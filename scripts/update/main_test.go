// Copyright 2025 Zentrum für Digitale Souveränität der Öffentlichen Verwaltung (ZenDiS) GmbH.
// SPDX-License-Identifier: MIT
package main

import (
	"strings"
	"testing"
)

const debURL = "https://snapshot.debian.org/archive/debian/20260907T000000Z/pool/main/z/zlib/zlib1g_1_amd64.deb"

func TestBrokenPackages(t *testing.T) {
	states := []configState{
		{
			Path: "/repo/config.amd64.json",
			Packages: map[string]pkgState{
				"zlib1g":       {Version: "1", SHA256: "abc", URL: debURL},
				"libpcre2-8-0": {Version: "10.46", SHA256: "", URL: strings.Replace(debURL, "amd64", "<ARCHITECTURE>", 1)},
				"gcc-14-base":  {Version: "14.2.0", SHA256: "def", URL: strings.Replace(debURL, "amd64", "<ARCHITECTURE>", 1)},
			},
		},
		{
			Path:     "/repo/config.arm64.json",
			Packages: map[string]pkgState{"zlib1g": {Version: "1", SHA256: "abc", URL: debURL}},
		},
	}

	got := brokenPackages(states)
	want := []string{"config.amd64.json: gcc-14-base", "config.amd64.json: libpcre2-8-0"}
	if len(got) != len(want) {
		t.Fatalf("brokenPackages = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("brokenPackages[%d] = %q, want %q", i, got[i], want[i])
		}
	}

	if broken := brokenPackages(states[1:]); len(broken) != 0 {
		t.Errorf("brokenPackages on a healthy config = %v, want none", broken)
	}
}

func TestDiffConfig(t *testing.T) {
	state := func(path, raw, snapshot string, pkgs map[string]pkgState) configState {
		return configState{Path: path, Raw: []byte(raw), Exists: true, Packages: pkgs, Snapshot: snapshot}
	}

	prev := state("c.json", "old", "20260901T000000Z", map[string]pkgState{
		"zlib1g":   {Version: "1", SHA256: "abc"},
		"tzdata":   {Version: "2025b", SHA256: "def"},
		"openssl":  {Version: "3.5.7", SHA256: "ghi"},
		"debconf":  {Version: "1.5.91", SHA256: "jkl"},
		"libgcc-s": {Version: "14", SHA256: "mno"},
	})
	next := state("c.json", "new", "20260907T000000Z", map[string]pkgState{
		"zlib1g":  {Version: "2", SHA256: "abc"},
		"tzdata":  {Version: "2025b", SHA256: "xxx"},
		"openssl": {Version: "3.5.7", SHA256: "ghi"},
		"debconf": {Version: "1.5.91", SHA256: "jkl"},
		"libc6":   {Version: "2.41", SHA256: "pqr"},
	})

	diff := diffConfig(prev, next)
	if len(diff.Changed) != 1 || diff.Changed[0].Name != "zlib1g" || diff.Changed[0].To != "2" {
		t.Errorf("Changed = %v", diff.Changed)
	}
	if len(diff.Rebuilt) != 1 || !strings.HasPrefix(diff.Rebuilt[0], "tzdata") {
		t.Errorf("Rebuilt = %v", diff.Rebuilt)
	}
	if len(diff.Added) != 1 || !strings.HasPrefix(diff.Added[0], "libc6") {
		t.Errorf("Added = %v", diff.Added)
	}
	if len(diff.Removed) != 1 || !strings.HasPrefix(diff.Removed[0], "libgcc-s") {
		t.Errorf("Removed = %v", diff.Removed)
	}
	if !diff.hasVersionChange() || diff.snapshotOnly() {
		t.Error("a package version moved, so the diff must not count as snapshot-only")
	}
}

func TestDiffConfigSnapshotOnly(t *testing.T) {
	pkgs := map[string]pkgState{"zlib1g": {Version: "1", SHA256: "abc", URL: debURL}}
	prev := configState{Path: "c.json", Raw: []byte("old"), Exists: true, Packages: pkgs, Snapshot: "20260901T000000Z"}
	next := configState{Path: "c.json", Raw: []byte("new"), Exists: true, Packages: pkgs, Snapshot: "20260907T000000Z"}

	diff := diffConfig(prev, next)
	if diff.hasVersionChange() {
		t.Error("no package moved, hasVersionChange must be false")
	}
	if !diff.snapshotOnly() {
		t.Error("only the snapshot date moved, snapshotOnly must be true")
	}

	unchanged := diffConfig(prev, prev)
	if unchanged.RawChanged || unchanged.snapshotOnly() {
		t.Error("an identical config must report no change at all")
	}
}
