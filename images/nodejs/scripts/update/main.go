// Command update refreshes everything this image is pinned to:
//
//   - the Debian package closure in config.amd64.json / config.arm64.json,
//     re-resolved against the Debian suite via the container hardening workbench
//   - the Node.js pin of every stream in flake.nix (version plus the amd64 and
//     arm64 tarball hashes), taken from the current upstream release of that
//     stream
//
// Run it from this directory:
//
//	go run .
package main

import (
	"bytes"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"gitlab.opencode.de/open-code/oci/container-hardening-work-bench/cmd"
)

// One "<major>" = { version = "..."; hashes = { amd64 = "..."; arm64 = "..."; }; }
// entry of the nodejsSources attribute set in flake.nix.
var nodePinRe = regexp.MustCompile(`(?m)^([ \t]*)"(\d+)" = \{[ \t]*\n` +
	`[ \t]*version = "([^"]+)";[ \t]*\n` +
	`[ \t]*hashes = \{[ \t]*\n` +
	`[ \t]*amd64 = "([^"]+)";[ \t]*\n` +
	`[ \t]*arm64 = "([^"]+)";[ \t]*\n` +
	`[ \t]*\};[ \t]*\n` +
	`[ \t]*\};`)

// Snapshot timestamp in a snapshot.debian.org URL, e.g. .../debian/20260907T000000Z/pool/...
var snapshotRe = regexp.MustCompile(`snapshot\.debian\.org/archive/debian(?:-security)?/(\d{8}T\d{6}Z)/`)

// arches maps the Debian architecture used throughout this repo to the
// architecture slug in a Node.js tarball name.
var arches = []struct{ debian, node string }{
	{"amd64", "x64"},
	{"arm64", "arm64"},
}

// exitNoUpdate is returned with -failIfNoUpdate when neither the Debian
// packages nor the Node.js streams offered a new version.
const exitNoUpdate = 3

func main() {
	root := repoRoot()

	config := flag.String("config", filepath.Join(root, "config"), "base path of the deb2nix config pair")
	flake := flag.String("flake", filepath.Join(root, "flake.nix"), "path to the flake.nix holding the nodejsSources pins")
	suite := flag.String("debianVersion", "13", "Debian suite to resolve against")
	streams := flag.String("streams", "", "comma separated Node.js streams to update (default: every stream in flake.nix)")
	skipDebian := flag.Bool("skipDebian", false, "skip the Debian package config update")
	skipNode := flag.Bool("skipNode", false, "skip the Node.js source update")
	prefetch := flag.Bool("prefetch", false, "hash the tarballs with nix-prefetch-url instead of reading SHASUMS256.txt")
	revertSnapshotOnly := flag.Bool("revertSnapshotOnly", false, "restore the previous config when only the snapshot date changed")
	failIfNoUpdate := flag.Bool("failIfNoUpdate", false, fmt.Sprintf("exit with %d when no new versions are available", exitNoUpdate))
	flag.Parse()

	var (
		debianDiffs []configDiff
		debianRan   bool
		nodePins    []nodePin
		nodeRan     bool
	)

	if !*skipDebian {
		diffs, err := updateDebianConfig(*config, *suite, *revertSnapshotOnly)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		debianDiffs, debianRan = diffs, true
	}

	if !*skipNode {
		pins, err := updateNodeSources(*flake, splitStreams(*streams), *prefetch)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		nodePins, nodeRan = pins, true
	}

	updated := report(debianDiffs, debianRan, nodePins, nodeRan)
	if !updated && *failIfNoUpdate {
		os.Exit(exitNoUpdate)
	}
}

// repoRoot walks up from the working directory to the checkout holding
// flake.nix, so the tool can be run from anywhere in the repo.
func repoRoot() string {
	dir, err := os.Getwd()
	if err != nil {
		return ".."
	}
	for {
		if _, err := os.Stat(filepath.Join(dir, "flake.nix")); err == nil {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return ".."
		}
		dir = parent
	}
}

