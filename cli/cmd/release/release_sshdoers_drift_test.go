package releasecmd

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// STATBUS-259. The fleet's inbound-command policy was the one security surface
// that did not ship as code: /etc/sshdoers was hand-edited root state, the repo
// carried a copy nothing compared it against, and drift was silent in either
// direction.
//
// These pin the gate's behaviour, and especially its FAILURE paths — a gate is
// only worth having if it fails when it should, and the tempting bugs here all
// make it pass.

// TestSshdoersHostsComeFromDisk_STATBUS259: the host list is discovered, never
// hard-coded.
//
// A hard-coded list is the same defect one level up: a standalone host that
// grows its own allowlist would be silently unchecked until somebody remembered
// to add it here, and nobody would ever learn that they had not.
func TestSshdoersHostsComeFromDisk_STATBUS259(t *testing.T) {
	dir := t.TempDir()
	for _, h := range []string{"niue", "rune"} {
		if err := os.MkdirAll(filepath.Join(dir, "ops", h), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(dir, "ops", h, "sshdoers"), []byte("match hexdigits\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	// A directory with no sshdoers must not be claimed as a host.
	if err := os.MkdirAll(filepath.Join(dir, "ops", "cloud"), 0o755); err != nil {
		t.Fatal(err)
	}

	hosts, err := discoverSshdoersHosts(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(hosts) != 2 {
		t.Fatalf("discovered %d hosts, want 2 (niue, rune) — a directory without an sshdoers file is not a host", len(hosts))
	}
	if hosts[0].Name != "niue" || hosts[1].Name != "rune" {
		t.Errorf("hosts are not in a stable order: %v — an unstable order makes the preflight's output differ run to run", hosts)
	}
	if hosts[0].Address != "niue.statbus.org" {
		t.Errorf("host address = %q, want niue.statbus.org", hosts[0].Address)
	}
}

// TestNoAllowlistIsAFailure_STATBUS259: zero hosts must FAIL, never pass.
//
// This is the zero-scope shape and the single most likely way this gate turns
// into decoration: the layout moves, the loop finds nothing, and a green
// preflight reports that the fleet's access policy was confirmed when nothing
// was examined at all.
func TestNoAllowlistIsAFailure_STATBUS259(t *testing.T) {
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, "ops"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv(sshdoersSkipEnv, "")

	out := captureStdout(t, func() {
		if checkSshdoersDrift(dir) {
			t.Error(`the drift check PASSED with no allowlist to compare.

Nothing was examined, so nothing was verified — but the release summary would
report the access policy as confirmed. A check that loses its subject must fail.`)
		}
	})
	if !strings.Contains(out, "examined nothing") {
		t.Errorf("the refusal must say plainly that nothing was examined; got:\n%s", out)
	}
}

// TestUnreachableHostFailsWithGuidance_STATBUS259: an unreadable host is a
// FAILURE, and the message has to be actionable.
//
// Skipping would be the comfortable choice and it is wrong for the same reason
// as above: the check examined nothing. The bypass exists for the genuinely
// unreachable case, and it is loud — that is the difference between a decision
// and an accident.
func TestUnreachableHostFailsWithGuidance_STATBUS259(t *testing.T) {
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, "ops", "nonexistent-host-259"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "ops", "nonexistent-host-259", "sshdoers"), []byte("match hexdigits\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv(sshdoersSkipEnv, "")
	// Force the ssh attempt to fail fast rather than actually dialling out.
	t.Setenv(sshdoersReadUserEnv, "definitely-not-a-user-259")

	out := captureStdout(t, func() {
		if checkSshdoersDrift(dir) {
			t.Error("an unreadable host must FAIL — reporting a pass would claim a comparison that never happened")
		}
	})
	for _, want := range []struct{ needle, why string }{
		{"could not be read", "the operator must know the read failed rather than the hashes matching"},
		{"This is not a pass", "the message must say what the failure means, since a reader could otherwise take it for a warning"},
		{"Stage 8", "the most common cause on a fresh host is that the stage has never run there"},
		{sshdoersReadUserEnv, "the account is overridable and the message must say so"},
		{sshdoersSkipEnv, "the genuinely-unreachable escape must be named, or someone will invent a worse one"},
	} {
		if !strings.Contains(out, want.needle) {
			t.Errorf("the unreachable-host refusal never mentions %q — %s\n\nGot:\n%s", want.needle, want.why, out)
		}
	}
}

// TestBypassIsLoudAndSaysWhatIsUnverified_STATBUS259: the escape hatch must
// announce what it gave up, in the established SKIP_IMAGES shape.
func TestBypassIsLoudAndSaysWhatIsUnverified_STATBUS259(t *testing.T) {
	t.Setenv(sshdoersSkipEnv, "1")
	out := captureStdout(t, func() {
		if !checkSshdoersDrift(t.TempDir()) {
			t.Error("the documented bypass must let the preflight continue")
		}
	})
	if !strings.Contains(out, "⚠") || !strings.Contains(out, "BYPASSED") {
		t.Errorf("the bypass must be visually loud, matching the SKIP_IMAGES shape; got:\n%s", out)
	}
	if !strings.Contains(out, "has NOT been compared") {
		t.Errorf("the bypass must state exactly what is no longer claimed — an operator reading a green summary must not think the policy was checked; got:\n%s", out)
	}
}

// TestDriftMessageNamesBothHashesAndTheDirection_STATBUS259 pins the part an
// operator acts on.
//
// Knowing the hashes differ is useless on its own. The two sides are
// authoritative for DIFFERENT things — live for behaviour, repo for intent — and
// the dangerous reflex is to re-run the stage to make the red go away, which
// erases whatever the live file has that the repo lacks. An entry that
// disappears is a workflow that stops working.
func TestDriftMessageNamesBothHashesAndTheDirection_STATBUS259(t *testing.T) {
	src, err := os.ReadFile("release_sshdoers_drift.go")
	if err != nil {
		t.Fatal(err)
	}
	body := string(src)
	i := strings.Index(body, "DIFFERS from the reviewed copy")
	if i < 0 {
		t.Fatal("the drift branch was not found — the scan lost its subject")
	}
	arm := body[i:]
	if end := strings.Index(arm, "allPassed = false"); end > 0 {
		arm = arm[:end]
	}

	for _, want := range []struct{ needle, why string }{
		{"live (", "the live hash must be printed — the operator cannot reconcile what they cannot see"},
		{"repo (", "and the repo hash beside it"},
		{"authoritative for BEHAVIOUR", "live is what the door enforces right now"},
		{"authoritative for INTENT", "repo is what was reviewed and what the next stage run installs"},
		{"Do NOT simply re-run the stage", "the dangerous reflex is to make the red go away, which erases live-only entries"},
		{"stops working", "and the consequence of that erasure has to be spelled out"},
	} {
		if !strings.Contains(arm, want.needle) {
			t.Errorf("the drift message is missing %q — %s", want.needle, want.why)
		}
	}
}

// TestRepoHashMatchesTheToolTheHostUses_STATBUS259 is the both-ends property.
//
// The stage publishes `sha256sum`'s output on the host; the preflight computes
// its side in Go. If those two ever disagreed about what "the sha256 of this
// file" means, every release would fail on identical policies — so the oracle
// here is the ACTUAL command-line tool, not a constant I typed, and not Go
// hashing itself twice and agreeing with itself.
func TestRepoHashMatchesTheToolTheHostUses_STATBUS259(t *testing.T) {
	tool, args := "", []string(nil)
	for _, cand := range [][]string{{"sha256sum"}, {"shasum", "-a", "256"}} {
		if p, err := exec.LookPath(cand[0]); err == nil {
			tool, args = p, cand[1:]
			break
		}
	}
	if tool == "" {
		t.Skip("no sha256sum/shasum available — the host-side tool cannot be consulted here")
	}

	dir := t.TempDir()
	path := filepath.Join(dir, "sshdoers")
	// Shaped like the real file — comments, a blank line, a trailing newline,
	// non-ASCII in a comment — because those are exactly the bytes a
	// well-meaning normaliser would strip, and stripping any of them would make
	// two identical policies hash differently.
	body := "# /etc/sshdoers — test\nmatch hexdigits\nsyslog auth\n\nstatbus_dev: cd ~/statbus && ./sb upgrade apply-latest\n"
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}

	out, err := exec.Command(tool, append(args, path)...).Output()
	if err != nil {
		t.Fatal(err)
	}
	fields := strings.Fields(string(out))
	if len(fields) == 0 {
		t.Fatalf("%s produced no output", tool)
	}
	external := fields[0]

	got, err := fileSHA256(path)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.EqualFold(got, external) {
		t.Errorf(`the preflight and %s disagree about this file's sha256:
  preflight: %s
  %s: %s

The stage publishes the host tool's output and the preflight computes its own.
If they ever differ, every release fails on a policy that is actually identical.`,
			filepath.Base(tool), got, filepath.Base(tool), external)
	}
}

// TestDriftCheckIsWiredIntoThePreflight_STATBUS259 closes the presence-≠-use
// gap, in the source-scanning shape release_gate_layer_test.go established.
//
// Every other test in this file exercises checkSshdoersDrift directly. All six
// would still pass if the call were deleted from preflightChecks — the gate
// would be perfectly correct and never run, and the release summary would simply
// stop mentioning it. A gate nothing calls is indistinguishable from no gate.
func TestDriftCheckIsWiredIntoThePreflight_STATBUS259(t *testing.T) {
	src, err := os.ReadFile("release.go")
	if err != nil {
		t.Fatal(err)
	}
	code := string(src)

	i := strings.Index(code, "func preflightChecks(")
	if i < 0 {
		t.Fatal("preflightChecks not found — the scan lost its subject")
	}
	end := strings.Index(code[i:], "\n}\n")
	if end < 0 {
		t.Fatal("could not bound preflightChecks")
	}
	body := code[i : i+end]

	if !strings.Contains(body, "checkSshdoersDrift(projDir)") {
		t.Error(`preflightChecks never calls checkSshdoersDrift.

The check would be correct and never run. Worse than absent: the gate's tests
would stay green while the fleet's access policy went unverified at every cut.`)
	}
	// And its result must reach the verdict, not be discarded. `checkX(...)` on
	// its own line compiles fine and decides nothing.
	if !strings.Contains(body, "allPassed = checkSshdoersDrift(projDir) && allPassed") {
		t.Error(`the drift check's result is not folded into allPassed.

Calling it and dropping the answer is the same as not calling it, except that it
looks wired up in review and prints a ✗ nobody acts on.`)
	}
}
