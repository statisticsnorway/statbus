package upgrade

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// ---------------------------------------------------------------------
// Smart constructor tests
// ---------------------------------------------------------------------

func TestNewCommitSHA(t *testing.T) {
	valid := []string{
		"61e79e265a1288e9babc7e3f2e9d4c51d5d42f01",
		"0000000000000000000000000000000000000000",
		"ffffffffffffffffffffffffffffffffffffffff",
	}
	invalid := []string{
		"",
		"61e79e26",
		"61E79E265a1288e9babc7e3f2e9d4c51d5d42f01", // uppercase
		"61e79e265a1288e9babc7e3f2e9d4c51d5d42f0",  // 39 chars
		"61e79e265a1288e9babc7e3f2e9d4c51d5d42f011", // 41 chars
		"sha-61e79e265a1288e9babc7e3f2e9d4c51d5d42f01",
		"v2026.04.0-rc.61",
		"dev",
	}
	for _, s := range valid {
		if _, err := NewCommitSHA(s); err != nil {
			t.Errorf("NewCommitSHA(%q) rejected valid input: %v", s, err)
		}
	}
	for _, s := range invalid {
		if _, err := NewCommitSHA(s); err == nil {
			t.Errorf("NewCommitSHA(%q) accepted invalid input", s)
		}
	}
}

func TestNewCommitShort(t *testing.T) {
	valid := []string{
		"61e79e26",
		"00000000",
		"ffffffff",
	}
	invalid := []string{
		"",
		"61e79e2",      // 7 chars
		"61e79e265",    // 9 chars
		"61E79E26",     // uppercase
		"sha-61e79e26", // prefix
		"v2026.04.0",
		"dev",
	}
	for _, s := range valid {
		if _, err := NewCommitShort(s); err != nil {
			t.Errorf("NewCommitShort(%q) rejected valid input: %v", s, err)
		}
	}
	for _, s := range invalid {
		if _, err := NewCommitShort(s); err == nil {
			t.Errorf("NewCommitShort(%q) accepted invalid input", s)
		}
	}
}

func TestNewReleaseTag(t *testing.T) {
	valid := []string{
		"v2026.04.0",
		"v2026.04.0-rc.61",
		"v2026.12.10-beta.2",
		"v2026.04.0-rc.1",
	}
	invalid := []string{
		"",
		"2026.04.0",     // missing v
		"2026.04.0-rc.61",
		"v26.04.0",      // too-short year
		"v2026.4.0",     // too-short month
		"v2026.04",      // missing patch
		"sha-abc12345",
		"dev",
		"install-verified",
		"61e79e26",
	}
	for _, s := range valid {
		if _, err := NewReleaseTag(s); err != nil {
			t.Errorf("NewReleaseTag(%q) rejected valid input: %v", s, err)
		}
	}
	for _, s := range invalid {
		if _, err := NewReleaseTag(s); err == nil {
			t.Errorf("NewReleaseTag(%q) accepted invalid input", s)
		}
	}
}

// ---------------------------------------------------------------------
// Shape-classification taxonomy — every string shape a guard could see
// ---------------------------------------------------------------------

// TestDisplayName_DiscriminatorsCoverAllShapes enumerates every
// accepted and rejected string shape the rc.63 rewrites must
// classify correctly. If a shape is added to the system, add a row
// here and update every affected call site.
func TestDisplayName_DiscriminatorsCoverAllShapes(t *testing.T) {
	cases := []struct {
		name        string
		input       string
		wantIsSHA   bool
		wantIsShort bool
		wantIsTag   bool
	}{
		// Full commit_sha
		{"full-sha-lowercase", "61e79e265a1288e9babc7e3f2e9d4c51d5d42f01", true, false, false},
		{"full-sha-mixed-case-rejected", "61E79E265a1288e9babc7e3f2e9d4c51d5d42f01", false, false, false},

		// commit_short (canonical 8-char)
		{"commit-short-lowercase", "61e79e26", false, true, false},
		{"commit-short-mixed-case-rejected", "61E79E26", false, false, false},
		{"commit-short-too-short", "61e79e2", false, false, false},
		{"commit-short-too-long", "61e79e265", false, false, false},

		// Legacy sha- prefix — all rejected post-rc.63
		{"legacy-sha-prefix-short", "sha-61e79e26", false, false, false},
		{"legacy-sha-prefix-12", "sha-61e79e265a12", false, false, false},
		{"legacy-sha-prefix-full", "sha-61e79e265a1288e9babc7e3f2e9d4c51d5d42f01", false, false, false},

		// Describe-off-tag — never reaches these guards (only stored in commit_version)
		{"describe-off-tag", "v2026.04.0-rc.61-3-g1a2b3c4d", false, false, false},

		// CalVer tags
		{"calver-v-prefix", "v2026.04.0-rc.61", false, false, true},
		{"calver-v-prefix-stable", "v2026.04.0", false, false, true},
		{"calver-no-v-prefix", "2026.04.0-rc.61", false, false, false},

		// Degraded-mode
		{"dev-literal", "dev", false, false, false},
		{"empty", "", false, false, false},
		{"unknown-literal", "unknown", false, false, false},

		// Unknowns that might reach the parser
		{"random-word", "foo", false, false, false},
		{"hex-of-wrong-length", "abc", false, false, false},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := isCommitSHAShape(c.input); got != c.wantIsSHA {
				t.Errorf("isCommitSHAShape(%q) = %v, want %v", c.input, got, c.wantIsSHA)
			}
			if got := isCommitShortShape(c.input); got != c.wantIsShort {
				t.Errorf("isCommitShortShape(%q) = %v, want %v", c.input, got, c.wantIsShort)
			}
			if got := isReleaseTagShape(c.input); got != c.wantIsTag {
				t.Errorf("isReleaseTagShape(%q) = %v, want %v", c.input, got, c.wantIsTag)
			}
		})
	}
}

