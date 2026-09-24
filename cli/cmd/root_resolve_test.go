package cmd

import (
	"os"
	"path/filepath"
	"runtime/debug"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

func fixtureCheckout(t *testing.T, dir string) {
	t.Helper()
	for _, name := range []string{".git", "docker-compose.yml"} {
		if err := os.WriteFile(filepath.Join(dir, name), nil, 0600); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.Mkdir(filepath.Join(dir, "cli"), 0700); err != nil {
		t.Fatal(err)
	}
}

func TestInstallTargetResolution(t *testing.T) {
	base := t.TempDir()
	a, b := filepath.Join(base, "A"), filepath.Join(base, "B")
	home := filepath.Join(base, "home")
	defaultDir := filepath.Join(home, "statbus")
	for _, dir := range []string{a, b, defaultDir} {
		if err := os.MkdirAll(dir, 0700); err != nil {
			t.Fatal(err)
		}
		fixtureCheckout(t, dir)
	}
	outside := filepath.Join(base, "outside")
	if err := os.Mkdir(outside, 0700); err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		name, exe, cwd, home, want string
		refuse                     bool
	}{
		{"two checkouts: binary wins", filepath.Join(a, "sb"), b, home, a, false},
		{"binary under HOME/statbus from HOME", filepath.Join(defaultDir, "sb"), home, home, defaultDir, false},
		{"external binary uses cwd checkout", filepath.Join(outside, "sb"), b, home, b, false},
		{"external binary uses default checkout", filepath.Join(outside, "sb"), outside, home, defaultDir, false},
		{"no checkout refuses", filepath.Join(outside, "sb"), outside, outside, "", true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if err := os.WriteFile(tc.exe, nil, 0700); err != nil {
				t.Fatal(err)
			}
			got, err := resolveInstallDir(tc.exe, tc.cwd, tc.home)
			if got != tc.want || (err != nil) != tc.refuse {
				t.Fatalf("target=%q error=%v; want %q refusal=%v", got, err, tc.want, tc.refuse)
			}
			if tc.refuse && !strings.Contains(err.Error(), "cannot find a StatBus checkout") {
				t.Fatal(err)
			}
		})
	}
	link := filepath.Join(outside, "linked-sb")
	if err := os.Symlink(filepath.Join(a, "sb"), link); err != nil {
		t.Fatal(err)
	}
	if got, err := resolveInstallDir(link, b, home); err != nil || got != a {
		t.Fatalf("symlink target=%q error=%v", got, err)
	}
	old := installExecutable
	installExecutable = func() (string, error) { return filepath.Join(a, "sb"), nil }
	t.Cleanup(func() { installExecutable = old })
	oldWD, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Chdir(b); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chdir(oldWD) })
	if got, err := guardProjectDir(installCmd); err != nil || got != a {
		t.Fatalf("guard target=%q error=%v", got, err)
	}
	if got, err := guardProjectDir(restartCmd); err != nil || got != a {
		t.Fatalf("restart guard target=%q error=%v", got, err)
	}
	if got, err := installProjectDir(); err != nil || got != a {
		t.Fatalf("runInstall target=%q error=%v", got, err)
	}
}

