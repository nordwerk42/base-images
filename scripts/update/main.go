// Copyright 2025 Zentrum für Digitale Souveränität der Öffentlichen Verwaltung (ZenDiS) GmbH.
// SPDX-License-Identifier: MIT
package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"gitlab.opencode.de/open-code/oci/container-hardening-work-bench/cmd"
)

var snapshotRe = regexp.MustCompile(`snapshot\.debian\.org/archive/debian(?:-security)?/(\d{8}T\d{6}Z)/`)

const exitNoUpdate = 3

func main() {
	root := repoRoot()

	config := flag.String("config", filepath.Join(root, "config"), "base path of the deb2nix config pair")
	suite := flag.String("debianVersion", "13", "Debian suite to resolve against")
	revertSnapshotOnly := flag.Bool("revertSnapshotOnly", false, "restore the previous config when only the snapshot date changed")
	failIfNoUpdate := flag.Bool("failIfNoUpdate", false, fmt.Sprintf("exit with %d when no new versions are available", exitNoUpdate))
	flag.Parse()

	diffs, err := updateDebianConfig(*config, *suite, *revertSnapshotOnly)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	if !report(diffs) && *failIfNoUpdate {
		os.Exit(exitNoUpdate)
	}
}

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

type pkgState struct {
	Version string
	SHA256  string
	URL     string
}

func (p pkgState) usable() bool {
	return p.SHA256 != "" && p.URL != "" && !strings.Contains(p.URL, "<ARCHITECTURE>")
}

type configState struct {
	Path     string
	Raw      []byte
	Exists   bool
	Packages map[string]pkgState
	Snapshot string
}

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
	Rebuilt                  []string
	SnapshotFrom, SnapshotTo string
	RawChanged               bool
	Reverted                 bool
}

func (d configDiff) hasVersionChange() bool {
	return d.Created || len(d.Added) > 0 || len(d.Removed) > 0 || len(d.Changed) > 0 || len(d.Rebuilt) > 0
}

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
		diff := diffConfig(prev, after[i])
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

func report(diffs []configDiff) bool {
	fmt.Println("\n=== Update summary ===")

	updated := false
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
		updated = updated || d.hasVersionChange()
	}

	fmt.Println()
	if updated {
		fmt.Println("Result: update available - the configs were changed.")
		return true
	}
	if anySnapshotOnly(diffs) {
		fmt.Println("Result: no update available. Only the snapshot.debian.org date in the package URLs was updated;")
		fmt.Println("        no package version changed, so the resulting image content is the same.")
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
