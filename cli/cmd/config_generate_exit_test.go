package cmd

import (
	"errors"
	"fmt"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/config"
)

// TestExitCodeForConfigGenerateErr_PrincipledRefusal pins the STATBUS-298
// discriminator: a principled refusal (config.ErrPrincipledRefusal) must
// select exit 78 (EX_CONFIG) — the code the recovery-boot caller
// (service.go, STATBUS-298) inspects to stop retrying a refusal that cannot
// change between attempts. Wrapped via fmt.Errorf("...: %w", ...), matching
// how a real caller one layer above config.Generate might add context —
// errors.Is must still see through that layer.
func TestExitCodeForConfigGenerateErr_PrincipledRefusal(t *testing.T) {
	base := config.ErrPrincipledRefusal
	wrapped := fmt.Errorf("generate config: %w", base)

	code, shouldExit := exitCodeForConfigGenerateErr(wrapped)
	if !shouldExit {
		t.Fatal("a principled refusal must select an exit code, got shouldExit=false")
	}
	if code != exitPrincipledConfigRefusal {
		t.Errorf("code = %d, want %d (exitPrincipledConfigRefusal)", code, exitPrincipledConfigRefusal)
	}
}

// TestExitCodeForConfigGenerateErr_TransientFailure is the RED half: an
// ordinary error (disk full, permissions, a momentarily locked file) must
// NOT select exit 78 — that exit code is reserved for principled refusals
// only (architect ruling, STATBUS-298 ticket comment #1): "the moment 78
// covers a transient, the box stops recovering on its own."
func TestExitCodeForConfigGenerateErr_TransientFailure(t *testing.T) {
	err := errors.New("write .env: permission denied")

	code, shouldExit := exitCodeForConfigGenerateErr(err)
	if shouldExit {
		t.Errorf("a transient error must not select exit 78 (got code=%d) — that would stop the unit from ever self-recovering from a real transient", code)
	}
}

// TestExitCodeForConfigGenerateErr_Nil confirms the success path (nil error)
// never triggers an exit-code override — RunE's normal nil-error return
// must be untouched.
func TestExitCodeForConfigGenerateErr_Nil(t *testing.T) {
	if _, shouldExit := exitCodeForConfigGenerateErr(nil); shouldExit {
		t.Error("a nil error must never select an exit code")
	}
}
