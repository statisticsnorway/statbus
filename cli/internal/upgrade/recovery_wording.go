package upgrade

import "fmt"

// recoveryOpeningLine is the first line an operator reads when a process finds
// an upgrade flag at startup (STATBUS-318).
//
// WHY THIS IS A FUNCTION AND NOT AN INLINE STRING. It is message LOGIC: which
// story is true depends on the flag's phase, and getting it wrong is not a
// cosmetic error. The first human-canary run read "Recovering an interrupted
// upgrade" at the exact moment the upgrade was proceeding exactly as designed,
// and reasonably concluded the system had lost track of itself. A log that
// accuses itself of crashing during normal operation teaches its reader to
// distrust it — and then it means nothing on the day something really has
// crashed. Pulling it out here makes the branch directly testable, so the
// wording cannot silently drift back.
//
// THE PHASES ARE AN EXACT DISCRIMINATOR, not an inference:
//   - PhaseNewSbSwapped is stamped after the binary swap and immediately before
//     the deliberate exit-42 handoff. A fresh process meeting this flag is
//     meeting a marker its own predecessor left one moment earlier. This is the
//     design working; nothing was interrupted.
//   - PhaseNewSbUpgrading means the post-swap resume had begun and THAT process
//     died before completing (watchdog SIGABRT, OOM, reboot, kill).
//   - PhaseOldSbUpgrading (the empty default) means a crash before the swap, on
//     the old binary.
//
// Only the first is a planned continuation. The other two are genuine recovery
// and keep recovery language — the word has to stay meaningful for them.
//
// Both branches follow the same shape: the plain statement first, in the words
// an operator thinks in, then the precise identifiers for diagnosis. High level
// first, then the exact detail — never only one of the two.
func recoveryOpeningLine(flag UpgradeFlag, holder string) string {
	if flag.Phase == PhaseNewSbSwapped {
		return fmt.Sprintf(
			"Continuing the upgrade under the new binary (planned handoff). (detail: %s marker for %s, id=%d, invoked_by=%s, phase=%s)",
			holder, flag.Label(), flag.ID, flag.InvokedBy, flag.Phase)
	}
	return fmt.Sprintf(
		"Recovering an interrupted upgrade — found a %s marker for %s. (detail: id=%d, invoked_by=%s)",
		holder, flag.Label(), flag.ID, flag.InvokedBy)
}
