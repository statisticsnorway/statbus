package upgrade

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// STATBUS-250's first deliverable: `sb upgrade dismiss <target>`.
//
// Until now dismissal existed ONLY as an app action (a PATCH from the admin UI
// — the write site the STATBUS-242 audit enumerates). So an operator who
// decided against a candidate had no CLI way to say so, and the dev-reset
// script could not dismiss the wrecking candidate through product tooling at
// all: it would have had to write the row directly, which is surgery.

// TestDismissedRowsAreNeverOffered_STATBUS250 is the core guarantee, verified
// AT SOURCE rather than asserted.
//
// The guarantee does not come from a new filter — it comes from every automatic
// path already selecting `state IN ('available', 'scheduled')`. A dismissed row
// is in neither, so no automatic path can pick it up. That is stronger than a
// check, because there is nothing to remember: the exclusion is structural.
//
// This test pins that the selection predicates STAY that shape. If one ever
// widens to include 'dismissed', the operator's deliberate decision silently
// stops meaning anything — and it would be invisible in review, because the
// dismiss command itself would still look correct.
func TestDismissedRowsAreNeverOffered_STATBUS250(t *testing.T) {
	src := readUpgradeServiceSource(t)

	// Every offer/candidate-selection predicate in the service.
	offerPredicates := []string{
		"state IN ('available', 'scheduled')",
		"state = 'available'",
	}
	found := 0
	for _, p := range offerPredicates {
		found += strings.Count(src, p)
	}
	if found == 0 {
		t.Fatal("no offer-selection predicate found — the scan lost its subject, and a check that examines nothing must fail rather than pass")
	}

	// The decisive property: no selection predicate may admit a dismissed row.
	for _, admits := range []string{
		"state IN ('available', 'scheduled', 'dismissed')",
		"state IN ('dismissed'",
		"state = 'dismissed' OR",
	} {
		// Scanned OUTSIDE RunDismiss: its own UPDATE carries a legitimate
		// `state <> 'dismissed'` compare-and-set guard, which is what makes
		// RowsAffected==0 mean "the row changed underneath me" rather than
		// "nothing to do". My first version of this list flagged that guard —
		// the pattern was broader than the property. The property is about
		// SELECTION predicates, so the write that CREATES the state is excluded.
		if strings.Contains(withoutFunc(src, "func (d *Service) RunDismiss("), admits) {
			t.Errorf(`an offer path admits dismissed rows (%q).

The whole guarantee of 'sb upgrade dismiss' is that no automatic path can pick
the row up again, and it holds BY CONSTRUCTION: offers select 'available' or
'scheduled', and dismissed is neither. Widening a selection — or filtering
dismissal out by hand instead — turns a structural property into one someone has
to remember.`, admits)
		}
	}
}

// TestDismissWritesThePair_STATBUS250: state and dismissed_at go together in ONE
// statement. chk_upgrade_state_attributes rejects a row whose state and
// timestamp columns disagree, so a half-write is a FAILED statement rather than
// a silently contradictory row — the STATBUS-242 pair ruling, applied to the
// command that creates the state.
func TestDismissWritesThePair_STATBUS250(t *testing.T) {
	src := readUpgradeServiceSource(t)
	body := extractFuncBody(t, src, "func (d *Service) RunDismiss(")

	if !strings.Contains(body, "SET state = 'dismissed', dismissed_at = now()") {
		t.Error("dismiss must write state AND dismissed_at in one statement — the pair is what chk_upgrade_state_attributes accepts, and it is how the app's own PATCH writes it")
	}
	// The app writes the same pair; the CLI must not invent a different shape,
	// or two ways of dismissing produce two different rows.
	if strings.Count(body, "dismissed_at") != 1 {
		t.Error("exactly one dismissed_at write — a second would be a second shape of the same act")
	}
}

// TestDismissRefusesNothing_STATBUS250: a dismissal of a version with no row is
// a TYPO, not a no-op. Reporting success there would leave the operator
// believing they stopped a candidate that is still being offered.
func TestDismissRefusesNothing_STATBUS250(t *testing.T) {
	src := readUpgradeServiceSource(t)
	body := extractFuncBody(t, src, "func (d *Service) dismissNoSuchRow(")

	if !strings.Contains(body, "nothing was dismissed") {
		t.Error("the refusal must say plainly that nothing was dismissed")
	}
	if !strings.Contains(body, "Rows this box knows about") {
		t.Error("the refusal must SHOW what rows exist — a bare 'not found' leaves the operator unable to tell a typo from a box that never saw the candidate")
	}

	// And the completed case must refuse rather than pretend.
	dismissBody := extractFuncBody(t, src, "func (d *Service) RunDismiss(")
	if !strings.Contains(dismissBody, "would not uninstall anything") {
		t.Error("dismissing an already-COMPLETED version must be refused with the reason: it does not uninstall anything, and implying otherwise is the most expensive kind of wrong")
	}
	if !strings.Contains(dismissBody, "already dismissed") {
		t.Error("re-dismissing must be a clear no-op message, not a second write or a spurious error")
	}
}

