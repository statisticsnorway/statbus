package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/invariants"
)

// TestNoSilentNotesInInstall enforces the install-path fail-fast contract
// from the plan's Phase 4: install flow must not emit `Note: ...` or
// `Warning: ...` for conditions that the operator could act on — every
// such condition must either be a named invariant (class=fail-fast, which
// emits the transcript + MarkTerminal and returns a wrapped error) or a
// class=log-only breadcrumb whose primary failure path has already
// terminated the run. Log-only breadcrumbs use log.Printf (which prepends
// a timestamp) rather than fmt.Printf, keeping them outside this gate.
func TestNoSilentNotesInInstall(t *testing.T) {
	pattern := regexp.MustCompile(`fmt\.Printf\("[^"]*(Note|Warning):`)
	files := []string{
		thisRepoFile(t, "cli/cmd/install.go"),
	}
	var violations []string
	for _, f := range files {
		data, err := os.ReadFile(f)
		if err != nil {
			t.Fatalf("read %s: %v", f, err)
		}
		lines := strings.Split(string(data), "\n")
		for i, ln := range lines {
			if pattern.MatchString(ln) {
				violations = append(violations,
					fmt.Sprintf("%s:%d: %s", relPath(f), i+1, strings.TrimSpace(ln)))
			}
		}
	}
	if len(violations) > 0 {
		t.Errorf("install-path files contain %d silent Note/Warning prints "+
			"(Phase 4 must rewrite each as a named invariant):\n  %s",
			len(violations), strings.Join(violations, "\n  "))
	}
}

// TestEveryInvariantHasTriadDocumented walks the runtime registry and
// asserts that every registered invariant has non-empty triad fields
// (Name, Class, SourceLocation, ExpectedToHold, WhyExpected,
// ViolationShape, TranscriptFormat) — i.e., the four-element triad from
// the plan plus the provenance fields. This enforces the "plan ↔ code ↔
// bundle" invariant-triad coupling at build time.
//
// Trivially passes when the registry is empty (Phase 3 state — Phase 4
// is where we first register install-path guards). Gains teeth on each
// subsequent Register() call.
func TestEveryInvariantHasTriadDocumented(t *testing.T) {
	for _, name := range invariants.Names() {
		// Skip the test-only invariants registered by sibling tests in
		// cli/internal/invariants — those are intentionally minimal.
		if strings.HasPrefix(name, "TEST_") {
			continue
		}
		inv, ok := invariants.Get(name)
		if !ok {
			t.Errorf("Names() lists %q but Get(%q) returned !ok", name, name)
			continue
		}
		if inv.Class == "" {
			t.Errorf("invariant %q has empty Class", name)
		}
		if inv.SourceLocation == "" {
			t.Errorf("invariant %q has empty SourceLocation", name)
		}
		if inv.ExpectedToHold == "" {
			t.Errorf("invariant %q has empty ExpectedToHold (first triad field)", name)
		}
		if inv.WhyExpected == "" {
			t.Errorf("invariant %q has empty WhyExpected (second triad field)", name)
		}
		if inv.ViolationShape == "" {
			t.Errorf("invariant %q has empty ViolationShape (third triad field)", name)
		}
		if inv.TranscriptFormat == "" {
			t.Errorf("invariant %q has empty TranscriptFormat (fourth triad field)", name)
		}
		if !strings.Contains(inv.TranscriptFormat, "violated") {
			t.Errorf("invariant %q TranscriptFormat missing the anchor word %q "+
				"(support-bundle grep depends on this)", name, "violated")
		}
	}
}

