package migrate

import (
	"errors"
	"fmt"
	"os/exec"
	"testing"
)

// STATBUS-046 slice 2 (architect Q5) — pins ClassifyUpErr against the
// documented psql exit-status contract (postgresql.org app-psql §Exit
// Status) and against runUp's actual wrapping shape (fmt.Errorf("...: %w",
// err)), since the consumer (recovery_escalation.go's StepMigrateUp
// classifier) depends on errors.As seeing through exactly that wrap.

// exitErrWithCode runs a subprocess that exits with the given code and
// returns the resulting *exec.ExitError — the same concrete error shape
// cmd.CombinedOutput() produces inside runPsqlFile on a non-zero psql exit.
func exitErrWithCode(t *testing.T, code int) error {
	t.Helper()
	cmd := exec.Command("sh", "-c", fmt.Sprintf("exit %d", code))
	err := cmd.Run()
	if err == nil {
		t.Fatalf("expected sh -c 'exit %d' to fail, got nil error", code)
	}
	var exitErr *exec.ExitError
	if !errors.As(err, &exitErr) {
		t.Fatalf("expected *exec.ExitError, got %T: %v", err, err)
	}
	return exitErr
}

func TestClassifyUpErr_Nil(t *testing.T) {
	if got := ClassifyUpErr(nil); got != ExitSuccess {
		t.Errorf("ClassifyUpErr(nil) = %d, want ExitSuccess (%d)", got, ExitSuccess)
	}
}

func TestClassifyUpErr_PsqlExit3_Deterministic(t *testing.T) {
	err := exitErrWithCode(t, 3)
	if got := ClassifyUpErr(err); got != ExitDeterministic {
		t.Errorf("ClassifyUpErr(exit 3) = %d, want ExitDeterministic (%d)", got, ExitDeterministic)
	}
}

func TestClassifyUpErr_PsqlExit3_WrappedLikeRunUp(t *testing.T) {
	// runUp wraps runPsqlFile's error with fmt.Errorf("migration %d (%s)
	// failed: %w\n%s", ...) — mirror that shape exactly so this test would
	// catch a future wrap that breaks errors.As unwrapping.
	raw := exitErrWithCode(t, 3)
	wrapped := fmt.Errorf("migration %d (%s) failed: %w\n%s", 20260703104910, "some.up.sql", raw, "psql output")
	if got := ClassifyUpErr(wrapped); got != ExitDeterministic {
		t.Errorf("ClassifyUpErr(wrapped exit 3) = %d, want ExitDeterministic (%d)", got, ExitDeterministic)
	}
}

func TestClassifyUpErr_PsqlExit1_Unclassified(t *testing.T) {
	err := exitErrWithCode(t, 1)
	if got := ClassifyUpErr(err); got != ExitUnclassified {
		t.Errorf("ClassifyUpErr(exit 1) = %d, want ExitUnclassified (%d)", got, ExitUnclassified)
	}
}

func TestClassifyUpErr_PsqlExit2_Unclassified(t *testing.T) {
	err := exitErrWithCode(t, 2)
	if got := ClassifyUpErr(err); got != ExitUnclassified {
		t.Errorf("ClassifyUpErr(exit 2) = %d, want ExitUnclassified (%d)", got, ExitUnclassified)
	}
}

func TestClassifyUpErr_NonExitError_Unclassified(t *testing.T) {
	// e.g. migration file wouldn't open, advisory-lock acquisition failed,
	// content-hash immutability violation — none of these carry a psql
	// exit code at all.
	err := errors.New("open migration file: no such file or directory")
	if got := ClassifyUpErr(err); got != ExitUnclassified {
		t.Errorf("ClassifyUpErr(non-ExitError) = %d, want ExitUnclassified (%d)", got, ExitUnclassified)
	}
}
