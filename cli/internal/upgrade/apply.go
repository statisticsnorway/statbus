package upgrade

import (
	"context"
	"fmt"
	"strings"
)

// RunApply installs EXACTLY the named candidate: `./sb upgrade apply <target>`.
//
// STATBUS-258. The product could already install a named version, but only as
// two commands an operator had to know to pair — `register` then `schedule` —
// and only if they knew that `schedule` fails on an unregistered target. The
// verb that says what an operator actually wants ("put this version on this
// box") did not exist, so callers reached for `apply-latest` instead, which
// installs whatever is newest rather than what was asked for. That is how a
// release chain waiting for one specific commit can be handed a different one.
//
// THIS IS A GENERAL VERB, deliberately. It carries no role semantics, nothing
// fleet-specific, and no notion of "latest": it takes one target in the
// canonical commit vocabulary (release tag, 8-char commit_short, or full
// 40-hex SHA — commit.go) and installs that. Any operator of any installation
// would want it, which is the test it had to pass.
//
// It composes rather than reimplements: the same registration path every other
// caller uses, then the same promotion. What it adds is that they happen in one
// connection, under one command, with refusals phrased for someone who asked for
// a specific version and needs to know why they are not getting it.
func (d *Service) RunApply(ctx context.Context, input string, recreate bool) error {
	return d.runOneShot(ctx, func(ctx context.Context) error {
		// REGISTER FIRST, ALWAYS — including when a row already exists.
		//
		// registerStep is idempotent by construction: it resolves the target and
		// upserts through the single guarded path, so a second call re-reads the
		// commit's tags and refreshes the row rather than duplicating it. Making
		// the call unconditional means `apply` behaves identically whether the
		// box has seen this candidate before or not, which is the property an
		// operator relies on when they are repeating a command after a failure.
		if err := d.registerStep(ctx, input); err != nil {
			return fmt.Errorf("%w\n\n%s", err, applyRegisterAdvice(input))
		}

		if err := d.scheduleStep(ctx, input, recreate); err != nil {
			return err
		}

		// Say what will happen next, because "scheduled" is not "installed" and
		// the gap between them is where an operator otherwise stands and waits
		// with no idea what they are waiting for.
		fmt.Printf("\n%s is scheduled on this box. The upgrade service will take it from here:\n", strings.TrimSpace(input))
		fmt.Println("  it backs up the database, applies migrations, restarts, health-checks,")
		fmt.Println("  and rolls back automatically if any of that fails.")
		fmt.Println("Follow it with: ./sb upgrade list   (or the service log)")
		return nil
	})
}

// applyRegisterAdvice is the actionable half of a registration refusal.
//
// Registration fails for reasons an operator can act on, and they are different
// actions — so the message names all of them rather than saying "register
// failed". The underlying error already says WHICH one; this says what to do
// about each.
func applyRegisterAdvice(input string) string {
	return fmt.Sprintf(`What to check, in the order that resolves this fastest:

  1. Is %q a real target on this box?
     It must be a release tag (v2026.08.0), an 8-character commit_short, or a
     full 40-character commit SHA. Run './sb upgrade list' to see what this box
     already knows about.

  2. Does the commit exist in this box's clone?
     A commit pushed minutes ago may not be here yet. Registration fetches it,
     but that needs the box to reach the remote — if the fetch is what failed,
     the error above names it.

  3. Are the release artifacts published?
     A tag can exist before CI finishes building it. That case is NOT an error
     here: the candidate registers, and the upgrade is unscheduled with
     "Release assets not ready … Will be available when CI finishes" until the
     build lands. Re-run this command then; nothing is lost by waiting.`, input)
}
