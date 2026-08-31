package upgrade

import (
	"context"
	"fmt"
)

// ─────────────────────────────────────────────────────────────────────────────
// STATBUS-328 arm 1 — THE SHELF MUST MATCH THE INTAKE POLICY.
//
// THE LIST IS THE OFFER (the 291 principle): a row a box displays as
// "available" must be a valid upgrade for THAT box. The channel filter guards
// INTAKE only — nothing has ever retired a row for being off-channel. Every
// retirement path keys on version ORDERING (supersedeBelowInstalled,
// selectStaleBelowInstalled), and d.channel appeared only at intake and at the
// schedule announce, never in a retirement predicate.
//
// So a row registered BEFORE the filter arrived, sitting ABOVE the installed
// version, is never superseded and stays on the shelf indefinitely. Confirmed
// live on et, jo and ug: they display v2026.08.1-rc.01 residue while their
// filter provably works (zero rc discoveries since v2026.08.0).
//
// WHY THE SERVICE AND NOT A MIGRATION. The box's channel lives in .env, not in
// the database — a repair migration has nothing to filter on. The retraction
// must live where the channel is known, which is here.
//
// WHY THIS IS NOT A STANDING SELF-HEAL, which the project otherwise forbids: it
// applies the SAME declared channel policy discover() applies at intake, to rows
// that entered before that policy existed. Consistent application of declared
// policy is not repair — the same reasoning that settled 325's derivation
// question. A box whose shelf already matches its policy sweeps nothing, forever.
// ─────────────────────────────────────────────────────────────────────────────

// retireOffChannelOffers retires available rows whose tags do not match this
// box's channel.
//
// SCOPE — 'available' ONLY, NEVER 'scheduled'. Its sibling supersedeBelowInstalled
// retires both, and the difference is deliberate: a scheduled row is a HUMAN
// DECISION already taken, and taken with the 291 announce in front of them
// (scheduleStep warns when a named target is off the box's channel). Retiring it
// here would silently cancel an operator's deliberate act, using the same policy
// they were shown and chose to override. The offer surface is what this fixes;
// a decision already made is not an offer.
//
// PREDICATE — channel membership only, via TagMatchesChannel. That is the ONE
// definition of "on channel", the same function discover() filters intake with
// and scheduleStep announces from. No version-string reasoning, no second copy
// of the rule: a private copy of this exact judgement was found and removed from
// selectLatestTagFromNames in STATBUS-307, and creating another here would
// reintroduce the drift that fix eliminated.
//
// A row is ON CHANNEL if ANY of its tags matches. Dual-tagged rows are the
// reason: a release and its final release candidate are two names for one
// commit, so on a stable box a row carrying both v2026.08.1 and
// v2026.08.1-rc.01 is legitimately installable under the release name and must
// survive. Requiring every tag to match would retire exactly the rows a stable
// box most wants.
//
// UNTAGGED ROWS ARE NEVER TOUCHED. A row with no tags was registered by commit
// SHA — a deliberate operator act (`./sb upgrade register <sha>`), not something
// discovery put on the shelf. It has no channel membership to test, and retiring
// it would destroy a human decision on the strength of a predicate that does not
// apply to it. Mirrors supersedeBelowInstalled's own tagged-rows-only guard.
func (d *Service) retireOffChannelOffers(ctx context.Context) {
	if d.queryConn == nil || d.channel == "" {
		return
	}

	// Single *pgx.Conn: drain the SELECT fully before the UPDATE.
	rows, err := d.queryConn.Query(ctx,
		`SELECT id, commit_tags
		   FROM public.upgrade
		  WHERE state = 'available'
		    AND array_length(commit_tags, 1) > 0`)
	if err != nil {
		return
	}
	var candidates []tagSet
	for rows.Next() {
		var c tagSet
		if err := rows.Scan(&c.ID, &c.Tags); err != nil {
			continue
		}
		candidates = append(candidates, c)
	}
	rows.Close()

	retire := selectOffChannel(d.channel, candidates)
	if len(retire) == 0 {
		return
	}

	// state='skipped' — chosen deliberately over 'superseded' and 'dismissed'.
	//
	//   superseded would state a FALSEHOOD about why the row retired. It means
	//   "something newer replaced this", which is what supersedeBelowInstalled
	//   records for rows below the installed version. Nothing replaced an
	//   off-channel row; it was never eligible in the first place, and
	//   superseded_at would carry a reason the row does not have.
	//
	//   dismissed is structurally impossible here, and the schema says so: the
	//   chk_upgrade_state_attributes CHECK requires dismissed_at IS NOT NULL AND
	//   (error IS NOT NULL OR rolled_back_at IS NOT NULL). Dismissal is for rows
	//   that FAILED. An off-channel row has no error, and inventing one to fit
	//   the state would be fabricating a failure that never happened.
	//
	//   skipped requires only skipped_at, and its established meaning is a
	//   deliberate terminal decision — STATBUS-250's ordering rule ranks it as a
	//   DECISION-state above the history-states. That is what this is: the box's
	//   declared policy says it does not take rows of this shape. Worth naming
	//   the nuance rather than glossing it — 250 describes a skip as an OPERATOR
	//   decision, and this one is made by declared policy rather than by a person
	//   clicking. It is still a decision rather than an accident, and the
	//   alternative states are actively wrong rather than merely imperfect.
	//
	// The WHERE re-asserts state='available' so a row scheduled concurrently
	// between the SELECT and this UPDATE is not clobbered — that row became a
	// human decision in the interval, and this sweep does not touch those.
	ct, err := d.queryConn.Exec(ctx,
		`UPDATE public.upgrade
		    SET state = 'skipped',
		        skipped_at = COALESCE(skipped_at, now())
		  WHERE id = ANY($1::int[])
		    AND state = 'available'`,
		retire)
	if err != nil {
		fmt.Printf("Failed to retire off-channel offers: %v\n", err)
		return
	}
	if n := ct.RowsAffected(); n > 0 {
		fmt.Printf("Retired %d off-channel offer(s) — this box follows the %q channel; "+
			"rows that never matched it are no longer displayed as available\n", n, d.channel)
	}
}