// TestDismissUsesTheSharedTargetResolution_STATBUS250: one vocabulary across the
// subcommand set. An operator who can `register v2026.08.1-rc.3` must be able to
// `dismiss v2026.08.1-rc.3`, and a second resolver would drift from the first.
func TestDismissUsesTheSharedTargetResolution_STATBUS250(t *testing.T) {
	src := readUpgradeServiceSource(t)
	body := extractFuncBody(t, src, "func (d *Service) RunDismiss(")

	if !strings.Contains(body, "resolveUpgradeTarget(ctx, d, input)") {
		t.Error("dismiss must resolve its target through the SAME path register and schedule use — tag, commit_short, or full SHA — or the subcommand set speaks two vocabularies")
	}
	if !strings.Contains(body, "case TaggedTarget:") || !strings.Contains(body, "case UntaggedTarget:") {
		t.Error("the target type-switch must handle both shapes, matching the established sites; an unhandled shape must error rather than dismiss the wrong row")
	}
}

// withoutFunc returns src with one function body removed, so a scan about
// SELECTION predicates is not confused by the write that creates the state.
func withoutFunc(src, signature string) string {
	i := strings.Index(src, signature)
	if i < 0 {
		return src
	}
	rest := src[i:]
	end := strings.Index(rest, "\n}\n")
	if end < 0 {
		return src[:i]
	}
	return src[:i] + rest[end:]
}

// TestUpgradeListOrdersDecisionsAboveHistory_STATBUS250 closes the two-halves
// defect AND the pattern behind it: the command that CREATES a state and the
// command that REPORTS it must agree, and the report must not let a row's
// HISTORY outrank the operator's DECISION.
//
// INSTANCES OF ONE DEFECT, fixed together:
//   - 'dismissed' had NO branch at all and fell through to 'available', so a
//     CORRECT dismiss read as a failed one in the exact output the dev-reset
//     script checks at its verification step.
//   - 'skipped' HAD a branch but sat BELOW scheduled/error, so a candidate that
//     was scheduled (or failed) and then skipped rendered as 'scheduled' —
//     hiding the skip on precisely the rows that have a history.
//   - 'superseded' also retains scheduled_at, so it must outrank that history.
//
// ORDER IS THE SUBSTANCE, not formatting, which is why it is pinned: a later
// tidy-up that moves either decision branch back down beside the lifecycle
// states — where it reads more naturally — silently reintroduces the defect for
// the rows an operator is most likely to act on.
func TestUpgradeListOrdersDecisionsAboveHistory_STATBUS250(t *testing.T) {
	src := readCLIUpgradeSource(t)
	idx := func(needle string) int { return strings.Index(src, needle) }

	decisions := map[string]string{
		"dismissed":  "WHEN dismissed_at IS NOT NULL THEN 'dismissed'",
		"skipped":    "WHEN skipped_at IS NOT NULL THEN 'skipped'",
		"superseded": "WHEN superseded_at IS NOT NULL THEN 'superseded'",
	}
	// The marks a row keeps from what it DID earlier. A decision outranks all
	// of them, because the row still carries them after the decision is made.
	history := []string{
		"WHEN error IS NOT NULL AND rolled_back_at IS NOT NULL",
		"WHEN error IS NOT NULL THEN 'failed'",
		"WHEN started_at IS NOT NULL",
		"WHEN scheduled_at IS NOT NULL",
	}

	completed := idx("WHEN completed_at IS NOT NULL")
	if completed < 0 {
		t.Fatal("the status CASE was not found — the scan lost its subject, and a check that examines nothing must fail rather than pass")
	}

	for name, branch := range decisions {
		at := idx(branch)
		if at < 0 {
			t.Errorf(`'%s' has no branch in the status CASE — the row falls through and renders as something it is not.

An operator confirming their own decision would be told it did not take.`, name)
			continue
		}
		if at < completed {
			t.Errorf("'completed' must outrank '%s': a version the box actually HAS is a fact about the box, while %s is a decision about a candidate", name, name)
		}
		for _, h := range history {
			if i := idx(h); i >= 0 && i < at {
				t.Errorf(`the '%s' branch must come BEFORE %q.

DECISION-STATES ABOVE HISTORY-STATES: a row that was scheduled, or that failed,
and is THEN %s still carries scheduled_at or error. A decision branch below
those renders the row by its history and hides the operator's decision — the
same defect as having no branch at all, on exactly the rows that have a past.`, name, h, name)
			}
		}
	}
}

func TestUpgradeListUsesCanonicalNameAndLabelsBuildProvenance_STATBUS355(t *testing.T) {
	src := readCLIUpgradeSource(t)

	if strings.Contains(src, "SELECT commit_version AS version") {
		t.Fatal("upgrade list still presents immutable commit_version as the current version")
	}
	if !strings.Contains(src, "SELECT public.display_name(u) AS version") {
		t.Fatal("upgrade list must resolve the current name through public.display_name(upgrade)")
	}
	if !strings.Contains(src, `END AS "built as"`) {
		t.Fatal("upgrade list may retain commit_version only behind an explicit provenance label")
	}
	if !strings.Contains(src, `END AS "installed as"`) {
		t.Fatal("upgrade list may retain the install-time summary only behind an explicit provenance label")
	}
}

func readCLIUpgradeSource(t *testing.T) string {
	t.Helper()
	b, err := os.ReadFile(filepath.Join(repoRootFromTest(t), "cli", "cmd", "upgrade.go"))
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}
