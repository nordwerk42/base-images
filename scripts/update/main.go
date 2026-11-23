package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"gitlab.opencode.de/open-code/oci/container-hardening-work-bench/cmd"
)

var pythonPinRe = regexp.MustCompile(`("(\d+\.\d+)" = \{\s+version = ")([^"]+)(";\s+hash = ")([^"]+)(";)`)

var pythonReleaseRe = regexp.MustCompile(`href="(\d+\.\d+\.\d+)/"`)

// Snapshot timestamp in a snapshot.debian.org URL, e.g. .../debian/20260907T000000Z/pool/...
var snapshotRe = regexp.MustCompile(`snapshot\.debian\.org/archive/debian(?:-security)?/(\d{8}T\d{6}Z)/`)

// exitNoUpdate is returned with -failIfNoUpdate when neither the Debian
// packages nor the Python sources offered a new version.
const exitNoUpdate = 3

func main() {
	config := flag.String("config", "../../config", "base path of the deb2nix config pair")
	flake := flag.String("flake", "../../flake.nix", "path to the flake.nix holding the pythonSources pins")
	suite := flag.String("debianVersion", "13", "Debian suite to resolve against")
	skipDebian := flag.Bool("skipDebian", false, "skip the Debian package config update")
	skipPython := flag.Bool("skipPython", false, "skip the Python source update")
	revertSnapshotOnly := flag.Bool("revertSnapshotOnly", false, "restore the previous config when only the snapshot date changed")
	failIfNoUpdate := flag.Bool("failIfNoUpdate", false, fmt.Sprintf("exit with %d when no new versions are available", exitNoUpdate))
	flag.Parse()

	var (
		debianDiffs []configDiff
		debianRan   bool
		pythonPins  []pythonPin
		pythonRan   bool
	)

	if !*skipDebian {
		diffs, err := updateDebianConfig(*config, *suite, *revertSnapshotOnly)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		debianDiffs, debianRan = diffs, true
	}

	if !*skipPython {
		pins, err := updatePythonSources(*flake)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		pythonPins, pythonRan = pins, true
	}

	updated := report(debianDiffs, debianRan, pythonPins, pythonRan)
	if !updated && *failIfNoUpdate {
		os.Exit(exitNoUpdate)
	}
}

// --- Debian package configs -------------------------------------------------

type pkgState struct {
	Version string
	SHA256  string
}

// configState is what a single arch config looked like at a point in time.
type configState struct {
	Path     string
	Raw      []byte
	Exists   bool
	Packages map[string]pkgState
	Snapshot string
}

type versionChange struct {
	Name, From, To string
}

type configDiff struct {
	Path                     string
	Created                  bool
	Added, Removed           []string
	Changed                  []versionChange
	Rebuilt                  []string // same version, different tarball hash
	SnapshotFrom, SnapshotTo string
	RawChanged               bool
	Reverted                 bool // snapshot-only change, rolled back on request
}

// hasVersionChange reports whether the resolved package set actually moved,
// as opposed to the URLs merely pointing at a newer snapshot mirror.
func (d configDiff) hasVersionChange() bool {
	return d.Created || len(d.Added) > 0 || len(d.Removed) > 0 || len(d.Changed) > 0 || len(d.Rebuilt) > 0
}

// snapshotOnly reports whether the file changed, but only because the
// snapshot.debian.org date in the URLs was rewritten.
func (d configDiff) snapshotOnly() bool {
	return (d.RawChanged || d.Reverted) && !d.hasVersionChange()
}

func updateDebianConfig(configBase, suite string, revertSnapshotOnly bool) ([]configDiff, error) {
	paths := []string{configBase + ".amd64.json", configBase + ".arm64.json"}

	before := make([]configState, 0, len(paths))
	for _, path := range paths {
		state, err := readConfigState(path)
		if err != nil {
			return nil, err
		}
		before = append(before, state)
	}

	if err := cmd.UpdateConfig(configBase, suite, true, nil); err != nil {
		return nil, err
	}

	diffs := make([]configDiff, 0, len(paths))
	for _, prev := range before {
		next, err := readConfigState(prev.Path)
		if err != nil {
			return nil, err
		}
		if !next.Exists {
			return nil, fmt.Errorf("config %s missing after update", prev.Path)
		}

		diff := diffConfig(prev, next)
		if diff.snapshotOnly() && revertSnapshotOnly {
			if err := os.WriteFile(prev.Path, prev.Raw, 0644); err != nil {
				return nil, fmt.Errorf("failed to restore %s: %w", prev.Path, err)
			}
			diff.RawChanged, diff.Reverted = false, true
			fmt.Printf("%s: restored previous config (snapshot-only change)\n", prev.Path)
		}
		diffs = append(diffs, diff)
	}
	return diffs, nil
}

