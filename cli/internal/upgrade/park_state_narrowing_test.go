package upgrade

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/jackc/pgx/v5/pgconn"
)

// STATBUS-242 NARROWING. The park-state consumers used to treat two OPPOSITE
// facts as the same one:
//
//	SQLSTATE 42703 — the column does not exist, so the row CANNOT be parked.
//	                 Proceeding is knowledge-based: fail-INFORMED.
//	anything else  — we do not KNOW whether the row is parked. Proceeding is a
//	                 guess, and on the restore-bearing paths the guess rewinds a
//	                 live park's columns and silently un-parks the row into the
//	                 deterministic failure it stopped at (STATBUS-229's shape).
//
// The asymmetry that settles the unknown case: refusing costs a human trigger on
// an alive-idle, recoverable box; proceeding restores over a park.

func TestParkStateUnknown_DistinguishesOpposites_STATBUS242(t *testing.T) {
	if parkStateUnknown(nil) {
		t.Error("no error means the answer is known")
	}

	undefinedColumn := &pgconn.PgError{Code: "42703", Message: `column "recovery_parked_at" does not exist`}
	if parkStateUnknown(undefinedColumn) {
		t.Error("42703 is fail-INFORMED, not fail-open: a schema with no recovery_parked_at cannot hold a parked row, so the answer IS known — 'not parked'. Treating it as unknown would wedge the bootstrap, where boot migrate is what creates the column")
	}
	// Wrapped, as it arrives through the query helper.
	if parkStateUnknown(fmt.Errorf("read park state: %w", undefinedColumn)) {
		t.Error("42703 must be recognised through wrapping — errors.As, not a string match")
	}

	for _, err := range []error{
		errors.New("connection refused"),
		&pgconn.PgError{Code: "57P01", Message: "terminating connection due to administrator command"},
		&pgconn.PgError{Code: "42501", Message: "permission denied"},
		fmt.Errorf("context deadline exceeded"),
	} {
		if !parkStateUnknown(err) {
			t.Errorf("%v must count as UNKNOWN — anything that is not 'the column does not exist' leaves the park state unread, and acting on it is a guess", err)
		}
	}
}

// TestEveryParkStateConsumerIsNarrowed_STATBUS242 keeps the ENUMERATION honest,
// which is this ticket's own principle applied to itself.
//
// The ruling named three consumers. There are FIVE, and they do not share one
// disposition — three reach a restore and must refuse on unknown; one skips boot
// migrate and must refuse on unknown but MUST still proceed on 42703 (boot
// migrate is what creates the column, so treating it as unknown would deadlock
// the bootstrap); and one is genuinely safe because the write it guards carries
// its own SQL belt guard.
//
// So the pin is not "everything is narrowed" — it is "every consumer has been
// CLASSIFIED, and a new one goes red until someone classifies it too". Fixing
// the sites the ruling happened to name and declaring the pattern closed is the
// third-one-column-patch failure this ticket exists to end.
func TestEveryParkStateConsumerIsNarrowed_STATBUS242(t *testing.T) {
	src := readUpgradeServiceSource(t)

	const call = "d.upgradeParkedReason(ctx"
	consumers := strings.Count(src, call)
	// One of the occurrences is UpgradeParkedReason's own delegation, not a
	// decision site.
	const delegation = 1
	decisionSites := consumers - delegation
	if decisionSites < 1 {
		t.Fatal("no park-state consumers found — the scan lost its subject; a check that examines nothing must fail")
	}

	narrowed := strings.Count(src, "parkStateUnknown(")
	// One occurrence is the helper's own definition.
	narrowedSites := narrowed - 1

	// The one deliberately-unnarrowed site must SAY it is deliberate, at the
	// line, with the reason that makes it safe.
	if !strings.Contains(src, "DELIBERATELY LEFT FAIL-OPEN") {
		t.Error("the self-heal park check is deliberately left fail-open; that decision must be recorded at the line, or the next reader cannot tell it from an oversight")
	}
	if !strings.Contains(src, "AND recovery_parked_at IS NULL` — verified") {
		t.Error("the unnarrowed site's safety rests on the self-heal UPDATE's SQL belt guard — the comment must say that guard was VERIFIED present, not inferred")
	}

	if narrowedSites+1 != decisionSites {
		t.Errorf(`park-state consumers are not all classified: %d decision site(s), %d narrowed, 1 recorded-as-safe.

A NEW park-state consumer must be classified before it ships:
  - reaches a restore or a state change on the row  -> narrow it (treat UNKNOWN as parked)
  - guarded downstream by its own SQL predicate     -> record WHY at the line
42703 stays fail-INFORMED everywhere: the column's absence PROVES the row is not
parked, and at RecoveryBudgetGuard it is load-bearing — boot migrate is what
creates that column, so treating it as unknown would deadlock the bootstrap.`,
			decisionSites, narrowedSites)
	}
}

// TestRestoreBearingSitesRefuseOnUnknown_STATBUS242 pins the direction of the
// fix where it matters most: the three consumers that can reach a restore must
// set parked=true on an unknown read, so the refusal arm that already exists is
// the one an unverified row takes.
func TestRestoreBearingSitesRefuseOnUnknown_STATBUS242(t *testing.T) {
	src := readUpgradeServiceSource(t)
	for _, want := range []string{
		"refusing to restore on an unverified row",
		"refusing to reconcile an unverified row",
		"refusing the automatic resume on an unverified row",
	} {
		if !strings.Contains(src, want) {
			t.Errorf("a restore-bearing park-state consumer no longer refuses on an unknown read (missing %q). Proceeding there rewinds a live park's columns and un-parks the row into the failure it stopped at", want)
		}
	}
	// The refusal must be reached by joining the EXISTING parked arm rather than
	// growing a second, drifting copy of the refusal logic. THREE, not four:
	// the three restore-bearing sites set parked = true and fall into the arm
	// that was already there; RecoveryBudgetGuard's refusal is `return true`
	// (skip boot migrate), which IS its existing parked arm — it has no shared
	// branch to join. Counting four here was my own miscount, corrected against
	// the code rather than the code being bent to the count.
	if n := strings.Count(src, "parked = true"); n < 3 {
		t.Errorf("the three restore-bearing sites must join the existing parked branch (parked = true) rather than each growing its own refusal path — two copies of one refusal drift; found %d", n)
	}
}

func readUpgradeServiceSource(t *testing.T) string {
	t.Helper()
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	b, err := os.ReadFile(filepath.Join(filepath.Dir(thisFile), "service.go"))
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}
