package main

import (
	"strings"
	"testing"
)

func TestLatestRelease(t *testing.T) {
	releases := []nodeRelease{
		{Version: "v26.8.1"},
		{Version: "v26.10.0"}, // double digit minor, must beat 26.8.1
		{Version: "v26.9.0"},
		{Version: "v24.20.0"},
		{Version: "v24.9.1"},
		{Version: "v22.21.0"},
		{Version: "v26.x"}, // unparseable, must not win or panic
	}

	for _, tc := range []struct{ major, want string }{
		{"26", "26.10.0"},
		{"24", "24.20.0"},
		{"22", "22.21.0"},
		{"20", ""}, // stream not in the index
	} {
		if got := latestRelease(releases, tc.major); got != tc.want {
			t.Errorf("latestRelease(%q) = %q, want %q", tc.major, got, tc.want)
		}
	}
}

func TestSRIFromHex(t *testing.T) {
	// The published SHASUMS256.txt entry of node-v26.7.0-linux-x64.tar.xz and
	// the SRI hash that was pinned for it in flake.nix.
	const (
		digest = "982aa24dd8be4c889c6a8ab337ddff3b0896645b20f4239356e80552c16277ee"
		want   = "sha256-mCqiTdi+TIicaoqzN93/OwiWZFsg9COTVugFUsFid+4="
	)

	got, err := sriFromHex(digest)
	if err != nil {
		t.Fatalf("sriFromHex: %v", err)
	}
	if got != want {
		t.Errorf("sriFromHex(%q) = %q, want %q", digest, got, want)
	}

	if _, err := sriFromHex("not-hex"); err == nil {
		t.Error("sriFromHex accepted a non-hex digest")
	}
	if _, err := sriFromHex("abcd"); err == nil {
		t.Error("sriFromHex accepted a digest that is not 32 bytes")
	}
}

// The pin rewrite has to survive a round trip through flake.nix untouched:
// every stream is found, and re-rendering an unchanged pin reproduces the file
// byte for byte.
func TestNodePinRoundTrip(t *testing.T) {
	const flake = `      nodejsSources = {
        "24" = {
          version = "24.20.0";
          hashes = {
            amd64 = "sha256-amd64twentyfour=";
            arm64 = "sha256-arm64twentyfour=";
          };
        };
        "26" = {
          version = "26.8.1";
          hashes = {
            amd64 = "sha256-amd64twentysix=";
            arm64 = "sha256-arm64twentysix=";
          };
        };
      };
`

	matches := nodePinRe.FindAllStringSubmatch(flake, -1)
	if len(matches) != 2 {
		t.Fatalf("found %d pins, want 2", len(matches))
	}
	if matches[0][2] != "24" || matches[0][3] != "24.20.0" {
		t.Errorf("first pin = %q %q, want 24 24.20.0", matches[0][2], matches[0][3])
	}
	if matches[1][4] != "sha256-amd64twentysix=" || matches[1][5] != "sha256-arm64twentysix=" {
		t.Errorf("second pin hashes = %q %q", matches[1][4], matches[1][5])
	}

	rewritten := nodePinRe.ReplaceAllStringFunc(flake, func(match string) string {
		g := nodePinRe.FindStringSubmatch(match)
		return renderPin(g[1], g[2], g[3], map[string]string{"amd64": g[4], "arm64": g[5]})
	})
	if rewritten != flake {
		t.Errorf("re-rendering changed the file:\n%s", rewritten)
	}
}

func TestRenderPinUpdatesVersionAndHashes(t *testing.T) {
	got := renderPin("        ", "26", "26.9.0", map[string]string{
		"amd64": "sha256-new-amd64=",
		"arm64": "sha256-new-arm64=",
	})
	want := `        "26" = {
          version = "26.9.0";
          hashes = {
            amd64 = "sha256-new-amd64=";
            arm64 = "sha256-new-arm64=";
          };
        };`
	if got != want {
		t.Errorf("renderPin =\n%s\nwant\n%s", got, want)
	}
	if !nodePinRe.MatchString(got + "\n") {
		t.Error("renderPin output is not matched by nodePinRe, so the next run would not find it")
	}
}

func TestBrokenPackages(t *testing.T) {
	const url = "https://snapshot.debian.org/archive/debian/20260907T000000Z/pool/main/z/zlib/zlib1g_1_amd64.deb"

	states := []configState{
		{
			Path: "/repo/config.amd64.json",
			Packages: map[string]pkgState{
				"zlib1g": {Version: "1", SHA256: "abc", URL: url},
				// prefetch failed: no hash, architecture never substituted
				"libpcre2-8-0": {Version: "10.46", SHA256: "", URL: strings.Replace(url, "amd64", "<ARCHITECTURE>", 1)},
				"gcc-14-base":  {Version: "14.2.0", SHA256: "def", URL: strings.Replace(url, "amd64", "<ARCHITECTURE>", 1)},
			},
		},
		{
			Path: "/repo/config.arm64.json",
			Packages: map[string]pkgState{
				"zlib1g": {Version: "1", SHA256: "abc", URL: url},
			},
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