// channelAdmitsAnything reports whether membership is a meaningful question for
// this channel — and it is the guard that stops this sweep from destroying a
// ledger.
//
// FOUND BY WRITING THE TEST, not by reading the code: TagMatchesChannel admits
// NOTHING for a channel it does not recognise, and nothing for "local" either
// (a developer box follows no channel automatically). That is right for INTAKE,
// where offering nothing is the safe direction. Applied to RETIREMENT it
// INVERTS: "no tag matches" would be true of every row, so a box carrying a
// stale or retired channel value — or any developer machine — would sweep its
// entire shelf, including rows an operator registered by hand. The safe
// direction for intake is the catastrophic one for retirement.
//
// Derived by ASKING TagMatchesChannel rather than keeping a second list of
// channel names: a channel is sweepable exactly when some release shape is on
// it. A new channel added to that function is therefore handled here
// automatically, and there is still only one definition of membership — which is
// the property STATBUS-307 spent a fix restoring.
func channelAdmitsAnything(channel string) bool {
	return TagMatchesChannel("v2026.01.0", channel) ||
		TagMatchesChannel("v2026.01.0-rc.1", channel)
}

// tagSet is one ledger row reduced to what the channel decision needs.
type tagSet struct {
	ID   int
	Tags []string
}

// selectOffChannel is the pure decision: which rows carry NO tag matching the
// channel. Separated from the SQL so it is testable without a database, matching
// how selectStaleBelowInstalled sits beside supersedeBelowInstalled.
func selectOffChannel(channel string, rows []tagSet) []int {
	if !channelAdmitsAnything(channel) {
		return nil
	}
	var retire []int
	for _, r := range rows {
		if len(r.Tags) == 0 {
			continue // untagged: registered by SHA, not by discovery
		}
		onChannel := false
		for _, tag := range r.Tags {
			if TagMatchesChannel(tag, channel) {
				onChannel = true
				break
			}
		}
		if !onChannel {
			retire = append(retire, r.ID)
		}
	}
	return retire
}
