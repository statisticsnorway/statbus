package upgrade

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/migrate"
)

// STATBUS-144 — the FLAGLESS boot-migrate handler must classify a DETERMINISTIC
// failure (migrate exit-code contract exit 20) and stay alive-idle on it
// (log-loud-once + continue), keeping exit-and-restart ONLY for the
// transient/unclassified case. A concluded box (upgrade row terminal, no flag)
// whose boot-migrate hits a deterministically-broken pending migration must NOT
// restart-churn to a StartLimit death.

// exitErrWithCode runs a subprocess that exits with the given code and returns
// the resulting *exec.ExitError — the same concrete shape cmd.Run() produces for
// the boot-migrate subprocess (`sb migrate up`, which os.Exit(20)s on a
// deterministic failure; see cli/cmd/migrate.go).
func exitErrWithCode(t *testing.T, code int) error {
	t.Helper()
	err := exec.Command("sh", "-c", fmt.Sprintf("exit %d", code)).Run()
	if err == nil {
		t.Fatalf("expected sh -c 'exit %d' to fail, got nil", code)
	}
	var exitErr *exec.ExitError
	if !errors.As(err, &exitErr) {
		t.Fatalf("expected *exec.ExitError, got %T: %v", err, err)
	}
	return exitErr
}

func TestBootMigrateIsDeterministic(t *testing.T) {
	// AC#1 — exit 20 (a migration's SQL failed identically every apply) is the
	// deterministic class → the flagless handler stays alive-idle.
	if !bootMigrateIsDeterministic(exitErrWithCode(t, migrate.ExitDeterministic)) {
		t.Errorf("exit %d must classify as deterministic (stay alive-idle)", migrate.ExitDeterministic)
	}

	// AC#2 — every non-20 failure is NOT deterministic → keep exit-and-restart
	// (a re-run might succeed), exactly as before the fix.
	for _, tc := range []struct {
		name string
		err  error
	}{
		{"unclassified exit 1 (psql fatal / transient)", exitErrWithCode(t, migrate.ExitUnclassified)},
		{"resource exit 22 (disk full — may clear)", exitErrWithCode(t, migrate.ExitResource)},
		{"psql exit 2 (connection lost — transient)", exitErrWithCode(t, 2)},
		{"boot-migrate timeout (ErrCommandTimeout, not an ExitError)",
			fmt.Errorf("sb migrate up after 30m0s: %w", ErrCommandTimeout)},
		{"non-ExitError (migration file wouldn't open, advisory-lock, etc.)",
			errors.New("open migration file: no such file or directory")},
		{"nil (defensive — handler only calls this on a non-nil err)", nil},
	} {
		if bootMigrateIsDeterministic(tc.err) {
			t.Errorf("%s must NOT classify as deterministic (keep exit-and-restart)", tc.name)
		}
	}
}

// TestFlaglessDeterministicBootMigrateStaysAlive is the structural guard that
// the exit-20 flagless branch LOGS + CONTINUES (alive-idle) and does NOT exit
// the process — the churn fix. It reads Service.Run's body (line comments
// stripped, so the prose describing markTerminal/return can't false-match) and
// pins: the deterministic branch precedes the refuse branch, and between them
// there is neither a markTerminal nor a return — i.e. exit 20 falls through to
// the main loop, while the refuse `else` (transient) still exits as today.
func TestFlaglessDeterministicBootMigrateStaysAlive(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/service.go"))
	if err != nil {
		t.Fatalf("read service.go: %v", err)
	}
	run := extractFuncBody(t, string(src), "func (d *Service) Run(")

	detIdx := strings.Index(run, "else if bootMigrateDeterministic {")
	if detIdx < 0 {
		t.Fatal("Run() must have an `else if bootMigrateDeterministic` branch (STATBUS-144) — test is stale or the fix regressed")
	}
	refuseIdx := strings.Index(run, `d.markTerminal("BOOT_MIGRATE_UP_FAILED"`)
	if refuseIdx < 0 {
		t.Fatal("Run() must still have the refuse `markTerminal(BOOT_MIGRATE_UP_FAILED)` branch for the transient case")
	}
	if detIdx > refuseIdx {
		t.Errorf("the deterministic (stay-alive) branch must PRECEDE the refuse branch; detIdx=%d refuseIdx=%d", detIdx, refuseIdx)
	}

	// The deterministic branch body is everything from `else if
	// bootMigrateDeterministic {` up to the refuse branch's markTerminal. It must
	// contain NO return and NO markTerminal — the box stays alive-idle.
	branch := run[detIdx:refuseIdx]
	if strings.Contains(branch, "return ") {
		t.Errorf("the deterministic boot-migrate branch must NOT return (that exits the process → systemd restart churn → StartLimit death); found a return:\n%s", branch)
	}
	if strings.Contains(branch, "markTerminal") {
		t.Errorf("the deterministic boot-migrate branch must NOT markTerminal (the refuse-and-exit signal); it stays alive-idle:\n%s", branch)
	}

	// It classifies on the numeric exit code (doc-022: never stderr text) and
	// emits an actionable operator report (name the action; point at ./sb install).
	if !strings.Contains(branch, "migrate.ExitDeterministic") {
		t.Error("the deterministic branch must reference migrate.ExitDeterministic (classify on the exit code, not text)")
	}
	for _, want := range []string{"./sb migrate up", "./sb install", "staying ALIVE"} {
		if !strings.Contains(branch, want) {
			t.Errorf("the deterministic branch's loud report must be actionable — missing %q", want)
		}
	}
}