func readConfigState(path string) (configState, error) {
	state := configState{Path: path, Packages: map[string]pkgState{}}

	raw, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return state, nil
	}
	if err != nil {
		return state, fmt.Errorf("failed to read %s: %w", path, err)
	}
	state.Raw, state.Exists = raw, true

	var wrapper struct {
		Packages []struct {
			Name    string `json:"name"`
			Version string `json:"version"`
			URL     string `json:"url"`
			SHA256  string `json:"sha256"`
		} `json:"packages"`
	}
	if err := json.Unmarshal(raw, &wrapper); err != nil {
		return state, fmt.Errorf("failed to parse %s: %w", path, err)
	}

	for _, pkg := range wrapper.Packages {
		state.Packages[pkg.Name] = pkgState{Version: pkg.Version, SHA256: pkg.SHA256}
		if state.Snapshot == "" {
			if m := snapshotRe.FindStringSubmatch(pkg.URL); m != nil {
				state.Snapshot = m[1]
			}
		}
	}
	return state, nil
}

func diffConfig(prev, next configState) configDiff {
	diff := configDiff{
		Path:         next.Path,
		Created:      !prev.Exists,
		SnapshotFrom: prev.Snapshot,
		SnapshotTo:   next.Snapshot,
		RawChanged:   !bytes.Equal(prev.Raw, next.Raw),
	}
	if diff.Created {
		return diff
	}

	for name, after := range next.Packages {
		before, ok := prev.Packages[name]
		switch {
		case !ok:
			diff.Added = append(diff.Added, fmt.Sprintf("%s %s", name, after.Version))
		case before.Version != after.Version:
			diff.Changed = append(diff.Changed, versionChange{name, before.Version, after.Version})
		case before.SHA256 != after.SHA256:
			diff.Rebuilt = append(diff.Rebuilt, fmt.Sprintf("%s %s", name, after.Version))
		}
	}
	for name, before := range prev.Packages {
		if _, ok := next.Packages[name]; !ok {
			diff.Removed = append(diff.Removed, fmt.Sprintf("%s %s", name, before.Version))
		}
	}

	sort.Strings(diff.Added)
	sort.Strings(diff.Removed)
	sort.Strings(diff.Rebuilt)
	sort.Slice(diff.Changed, func(i, j int) bool { return diff.Changed[i].Name < diff.Changed[j].Name })
	return diff
}

// --- Python sources ---------------------------------------------------------

type pythonPin struct {
	Minor, From, To string
}

func (p pythonPin) changed() bool { return p.From != p.To }

func updatePythonSources(path string) ([]pythonPin, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	releases, err := fetchPythonReleases()
	if err != nil {
		return nil, err
	}

	var (
		failure error
		pins    []pythonPin
	)
	out := pythonPinRe.ReplaceAllStringFunc(string(data), func(match string) string {
		if failure != nil {
			return match
		}

		g := pythonPinRe.FindStringSubmatch(match)
		minor, current := g[2], g[3]

		latest := latestPatch(releases, minor)
		if latest == "" {
			failure = fmt.Errorf("no release found for %s", minor)
			return match
		}
		if latest == current {
			fmt.Printf("python %s: %s (up to date)\n", minor, current)
			pins = append(pins, pythonPin{minor, current, current})
			return match
		}

		hash, err := prefetchSRI(tarballURL(latest))
		if err != nil {
			failure = fmt.Errorf("failed to prefetch Python %s: %w", latest, err)
			return match
		}

		fmt.Printf("python %s: %s -> %s\n", minor, current, latest)
		pins = append(pins, pythonPin{minor, current, latest})
		return g[1] + latest + g[4] + hash + g[6]
	})
	if failure != nil {
		return nil, failure
	}

	if out == string(data) {
		return pins, nil
	}
	return pins, os.WriteFile(path, []byte(out), 0644)
}

func fetchPythonReleases() ([]string, error) {
	resp, err := http.Get("https://www.python.org/ftp/python/")
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	var releases []string
	for _, m := range pythonReleaseRe.FindAllStringSubmatch(string(body), -1) {
		releases = append(releases, m[1])
	}
	return releases, nil
}