func splitStreams(list string) map[string]bool {
	if strings.TrimSpace(list) == "" {
		return nil
	}
	only := map[string]bool{}
	for _, s := range strings.Split(list, ",") {
		if s = strings.TrimSpace(s); s != "" {
			only[s] = true
		}
	}
	return only
}

// --- Debian package configs -------------------------------------------------

type pkgState struct {
	Version string
	SHA256  string
	URL     string
}

// usable reports whether nix can actually fetch this package: the workbench
// leaves the hash empty and the <ARCHITECTURE> placeholder in the URL when its
// prefetch failed, and writes the package out anyway.
func (p pkgState) usable() bool {
	return p.SHA256 != "" && p.URL != "" && !strings.Contains(p.URL, "<ARCHITECTURE>")
}

// configState is what a single arch config looked like at a point in time.
type configState struct {
	Path     string
	Raw      []byte
	Exists   bool
	Packages map[string]pkgState
	Snapshot string
}

// brokenPackages names every package that would not be fetchable, as
// "<config file>: <package>".
func brokenPackages(states []configState) []string {
	var broken []string
	for _, state := range states {
		names := make([]string, 0, len(state.Packages))
		for name, pkg := range state.Packages {
			if !pkg.usable() {
				names = append(names, name)
			}
		}
		sort.Strings(names)
		for _, name := range names {
			broken = append(broken, fmt.Sprintf("%s: %s", filepath.Base(state.Path), name))
		}
	}
	return broken
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

	after := make([]configState, 0, len(paths))
	for _, prev := range before {
		next, err := readConfigState(prev.Path)
		if err != nil {
			return nil, err
		}
		if !next.Exists {
			return nil, fmt.Errorf("config %s missing after update", prev.Path)
		}
		after = append(after, next)
	}

	// A package whose prefetch failed - snapshot.debian.org serving a 503, say -
	// is written back with an empty hash and an unsubstituted URL instead of
	// failing the run, which would leave the image unbuildable. Roll the whole
	// update back rather than commit a config like that.
	if broken := brokenPackages(after); len(broken) > 0 {
		for _, prev := range before {
			if !prev.Exists {
				continue
			}
			if err := os.WriteFile(prev.Path, prev.Raw, 0644); err != nil {
				return nil, fmt.Errorf("failed to restore %s: %w", prev.Path, err)
			}
		}
		return nil, fmt.Errorf("could not fetch %s - the previous configs were restored, please retry",
			strings.Join(broken, ", "))
	}

	diffs := make([]configDiff, 0, len(paths))
	for i, prev := range before {
		next := after[i]

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
		state.Packages[pkg.Name] = pkgState{Version: pkg.Version, SHA256: pkg.SHA256, URL: pkg.URL}
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

// --- Node.js sources --------------------------------------------------------

type nodePin struct {
	Major, From, To string
	Skipped         bool
}

func (p nodePin) changed() bool { return p.From != p.To }

func updateNodeSources(path string, only map[string]bool, prefetch bool) ([]nodePin, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	releases, err := fetchNodeReleases()
	if err != nil {
		return nil, err
	}

	var (
		failure error
		pins    []nodePin
	)
	out := nodePinRe.ReplaceAllStringFunc(string(data), func(match string) string {
		if failure != nil {
			return match
		}

		g := nodePinRe.FindStringSubmatch(match)
		indent, major, current := g[1], g[2], g[3]
		currentHashes := map[string]string{"amd64": g[4], "arm64": g[5]}

		if len(only) > 0 && !only[major] {
			fmt.Printf("nodejs %s: %s (skipped)\n", major, current)
			pins = append(pins, nodePin{major, current, current, true})
			return match
		}

		latest := latestRelease(releases, major)
		if latest == "" {
			failure = fmt.Errorf("no linux release found for Node.js %s", major)
			return match
		}

		hashes, err := releaseHashes(latest, prefetch)
		if err != nil {
			failure = fmt.Errorf("failed to hash Node.js %s: %w", latest, err)
			return match
		}

		if latest == current {
			// The pin is current, so the recorded hashes must still be the ones
			// upstream publishes. If they are not, the pin is wrong or the
			// release was re-cut, and that is worth failing on rather than
			// leaving in place.
			if err := verifyHashes(current, currentHashes, hashes); err != nil {
				failure = err
				return match
			}
			fmt.Printf("nodejs %s: %s (up to date)\n", major, current)
			pins = append(pins, nodePin{major, current, current, false})
			return match
		}

		fmt.Printf("nodejs %s: %s -> %s\n", major, current, latest)
		pins = append(pins, nodePin{major, current, latest, false})
		return renderPin(indent, major, latest, hashes)
	})
	if failure != nil {
		return nil, failure
	}

	if out == string(data) {
		return pins, nil
	}
	return pins, os.WriteFile(path, []byte(out), 0644)
}

// renderPin writes the attribute set back in the layout nixfmt produces, so a
// rewritten pin does not show up as a formatting diff.
func renderPin(indent, major, version string, hashes map[string]string) string {
	inner := indent + "  "
	hash := inner + "  "
	return fmt.Sprintf("%s\"%s\" = {\n%sversion = \"%s\";\n%shashes = {\n%samd64 = \"%s\";\n%sarm64 = \"%s\";\n%s};\n%s};",
		indent, major,
		inner, version,
		inner,
		hash, hashes["amd64"],
		hash, hashes["arm64"],
		inner,
		indent)
}

func verifyHashes(version string, pinned, upstream map[string]string) error {
	for _, arch := range arches {
		if pinned[arch.debian] != upstream[arch.debian] {
			return fmt.Errorf("hash mismatch for Node.js %s (%s): flake.nix pins %s, upstream publishes %s",
				version, arch.debian, pinned[arch.debian], upstream[arch.debian])
		}
	}
	return nil
}

type nodeRelease struct {
	Version string   `json:"version"`
	Files   []string `json:"files"`
}

// fetchNodeReleases returns every release that ships both linux tarballs this
// image builds from, newest first.
func fetchNodeReleases() ([]nodeRelease, error) {
	body, err := httpGet("https://nodejs.org/dist/index.json")
	if err != nil {
		return nil, err
	}

	var all []nodeRelease
	if err := json.Unmarshal(body, &all); err != nil {
		return nil, fmt.Errorf("failed to parse the Node.js release index: %w", err)
	}

	releases := make([]nodeRelease, 0, len(all))
	for _, release := range all {
		if hasFile(release, "linux-x64") && hasFile(release, "linux-arm64") {
			releases = append(releases, release)
		}
	}
	return releases, nil
}

func hasFile(release nodeRelease, want string) bool {
	for _, file := range release.Files {
		if file == want {
			return true
		}
	}
	return false
}

// latestRelease returns the highest minor.patch release of a stream, e.g.
// "26.8.1" for major "26".
func latestRelease(releases []nodeRelease, major string) string {
	bestMinor, bestPatch := -1, -1
	for _, release := range releases {
		rest, ok := strings.CutPrefix(release.Version, "v"+major+".")
		if !ok {
			continue
		}
		minorStr, patchStr, ok := strings.Cut(rest, ".")
		if !ok {
			continue
		}
		minor, err := strconv.Atoi(minorStr)
		if err != nil {
			continue
		}
		patch, err := strconv.Atoi(patchStr)
		if err != nil {
			continue
		}
		if minor > bestMinor || (minor == bestMinor && patch > bestPatch) {
			bestMinor, bestPatch = minor, patch
		}
	}
	if bestMinor < 0 {
		return ""
	}
	return fmt.Sprintf("%s.%d.%d", major, bestMinor, bestPatch)
}

func tarballURL(version, nodeArch string) string {
	return fmt.Sprintf("https://nodejs.org/dist/v%s/node-v%s-linux-%s.tar.xz", version, version, nodeArch)
}

// releaseHashes returns the SRI hash of both linux tarballs of a release.
//
// The hashes come from the SHASUMS256.txt upstream publishes next to the
// tarballs - that is the same digest nix verifies after fetching, without
// downloading a hundred megabytes to find it out. With -prefetch the tarballs
// are downloaded and hashed by nix instead.
func releaseHashes(version string, prefetch bool) (map[string]string, error) {
	if prefetch {
		hashes := make(map[string]string, len(arches))
		for _, arch := range arches {
			hash, err := prefetchSRI(tarballURL(version, arch.node))
			if err != nil {
				return nil, err
			}
			hashes[arch.debian] = hash
		}
		return hashes, nil
	}

	body, err := httpGet(fmt.Sprintf("https://nodejs.org/dist/v%s/SHASUMS256.txt", version))
	if err != nil {
		return nil, err
	}

	wanted := make(map[string]string, len(arches))
	for _, arch := range arches {
		wanted[fmt.Sprintf("node-v%s-linux-%s.tar.xz", version, arch.node)] = arch.debian
	}

	hashes := make(map[string]string, len(arches))
	for _, line := range strings.Split(string(body), "\n") {
		fields := strings.Fields(line)
		if len(fields) != 2 {
			continue
		}
		arch, ok := wanted[fields[1]]
		if !ok {
			continue
		}
		sri, err := sriFromHex(fields[0])
		if err != nil {
			return nil, fmt.Errorf("%s: %w", fields[1], err)
		}
		hashes[arch] = sri
	}

	for _, arch := range arches {
		if hashes[arch.debian] == "" {
			return nil, fmt.Errorf("SHASUMS256.txt of v%s lists no linux-%s tarball", version, arch.node)
		}
	}
	return hashes, nil
}

// sriFromHex turns the hex digest of SHASUMS256.txt into the SRI spelling nix
// expects, e.g. "sha256-PjARGNffU9Vjt+lsFhdUXybi92+XJL5mjWyrZcFd2l0=".
func sriFromHex(digest string) (string, error) {
	raw, err := hex.DecodeString(digest)
	if err != nil {
		return "", fmt.Errorf("not a hex digest: %q", digest)
	}
	if len(raw) != 32 {
		return "", fmt.Errorf("not a sha256 digest: %q", digest)
	}
	return "sha256-" + base64.StdEncoding.EncodeToString(raw), nil
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

func httpGet(url string) ([]byte, error) {
	resp, err := http.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("GET %s: %s", url, resp.Status)
	}
	return io.ReadAll(resp.Body)
}

// --- Reporting --------------------------------------------------------------

// report prints the summary and returns whether a real update happened, i.e.
// a new package or Node.js version - not just a rewritten snapshot date.
func report(diffs []configDiff, debianRan bool, pins []nodePin, nodeRan bool) bool {
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

	fmt.Println()
	nodeUpdated := false
	if nodeRan {
		for _, p := range pins {
			if p.changed() {
				fmt.Printf("nodejs %s: %s -> %s\n", p.Major, p.From, p.To)
				nodeUpdated = true
			}
		}
		if nodeUpdated {
			fmt.Println("Node.js sources: updated")
		} else {
			fmt.Println("Node.js sources: no update available - every stream is on its latest release")
		}
	} else {
		fmt.Println("Node.js sources: skipped")
	}

	fmt.Println()
	updated := debianUpdated || nodeUpdated
	if updated {
		fmt.Println("Result: update available - configs and/or pins were changed.")
		return true
	}
	if debianRan && anySnapshotOnly(diffs) {
		fmt.Println("Result: no update available. Only the snapshot.debian.org date in the package URLs was updated;")
		fmt.Println("        no package or Node.js version changed, so the resulting image content is the same.")
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
