package upgrade

import (
	"strings"
	"testing"
)

// STATBUS-240. ONE terminal, TWO routes, and until now one label for both.
//
// On the POST-SWAP route ROLLBACK_FAILED_DB_RESTORE is TRUE: a restore ran and
// did not complete. On the PRESWAP route it lied three times — no restore was
// ever attempted (the volume was never touched), the system is not degraded (the
// same run shows the install ladder completing and the box healthy), and the
// operator was sent to support for something they can self-serve. For an
// unattended box in a statistical office that converts a self-serviceable state
// into a support ticket measured in days.
//
// BOTH DIRECTIONS ARE PINNED. It is not enough that the PreSwap route stops
// lying — the post-swap route must keep its own true label, because a message
// that reassures an operator whose data really is at risk would be the same
// defect pointing the other way, and far worse.

// TestPreSwapMessageIsTheApprovedText_STATBUS240 pins the King-approved wording
// verbatim. The ordering is the design, not prose style: the reassurance comes
// FIRST because an operator meeting this text is frightened before they are
// curious, and the most valuable fact we hold is that their data is untouched.
func TestPreSwapMessageIsTheApprovedText_STATBUS240(t *testing.T) {
	msg := preSwapStoppedMessage(3)

	// The class prefix, and the first sentence after it.
	if !strings.HasPrefix(msg, ErrUpgradeStoppedUnchanged+": The upgrade stopped before it changed anything.") {
		t.Errorf("the approved text opens with the class and the reassurance; got:\n%s", msg)
	}

	for _, want := range []string{
		"Your data was not modified and your installed version was not replaced.",
		"This system is still running the version it was running before, and it is serving normally.",
		"The upgrade was attempted twice and stopped at the same point both times, so it will not be tried again on its own.",
		"To try again: run ",
		"If it stops here again, the upgrade itself needs a fix.",
		"Report this message together with the version you were upgrading to.",
	} {
		if !strings.Contains(msg, want) {
			t.Errorf("the King approved this text VERBATIM; a rewording needs to go back to him, not through a commit. Missing:\n  %q\ngot:\n%s", want, msg)
		}
	}

	// The three lies the old text told must be absent from this route entirely.
	for _, forbidden := range []string{"degraded", "contact SSB support", "IT staff", "ROLLBACK_FAILED_DB_RESTORE"} {
		if strings.Contains(msg, forbidden) {
			t.Errorf("the PreSwap message must not contain %q — nothing was restored, the box is serving, and the operator can self-serve; got:\n%s", forbidden, msg)
		}
	}

	// It must name the operator's one tool, and no speculative cause.
	if !strings.Contains(msg, INSTALL_CMD) {
		t.Errorf("the message must name the operator's remedy; got:\n%s", msg)
	}
	for _, guess := range []string{"probably", "likely", "may have", "possibly"} {
		if strings.Contains(strings.ToLower(msg), guess) {
			t.Errorf("no speculative cause: we do not know from this terminal alone, and a guess sends the operator to investigate the wrong thing — the same defect as the old text in a friendlier tone. Found %q", guess)
		}
	}
}

// TestTerminalBranchesOnRoute_STATBUS240 pins that the terminal chooses by ROUTE
// and that each route keeps its own truth. Source-level, because the branch is
// what a future edit would collapse back into one message.
func TestTerminalBranchesOnRoute_STATBUS240(t *testing.T) {
	src := readUpgradeServiceSource(t)
	body := extractFuncBody(t, src, "func (d *Service) recoveryRollback(")

	// The discriminator must be the FLAG — the authoritative carrier across this
	// gap — never a remembered variable (the STATBUS-241 rule).
	if !strings.Contains(body, "flag.IsServiceNewSbRecovery()") {
		t.Error("the route discriminator must be the flag's own predicate (IsServiceNewSbRecovery) — the same one every other site uses to tell 'the binary was swapped' from 'nothing moved'. A remembered variable is exactly what STATBUS-241 forbade")
	}

	// PRESWAP arm: the new class. POST-SWAP arm: the old one, unchanged.
	//
	// EXACTLY ONCE, not merely present. An earlier version of this pin only
	// checked that each message EXISTED in the body, and a mutation that
	// assigned the reassuring text to the POST-SWAP arm — leaving the old text
	// dead in the file — sailed straight through it. That is the worse
	// direction: it would tell an operator whose data IS at risk that nothing
	// changed. Presence is not use; the count is what pins the routing.
	if n := strings.Count(body, "preSwapStoppedMessage(attempts)"); n != 1 {
		t.Errorf("the approved STOPPED-UNCHANGED text must be rendered on EXACTLY ONE arm (the PreSwap one); found %d use(s). Two uses means the post-swap route also reassures — the same defect pointing the dangerous way", n)
	}
	// The identifier, not its value: the source references the constant.
	if !strings.Contains(body, "ErrRollbackDBRestore") {
		t.Error("the POST-SWAP arm must KEEP ROLLBACK_FAILED_DB_RESTORE — there a restore genuinely ran and did not complete, and softening that message would reassure an operator whose data really is at risk")
	}
	if !strings.Contains(body, "The system is in a degraded state") {
		t.Error("the post-swap arm's degraded-state text must survive: it is TRUE on that route, and STATBUS-240 narrows a lie rather than deleting a warning")
	}

	// The log labels must differ, or an operator reading the journal cannot tell
	// which route fired — which is the same conflation one level down.
	if !strings.Contains(body, "STOPPED-UNCHANGED") || !strings.Contains(body, "RESTORE-BROKE") {
		t.Error("the two routes must log DISTINCT labels; a shared label reproduces the conflation this entry removes, in the journal instead of the row")
	}
}

// TestNewClassJoinsTheStableCodes_STATBUS240: the class is operator-facing and
// machine-filterable, so it lives with the others.
func TestNewClassJoinsTheStableCodes_STATBUS240(t *testing.T) {
	if ErrUpgradeStoppedUnchanged != "UPGRADE_STOPPED_NOTHING_CHANGED" {
		t.Errorf("the King approved this exact name; got %q", ErrUpgradeStoppedUnchanged)
	}
	// It deliberately does NOT read like its neighbours. Every other class names
	// a failure of something attempted; this one must not, because nothing
	// failed in that sense and an operator scanning for damage would assume
	// there is some.
	if strings.Contains(ErrUpgradeStoppedUnchanged, "FAILED") {
		t.Error("the name must not contain FAILED — it would sit in the list looking like its neighbours, and the name is the one surface nobody can skip")
	}
	if strings.Contains(ErrUpgradeStoppedUnchanged, "PRESWAP") || strings.Contains(ErrUpgradeStoppedUnchanged, "PRE_SWAP") {
		t.Error("PreSwap is our word for our machinery; this class is read by people who have never heard of a swap")
	}
}