func latestPatch(releases []string, minor string) string {
	best := -1
	for _, v := range releases {
		patch, ok := strings.CutPrefix(v, minor+".")
		if !ok {
			continue
		}
		n, err := strconv.Atoi(patch)
		if err != nil {
			continue
		}
		if n > best {
			best = n
		}
	}
	if best < 0 {
		return ""
	}
	return fmt.Sprintf("%s.%d", minor, best)
}

func tarballURL(version string) string {
	return fmt.Sprintf("https://www.python.org/ftp/python/%s/Python-%s.tar.xz", version, version)
}

func prefetchSRI(url string) (string, error) {
	raw, err := exec.Command("nix-prefetch-url", "--type", "sha256", url).Output()
	if err != nil {
		return "", err
	}
	sri, err := exec.Command("nix", "hash", "convert", "--hash-algo", "sha256", "--to", "sri", strings.TrimSpace(string(raw))).Output()
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(sri)), nil
}

// --- Reporting --------------------------------------------------------------

// report prints the summary and returns whether a real update happened, i.e.
// a new package or Python version - not just a rewritten snapshot date.
func report(diffs []configDiff, debianRan bool, pins []pythonPin, pythonRan bool) bool {
	fmt.Println("\n=== Update summary ===")

	debianUpdated := false
	if debianRan {
		for _, d := range diffs {
			fmt.Printf("\n%s:\n", d.Path)
			switch {
			case d.Created:
				fmt.Println("  created")
			case d.hasVersionChange():
				for _, c := range d.Changed {
					fmt.Printf("  updated: %s %s -> %s\n", c.Name, c.From, c.To)
				}
				for _, a := range d.Added {
					fmt.Printf("  added:   %s\n", a)
				}
				for _, r := range d.Removed {
					fmt.Printf("  removed: %s\n", r)
				}
				for _, r := range d.Rebuilt {
					fmt.Printf("  rebuilt: %s (same version, new checksum)\n", r)
				}
			case d.Reverted:
				fmt.Println("  no package version changed - snapshot-only rewrite was reverted")
			case d.RawChanged:
				fmt.Println("  no package version changed - only the snapshot.debian.org URLs were rewritten")
			default:
				fmt.Println("  unchanged")
			}
			if d.SnapshotFrom != "" && d.SnapshotTo != "" && d.SnapshotFrom != d.SnapshotTo {
				fmt.Printf("  snapshot: %s -> %s\n", d.SnapshotFrom, d.SnapshotTo)
			}
			debianUpdated = debianUpdated || d.hasVersionChange()
		}

		fmt.Println()
		switch {
		case debianUpdated:
			fmt.Println("Debian packages: updated")
		case anySnapshotOnly(diffs):
			fmt.Println("Debian packages: no update available - only the snapshot date changed, package versions are identical")
		default:
			fmt.Println("Debian packages: no update available - configs unchanged")
		}
	} else {
		fmt.Println("\nDebian packages: skipped")
	}

	pythonUpdated := false
	if pythonRan {
		for _, p := range pins {
			if p.changed() {
				fmt.Printf("python %s: %s -> %s\n", p.Minor, p.From, p.To)
				pythonUpdated = true
			}
		}
		if !pythonUpdated {
			fmt.Println("Python sources: no update available - all pins are on the latest patch release")
		} else {
			fmt.Println("Python sources: updated")
		}
	} else {
		fmt.Println("Python sources: skipped")
	}

	fmt.Println()
	updated := debianUpdated || pythonUpdated
	if updated {
		fmt.Println("Result: update available - configs and/or pins were changed.")
		return true
	}
	if debianRan && anySnapshotOnly(diffs) {
		fmt.Println("Result: no update available. Only the snapshot.debian.org date in the package URLs was updated;")
		fmt.Println("        no package or Python version changed, so the resulting image content is the same.")
		if !anyReverted(diffs) {
			fmt.Println("        Use -revertSnapshotOnly to drop that diff.")
		}
		return false
	}
	fmt.Println("Result: no update available. Nothing changed.")
	return false
}

func anySnapshotOnly(diffs []configDiff) bool {
	for _, d := range diffs {
		if d.snapshotOnly() {
			return true
		}
	}
	return false
}

func anyReverted(diffs []configDiff) bool {
	for _, d := range diffs {
		if d.Reverted {
			return true
		}
	}
	return false
}
