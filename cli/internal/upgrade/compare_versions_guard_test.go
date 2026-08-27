package upgrade

import (
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"testing"
)

// readUpgradePackageFile reads a named source file from this package's own
// directory, so the pins below examine the code that SHIPS rather than a
// re-expression of it in a fixture.
func readUpgradePackageFile(t *testing.T, name string) string {
	t.Helper()
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	b, err := os.ReadFile(filepath.Join(filepath.Dir(thisFile), name))
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

// comparabilityBinding captures the name the comparability flag is bound to at
// each call — "_" when it is thrown away at the call site itself.
var comparabilityBinding = regexp.MustCompile(`,\s*([A-Za-z_][A-Za-z0-9_]*)\s*:?=\s*CompareVersions\(`)

// discardsNamedFlag reports whether a body launders a BOUND flag into the blank
// identifier (`_ = ordered`), which satisfies the compiler while ignoring the
// answer just as completely as discarding it at the call site.
func discardsNamedFlag(body, name string) bool {
	return regexp.MustCompile(`_\s*=\s*` + regexp.QuoteMeta(name) + `\b`).MatchString(body)
}

// TestNoCallerDiscardsCompareVersionsComparability_STATBUS293 is the pin that
// makes the STATBUS-293 defect unwritable rather than merely fixed.
//
// WHAT WENT WRONG. CompareVersions documented its own precondition in prose —
// "both inputs MUST be CalVer release tags… passing a non-CalVer string
// produces an undefined (but non-panicking) ordering" — and then answered
// anyway, with a confident int, by falling back to lexical comparison of the
// raw strings. Two of its callers held an installed version that is routinely
// an untagged commit, so they consumed that undefined answer as though it were
// defined. A box installed at commit 063d860a was offered every stable release
// back to v2026.03.0 as an "available upgrade" — downgrades presented as
// upgrades — while the same box at 5399acd8 behaved perfectly. The only
// difference between the two was the FIRST HEX CHARACTER of the SHA.
//
// WHAT THIS PIN COVERS, and the over-claim that was corrected by testing it.
// The fix changed the signature to (int, bool), so every call site had to be
// revisited — the compiler did that enumeration, not a human. What the compiler
// does NOT catch is a future caller consuming the ordering while ignoring
// whether one exists, re-creating the original defect one line at a time.
//
// This test FIRST pinned only `ord, _ := CompareVersions(...)`, on the argument
// that binding the flag is self-enforcing because Go rejects an unused
// short-declared variable. RED VERIFICATION REFUTED THAT ARGUMENT: a mutation
// writing `ord, ordered := ...` followed by `_ = ordered` compiled cleanly and
// sailed past the pin. The compiler is satisfied by the laundering assignment,
// so "it must be used" does not mean "it must be consulted".
//
// Both spellings are therefore checked: discarded at the call site, and bound
// then laundered into `_`. That is the set of ways to hold the flag and ignore
// it without the compiler objecting. A caller could still consult it and then
// do the wrong thing — no source scan can catch that, which is what the
// behavioural pin below is for.
//
// The correction is left visible on purpose. The original claim sounded
// rigorous and was wrong, and the only reason it did not ship is that the
// mutation was actually run instead of reasoned about.
//
// THE ENUMERATION IS DERIVED FROM THE SOURCE, not listed here. A hardcoded list
// of today's callers could not fail for a caller written next month — it would
// never examine one — so a test promising "every caller is guarded" while
// iterating a literal would be making a promise its own code does not keep.
func TestNoCallerDiscardsCompareVersionsComparability_STATBUS293(t *testing.T) {
	files := map[string]string{
		"service.go": readUpgradePackageFile(t, "service.go"),
		"github.go":  readUpgradePackageFile(t, "github.go"),
	}

	totalCallers := 0
	for name, src := range files {
		for _, fn := range functionsCalling(t, src, "CompareVersions(") {
			// CompareVersions' own declaration contains its name; it defines
			// the ordering rather than consuming one.
			if strings.HasPrefix(fn, "func CompareVersions(") {
				continue
			}
			totalCallers++

			body := extractFuncBody(t, src, fn)

			var bad string
			for _, m := range comparabilityBinding.FindAllStringSubmatch(body, -1) {
				if m[1] == "_" {
					bad = "discarded at the call site (`ord, _ := CompareVersions(...)`)"
					break
				}
				if discardsNamedFlag(body, m[1]) {
					bad = "bound as `" + m[1] + "` and then laundered away (`_ = " + m[1] + "`)"
					break
				}
			}
			if bad != "" {
				t.Errorf(`%s in %s ignores CompareVersions' comparability flag — %s.

Consuming an ordering without asking whether one exists is exactly the
STATBUS-293 defect, restored. When the flag is false the int is meaningless,
and acting on it offers a DOWNGRADE as an upgrade to whichever statistical
office runs this box.

Bind the flag and decide what "these two have no release ordering" means for
this call site — the answer differs per site and is spelled out at each one:
  - discovery / check: register NOTHING and say so, naming both ways forward
  - supersede:         retire NOTHING (dismissing a real candidate is worse)
  - selection:         skip the candidate`, fn, name, bad)
			}
		}
	}

	// Zero-scope guard: a scan that examines nothing must fail rather than
	// pass. The known consumers are discover, RunCheck,
	// selectNewestDownloadCandidate, selectNewestTag, selectStaleBelowInstalled
	// and executeUpgrade in service.go, plus selectLatestTagFromNames in
	// github.go. If the scan stops finding them, it has broken and is silently
	// asserting nothing — the precise failure this whole ticket is about.
	if totalCallers < 7 {
		t.Fatalf("found %d function(s) calling CompareVersions across service.go and github.go — expected at least the 7 known consumers; the scan is broken, so this test is asserting nothing", totalCallers)
	}
}

// TestDiscoveryPathsRefuseUnorderableInstalledVersion_STATBUS293 pins the
// BEHAVIOUR the flag exists to enable, at the two paths that register
// candidates. The pin above proves nobody ignores the flag; this one proves
// the two paths that matter act on it, and act LOUDLY.
//
// Both halves are needed. A path could honour the flag by silently registering
// nothing, which fixes the downgrade and replaces it with a box that appears
// to check for upgrades and never finds any — a dead end wearing the costume
// of a healthy system. The refusal must name the way out, and for an operator
// whose entire interface is this command, "the way out" must be a command they
// can type.
func TestDiscoveryPathsRefuseUnorderableInstalledVersion_STATBUS293(t *testing.T) {
	src := readUpgradePackageFile(t, "service.go")

	for _, fn := range []string{
		"func (d *Service) discover(",
		"func (d *Service) RunCheck(",
	} {
		body := extractFuncBody(t, src, fn)

		if !strings.Contains(body, "CompareVersions(") {
			t.Errorf("%s no longer consults CompareVersions — it can no longer be ranking releases against the installed version", fn)
			continue
		}
		// The refusal must name BOTH ways forward (architect's ruling): an
		// explicit target now, and how to restore automatic discovery.
		if !strings.Contains(body, "./sb upgrade apply") {
			t.Errorf(`%s does not name `+"`./sb upgrade apply`"+` in its refusal.

A commit-installed box registers nothing — correct — but an operator told only
"no" has been handed a dead end. The refusal must name the explicit-target
command AND how to restore automatic discovery (install a release tag).`, fn)
		}
		if !strings.Contains(body, "STATBUS-293") {
			t.Errorf("%s refusal does not cite STATBUS-293 — the operator-facing message should be traceable to why the box is refusing", fn)
		}
	}
}