// ---------------------------------------------------------------------
// Display-rendering tests
// ---------------------------------------------------------------------

func TestCommitShort(t *testing.T) {
	sha, err := NewCommitSHA("61e79e265a1288e9babc7e3f2e9d4c51d5d42f01")
	if err != nil {
		t.Fatalf("NewCommitSHA: %v", err)
	}
	if got := commitShort(sha); string(got) != "61e79e26" {
		t.Errorf("commitShort = %q, want %q", got, "61e79e26")
	}
}

func TestShortForDisplay(t *testing.T) {
	cases := []struct{ in, want string }{
		{"61e79e265a1288e9babc7e3f2e9d4c51d5d42f01", "61e79e26"},
		{"61e79e26", "61e79e26"},
		{"61e79e2", "61e79e2"}, // too short — passthrough
		{"dev", "dev"},
		{"", ""},
		{"unknown", "unknown"},
	}
	for _, c := range cases {
		if got := ShortForDisplay(c.in); got != c.want {
			t.Errorf("ShortForDisplay(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

func TestRenderDisplayName(t *testing.T) {
	sha, _ := NewCommitSHA("61e79e265a1288e9babc7e3f2e9d4c51d5d42f01")
	cases := []struct {
		name string
		sha  CommitSHA
		tags []string
		want string
	}{
		{"untagged-empty", sha, []string{}, "61e79e26"},
		{"untagged-nil", sha, nil, "61e79e26"},
		{"single-release-tag", sha, []string{"v2026.04.0-rc.61"}, "v2026.04.0-rc.61"},
		{"stable-and-rc", sha, []string{"v2026.04.0-rc.61", "v2026.04.0"}, "v2026.04.0"},
		{"stable-wins-regardless-of-order", sha, []string{"v2026.04.0", "v2026.04.0-rc.61"}, "v2026.04.0"},
		{"non-release-tag-falls-through", sha, []string{"arbitrary"}, "arbitrary"},
		{"mixed-release-and-arbitrary", sha, []string{"arbitrary", "v2026.04.0-rc.5"}, "v2026.04.0-rc.5"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := renderDisplayName(c.sha, c.tags); got != c.want {
				t.Errorf("renderDisplayName(%q, %v) = %q, want %q", c.sha, c.tags, got, c.want)
			}
		})
	}
}

func TestPreferredReleaseTag(t *testing.T) {
	cases := []struct {
		in   []string
		want string
	}{
		{nil, ""},
		{[]string{}, ""},
		{[]string{"v2026.04.0-rc.61"}, "v2026.04.0-rc.61"},
		{[]string{"v2026.04.0"}, "v2026.04.0"},
		{[]string{"v2026.04.0", "v2026.04.0-rc.61"}, "v2026.04.0"},
		{[]string{"v2026.04.0-rc.61", "v2026.04.0"}, "v2026.04.0"},
		{[]string{"arbitrary"}, "arbitrary"}, // fallback to last
		{[]string{"arbitrary", "v2026.04.0-rc.5"}, "v2026.04.0-rc.5"},
	}
	for _, c := range cases {
		if got := preferredReleaseTag(c.in); got != c.want {
			t.Errorf("preferredReleaseTag(%v) = %q, want %q", c.in, got, c.want)
		}
	}
}

// ---------------------------------------------------------------------
// Parser tests
// ---------------------------------------------------------------------

// fakeLookup implements CommitLookup for table-driven tests. Records
// which method was called so tests can assert routing behaviour.
type fakeLookup struct {
	tagsAtCommit map[CommitSHA][]string
	revParse     map[string]CommitSHA
	tagToSHA     map[ReleaseTag]CommitSHA
}

func (f *fakeLookup) LookupSHAByTag(_ context.Context, tag ReleaseTag) (CommitSHA, bool, error) {
	s, ok := f.tagToSHA[tag]
	return s, ok, nil
}
func (f *fakeLookup) RevParse(_ context.Context, ref string) (CommitSHA, error) {
	if s, ok := f.revParse[ref]; ok {
		return s, nil
	}
	return "", errors.New("unknown ref")
}
func (f *fakeLookup) TagsAtCommit(_ context.Context, sha CommitSHA) ([]string, error) {
	return f.tagsAtCommit[sha], nil
}

func TestResolveUpgradeTarget(t *testing.T) {
	full := CommitSHA("61e79e265a1288e9babc7e3f2e9d4c51d5d42f01")
	short := "61e79e26"
	tag := ReleaseTag("v2026.04.0-rc.61")

	lookup := &fakeLookup{
		tagsAtCommit: map[CommitSHA][]string{
			full: {"v2026.04.0-rc.61"},
			"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa": {},
		},
		revParse: map[string]CommitSHA{
			short: full,
			"v2026.04.0-rc.61": full,
		},
		tagToSHA: map[ReleaseTag]CommitSHA{
			tag: full,
		},
	}

	ctx := context.Background()

	t.Run("full-sha-tagged", func(t *testing.T) {
		got, err := resolveUpgradeTarget(ctx, lookup, string(full))
		if err != nil {
			t.Fatalf("resolveUpgradeTarget: %v", err)
		}
		tt, ok := got.(TaggedTarget)
		if !ok {
			t.Fatalf("got %T, want TaggedTarget", got)
		}
		if tt.SHA != full || tt.Tag != tag {
			t.Errorf("got %+v, want TaggedTarget{SHA: %s, Tag: %s}", tt, full, tag)
		}
	})

	t.Run("full-sha-untagged", func(t *testing.T) {
		got, err := resolveUpgradeTarget(ctx, lookup, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
		if err != nil {
			t.Fatalf("resolveUpgradeTarget: %v", err)
		}
		ut, ok := got.(UntaggedTarget)
		if !ok {
			t.Fatalf("got %T, want UntaggedTarget", got)
		}
		if ut.SHA != "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" {
			t.Errorf("got %+v, want SHA=aaaa...", ut)
		}
	})

	t.Run("short-resolves-to-tagged", func(t *testing.T) {
		got, err := resolveUpgradeTarget(ctx, lookup, short)
		if err != nil {
			t.Fatalf("resolveUpgradeTarget: %v", err)
		}
		tt, ok := got.(TaggedTarget)
		if !ok {
			t.Fatalf("got %T, want TaggedTarget", got)
		}
		if tt.SHA != full || tt.Tag != tag {
			t.Errorf("got %+v, want TaggedTarget{SHA: %s, Tag: %s}", tt, full, tag)
		}
	})

	t.Run("release-tag-routes-via-lookup", func(t *testing.T) {
		got, err := resolveUpgradeTarget(ctx, lookup, string(tag))
		if err != nil {
			t.Fatalf("resolveUpgradeTarget: %v", err)
		}
		tt, ok := got.(TaggedTarget)
		if !ok {
			t.Fatalf("got %T, want TaggedTarget", got)
		}
		if tt.SHA != full || tt.Tag != tag {
			t.Errorf("got %+v, want TaggedTarget{SHA: %s, Tag: %s}", tt, full, tag)
		}
	})

	t.Run("legacy-sha-prefix-short-accepted-via-compat", func(t *testing.T) {
		// Transitional: the NOTIFY trigger emits "sha-<40>" until Commit B.
		// resolveUpgradeTarget strips the legacy prefix and retries.
		got, err := resolveUpgradeTarget(ctx, lookup, "sha-"+short)
		if err != nil {
			t.Fatalf("legacy sha- prefix rejected: %v", err)
		}
		if _, ok := got.(TaggedTarget); !ok {
			t.Errorf("got %T, want TaggedTarget (short resolves to tagged full SHA)", got)
		}
	})

	t.Run("legacy-sha-prefix-full-accepted-via-compat", func(t *testing.T) {
		got, err := resolveUpgradeTarget(ctx, lookup, "sha-"+string(full))
		if err != nil {
			t.Fatalf("legacy sha-<40> rejected: %v", err)
		}
		if _, ok := got.(TaggedTarget); !ok {
			t.Errorf("got %T, want TaggedTarget", got)
		}
	})

	t.Run("malformed-sha-prefix-rejected", func(t *testing.T) {
		// "sha-foobar" is not a valid hex remainder — should not be stripped.
		_, err := resolveUpgradeTarget(ctx, lookup, "sha-foobar")
		if err == nil {
			t.Errorf("sha-foobar accepted; want error")
		}
	})

	t.Run("dev-rejected", func(t *testing.T) {
		_, err := resolveUpgradeTarget(ctx, lookup, "dev")
		if err == nil {
			t.Errorf("dev accepted; want error")
		}
	})

	t.Run("empty-rejected", func(t *testing.T) {
		_, err := resolveUpgradeTarget(ctx, lookup, "")
		if err == nil {
			t.Errorf("empty accepted; want error")
		}
	})
}

// ---------------------------------------------------------------------
// Regression guard: assert the rest of the codebase uses typed fields,
// not string-shape detection.
// ---------------------------------------------------------------------

// TestGuards_UseTypedFields walks cli/ for live call sites of
// strings.HasPrefix / strings.TrimPrefix against the literal "sha-".
// Post-rc.63, only this file (commit.go — which doesn't call these,
// but the taxonomy regression lives here) and commit_test.go are
// exempt. Every other hit is a violation.
//
// This is the enforcement arm of the "one shape-detection site" rule.
// When it fails, either the violating site needs rewriting against
// typed fields, OR the exempt list needs a principled addition — never
// silent allowance.
func TestGuards_UseTypedFields(t *testing.T) {
	patterns := []*regexp.Regexp{
		regexp.MustCompile(`strings\.HasPrefix\([^,]*,\s*"sha-"\)`),
		regexp.MustCompile(`strings\.TrimPrefix\([^,]*,\s*"sha-"\)`),
	}
	// Files that legitimately name the legacy "sha-" literal. The
	// allowlist is minimal by design: every entry is justified in a
	// comment. Any new addition needs a principled rationale; never
	// silence a violation by adding to the list.
	allowFiles := map[string]bool{
		// commit.go: the sole shape-detection site. Contains the
		// stripLegacyShaPrefix helper for NOTIFY payload compatibility
		// during the Commit A → Commit B transition.
		"commit.go": true,
		// commit_test.go: this regression test file itself.
		"commit_test.go": true,
	}

	root := findRepoCLI(t)
	var violations []string
	err := filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() {
			if info.Name() == "vendor" || info.Name() == "lib" || strings.HasPrefix(info.Name(), ".") {
				return filepath.SkipDir
			}
			return nil
		}
		if !strings.HasSuffix(path, ".go") {
			return nil
		}
		if allowFiles[filepath.Base(path)] {
			return nil
		}
		body, readErr := os.ReadFile(path)
		if readErr != nil {
			return readErr
		}
		for _, re := range patterns {
			for _, loc := range re.FindAllIndex(body, -1) {
				line := lineContaining(body, loc[0])
				rel, _ := filepath.Rel(root, path)
				violations = append(violations, rel+": "+strings.TrimSpace(line))
			}
		}
		return nil
	})
	if err != nil {
		t.Fatalf("walk: %v", err)
	}
	if len(violations) > 0 {
		t.Errorf("Found %d violations of the one-shape-detection-site rule:\n  %s",
			len(violations), strings.Join(violations, "\n  "))
	}
}

// findRepoCLI returns the absolute path of cli/ at the current repo root,
// located by walking up from the test's working dir until a go.mod is
// found. Returns "" (causing a Fatalf in the caller) if the walk fails.
func findRepoCLI(t *testing.T) string {
	t.Helper()
	cwd, err := os.Getwd()
	if err != nil {
		t.Fatalf("getwd: %v", err)
	}
	for dir := cwd; dir != "/"; dir = filepath.Dir(dir) {
		if _, err := os.Stat(filepath.Join(dir, "go.mod")); err == nil {
			return dir
		}
	}
	t.Fatalf("could not find go.mod above %s", cwd)
	return ""
}

// lineContaining returns the line in body that contains byte offset
// off. Used for pretty-printing violations.
func lineContaining(body []byte, off int) string {
	start := off
	for start > 0 && body[start-1] != '\n' {
		start--
	}
	end := off
	for end < len(body) && body[end] != '\n' {
		end++
	}
	return string(body[start:end])
}