// TestRunInstallService_GatesNowOnInsideActiveUpgrade is the structural
// guard for Item H (plan-rc.66): runInstallService must conditionally
// drop --now when invoked from inside an active upgrade. The Type=notify
// statbus-upgrade unit goes into a SDNOTIFY collision when systemctl
// --user enable --now joins the existing start job from a child PID;
// the parent times out at ~47s and is terminated. Skip --now in that
// case and let the parent's exit-42 → systemd auto-restart pick up the
// new binary.
//
// Source-level assertion (rather than a mocked runCmd) keeps the test
// honest about WHERE in the function the gate sits and matches the
// pattern other install-path guards use.
func TestRunInstallService_GatesNowOnInsideActiveUpgrade(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/cmd/install.go"))
	if err != nil {
		t.Fatalf("read install.go: %v", err)
	}
	body := string(src)
	start := strings.Index(body, "func runInstallService(")
	if start < 0 {
		t.Fatal("runInstallService not found in install.go")
	}
	rest := body[start:]
	end := regexp.MustCompile(`(?m)^}\n`).FindStringIndex(rest)
	if end == nil {
		t.Fatal("runInstallService closing brace not found")
	}
	fn := rest[:end[1]]

	gateIdx := strings.Index(fn, "if insideActiveUpgrade {")
	if gateIdx < 0 {
		t.Fatal("runInstallService missing `if insideActiveUpgrade {` gate. " +
			"Without it, step 14/14's `systemctl --user enable --now` " +
			"collides with the active service's SDNOTIFY contract — see Item H.")
	}

	// The gate must come BEFORE the is-enabled verification call
	// (otherwise the verification fires against an unenabled unit).
	// Anchor on the exec.Command call, not on bare "is-enabled" text
	// which may appear in the surrounding doc comment.
	verifyIdx := strings.Index(fn, `exec.Command("systemctl", "--user", "is-enabled"`)
	if verifyIdx < 0 {
		t.Fatal("runInstallService missing is-enabled verification call — test is stale")
	}
	if gateIdx > verifyIdx {
		t.Errorf("insideActiveUpgrade gate (idx=%d) must come BEFORE is-enabled verification (idx=%d)",
			gateIdx, verifyIdx)
	}

	// Find the gate's true-branch body and assert it omits "--now".
	gateBody := fn[gateIdx:]
	openBrace := strings.Index(gateBody, "{")
	if openBrace < 0 {
		t.Fatal("gate body open brace not found")
	}
	// Find matching close. Naive depth counter suffices for this snippet.
	depth := 0
	closeIdx := -1
	for i := openBrace; i < len(gateBody); i++ {
		switch gateBody[i] {
		case '{':
			depth++
		case '}':
			depth--
			if depth == 0 {
				closeIdx = i
			}
		}
		if closeIdx >= 0 {
			break
		}
	}
	if closeIdx < 0 {
		t.Fatal("gate body close brace not found")
	}
	trueBranch := gateBody[openBrace : closeIdx+1]
	if !strings.Contains(trueBranch, `"systemctl", "--user", "enable", instance`) {
		t.Errorf("true branch must call `systemctl --user enable <instance>` (no --now). Body:\n%s", trueBranch)
	}
	if strings.Contains(trueBranch, `"--now"`) {
		t.Errorf("true branch must NOT pass --now (Item H). Body:\n%s", trueBranch)
	}

	// And after the gate (else branch / fall-through), `--now` must
	// still be present so the cold-install path keeps starting the
	// service. We check the rest of the function up to the
	// is-enabled verification.
	remainder := fn[gateIdx+closeIdx : verifyIdx]
	if !strings.Contains(remainder, `"systemctl", "--user", "enable", "--now", instance`) {
		t.Errorf("else/fall-through branch must keep `systemctl --user enable --now <instance>` " +
			"for cold installs. Otherwise nothing starts the service on a fresh box.")
	}
}

// thisRepoFile resolves a repo-relative path from the test's source
// location, so the test works regardless of go test's cwd.
func thisRepoFile(t *testing.T, relPath string) string {
	t.Helper()
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	// thisFile = cli/cmd/install_test.go → up two = repo root.
	repoRoot := filepath.Dir(filepath.Dir(filepath.Dir(thisFile)))
	return filepath.Join(repoRoot, relPath)
}

// relPath returns the repo-relative path from an absolute path, for
// tidy error messages.
func relPath(abs string) string {
	_, thisFile, _, _ := runtime.Caller(0)
	repoRoot := filepath.Dir(filepath.Dir(filepath.Dir(thisFile)))
	rel, err := filepath.Rel(repoRoot, abs)
	if err != nil {
		return abs
	}
	return rel
}