// TestResolveCommitSHA_Tiers covers the full identity-resolution
// matrix that closes task #30 (freshness-debug).
//
// The pre-fix behavior used a raw `commit` global directly: when
// ldflags weren't set, `commit` stayed "unknown", and stalenessGuard
// skipped silently — but versionString separately consulted vcs.revision
// and printed a misleading commit short, masking the silent skip.
//
// The fix unifies on resolveCommitSHA: a typed result that is either
// a validated CommitSHA (Tier 1 ldflag, or Tier 2 clean vcs.revision)
// OR empty (Tier 3 ambiguous → refuse mutating). Both versionString
// and stalenessGuard consult only the typed value.
//
// These cases name the principle: identity comes from definitive or
// reliable sources, never from a "best-guess fallback".
func TestResolveCommitSHA_Tiers(t *testing.T) {
	const (
		validSHA      = "8292dd0c74df175665c99174de85566d530c3cf3"
		anotherSHA    = "137bd57d2487724014f9c10d3f73758f7e9f3932"
		shortNotValid = "8292dd0c"
		bogusNotValid = "not-a-sha"
	)

	tests := []struct {
		name      string
		ldflag    string
		buildInfo *debug.BuildInfo
		buildOK   bool
		want      string
	}{
		{
			name:    "tier1 ldflag valid",
			ldflag:  validSHA,
			buildOK: false,
			want:    validSHA,
		},
		{
			name:   "tier1 ldflag valid; vcs ignored even if present and different",
			ldflag: validSHA,
			buildInfo: &debug.BuildInfo{
				Settings: []debug.BuildSetting{
					{Key: "vcs.revision", Value: anotherSHA},
					{Key: "vcs.modified", Value: "false"},
				},
			},
			buildOK: true,
			want:    validSHA,
		},
		{
			name:    "tier1 ldflag '8292dd0c' (CommitShort, NOT a CommitSHA) — invalid for tier 1, falls through",
			ldflag:  shortNotValid,
			buildOK: false,
			want:    "",
		},
		{
			name:    "tier1 ldflag bogus — invalid shape, falls through to tier 2",
			ldflag:  bogusNotValid,
			buildOK: false,
			want:    "",
		},
		{
			name:   "tier2 clean vcs.revision",
			ldflag: "unknown",
			buildInfo: &debug.BuildInfo{
				Settings: []debug.BuildSetting{
					{Key: "vcs.revision", Value: validSHA},
					{Key: "vcs.modified", Value: "false"},
				},
			},
			buildOK: true,
			want:    validSHA,
		},
		{
			name:   "tier3 vcs.modified=true → refuse",
			ldflag: "unknown",
			buildInfo: &debug.BuildInfo{
				Settings: []debug.BuildSetting{
					{Key: "vcs.revision", Value: validSHA},
					{Key: "vcs.modified", Value: "true"},
				},
			},
			buildOK: true,
			want:    "",
		},
		{
			name:    "tier3 ldflag empty + no buildInfo → refuse",
			ldflag:  "",
			buildOK: false,
			want:    "",
		},
		{
			name:    "tier3 ldflag 'unknown' + no buildInfo → refuse",
			ldflag:  "unknown",
			buildOK: false,
			want:    "",
		},
		{
			name:   "tier3 vcs.revision missing settings → refuse",
			ldflag: "unknown",
			buildInfo: &debug.BuildInfo{
				Settings: []debug.BuildSetting{},
			},
			buildOK: true,
			want:    "",
		},
		{
			name:   "tier3 vcs.revision wrong shape (short) → refuse",
			ldflag: "unknown",
			buildInfo: &debug.BuildInfo{
				Settings: []debug.BuildSetting{
					{Key: "vcs.revision", Value: shortNotValid},
					{Key: "vcs.modified", Value: "false"},
				},
			},
			buildOK: true,
			want:    "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			fn := func() (*debug.BuildInfo, bool) { return tt.buildInfo, tt.buildOK }
			got := resolveCommitSHAFrom(tt.ldflag, fn)
			if string(got) != tt.want {
				t.Errorf("resolveCommitSHAFrom(%q, ...) = %q, want %q",
					tt.ldflag, got, tt.want)
			}
		})
	}
}

// TestVersionString_Consistency verifies that versionString and
// resolveCommitSHA agree on identity. Pre-fix versionString could
// surface a vcs.revision short while the freshness check saw "unknown"
// — making the binary look stamped while silently skipping the
// staleness check. The fix routes both through the same typed value.
//
// The test reaches in by setting the package globals (commitSHA,
// commitVersion) directly. Restored on cleanup. This mimics what
// init() does, so we can exercise versionString's three branches
// without rebuilding the binary.
func TestVersionString_Consistency(t *testing.T) {
	const (
		stampedSHA = "8292dd0c74df175665c99174de85566d530c3cf3"
	)

	origSHA := commitSHA
	origVer := commitVersion
	t.Cleanup(func() {
		commitSHA = origSHA
		commitVersion = origVer
	})

	tests := []struct {
		name     string
		sha      string
		ver      string
		wantSubs []string
	}{
		{
			name:     "tagged release",
			sha:      stampedSHA,
			ver:      "v2026.04.0-rc.66",
			wantSubs: []string{"v2026.04.0-rc.66", "8292dd0c"},
		},
		{
			name:     "dev with reliable identity",
			sha:      stampedSHA,
			ver:      "dev",
			wantSubs: []string{"dev", "8292dd0c"},
		},
		{
			name:     "dev unstamped — UNSTAMPED marker",
			sha:      "",
			ver:      "dev",
			wantSubs: []string{"UNSTAMPED"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			commitSHA = upgrade.CommitSHA(tt.sha)
			commitVersion = upgrade.CommitVersion(tt.ver)

			got := versionString()
			for _, sub := range tt.wantSubs {
				if !strings.Contains(got, sub) {
					t.Errorf("versionString() = %q, missing substring %q", got, sub)
				}
			}
		})
	}
}
