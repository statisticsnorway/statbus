package invariants

import (
	"errors"
	"fmt"
	"testing"

	"github.com/jackc/pgx/v5/pgconn"
)

// TestMapPgConstraint_UniqueViolations covers the DB-enforced singleton
// invariants: both partial unique indices on public.upgrade surface as
// SQLSTATE=23505 + the corresponding ConstraintName when a second row
// would be written in the guarded state.
func TestMapPgConstraint_UniqueViolations(t *testing.T) {
	cases := []struct {
		name         string
		constraint   string
		wantInv      string
		wantSubstr   string
	}{
		{
			name:       "in_progress singleton",
			constraint: "upgrade_single_in_progress",
			wantInv:    "SINGLE_IN_PROGRESS_UPGRADE_AT_A_TIME",
			wantSubstr: "SQLSTATE=23505",
		},
		{
			name:       "scheduled singleton",
			constraint: "upgrade_single_scheduled",
			wantInv:    "SINGLE_SCHEDULED_UPGRADE_AT_A_TIME",
			wantSubstr: "SQLSTATE=23505",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			pgErr := &pgconn.PgError{
				Code:           "23505",
				ConstraintName: tc.constraint,
				Detail:         "Key (state)=(x) already exists.",
			}
			gotInv, gotObs := MapPgConstraint(pgErr)
			if gotInv != tc.wantInv {
				t.Errorf("invariant name: got %q, want %q", gotInv, tc.wantInv)
			}
			if gotObs == "" || !contains(gotObs, tc.wantSubstr) {
				t.Errorf("observed string missing %q: %q", tc.wantSubstr, gotObs)
			}
		})
	}
}

// TestMapPgConstraint_LogPointerCheck covers the LOG_POINTER_STAMPED
// DB-check path: a CHECK violation on chk_upgrade_state_attributes whose
// Detail shows a 'completed' row with a null column maps to the
// registered fail-fast invariant name.
func TestMapPgConstraint_LogPointerCheck(t *testing.T) {
	pgErr := &pgconn.PgError{
		Code:           "23514",
		ConstraintName: "chk_upgrade_state_attributes",
		Detail:         "Failing row contains (1, abcdef, completed, null, ...).",
	}
	gotInv, gotObs := MapPgConstraint(pgErr)
	if gotInv != "LOG_POINTER_STAMPED" {
		t.Errorf("invariant name: got %q, want %q", gotInv, "LOG_POINTER_STAMPED")
	}
	if !contains(gotObs, "SQLSTATE=23514") || !contains(gotObs, "CHECK chk_upgrade_state_attributes") {
		t.Errorf("observed missing SQLSTATE or constraint name: %q", gotObs)
	}
}

// TestMapPgConstraint_CheckOtherArm ensures that a chk_upgrade_state_attributes
// violation not matching the log-pointer arm (e.g. a future arm that trips
// on different detail) falls through rather than claiming LOG_POINTER_STAMPED.
func TestMapPgConstraint_CheckOtherArm(t *testing.T) {
	pgErr := &pgconn.PgError{
		Code:           "23514",
		ConstraintName: "chk_upgrade_state_attributes",
		Detail:         "Failing row contains (1, abcdef, in_progress, 2026-04-21, ...).",
	}
	gotInv, _ := MapPgConstraint(pgErr)
	if gotInv != "" {
		t.Errorf("expected empty invariant name for non-log-pointer arm, got %q", gotInv)
	}
}

func TestMapPgConstraint_NilAndNonPgErrors(t *testing.T) {
	if name, obs := MapPgConstraint(nil); name != "" || obs != "" {
		t.Errorf("nil error: got (%q, %q), want empty", name, obs)
	}
	plain := errors.New("garden variety error")
	if name, obs := MapPgConstraint(plain); name != "" || obs != "" {
		t.Errorf("non-pg error: got (%q, %q), want empty", name, obs)
	}
	wrapped := fmt.Errorf("wrapped: %w", &pgconn.PgError{
		Code:           "23505",
		ConstraintName: "some_unrelated_constraint",
	})
	if name, _ := MapPgConstraint(wrapped); name != "" {
		t.Errorf("unmapped constraint should return empty name, got %q", name)
	}
}

// TestSingletonInvariantsRegistered asserts the init() registrations in
// db_upgrade.go are present so the support bundle enumerates them.
func TestSingletonInvariantsRegistered(t *testing.T) {
	for _, name := range []string{
		"SINGLE_IN_PROGRESS_UPGRADE_AT_A_TIME",
		"SINGLE_SCHEDULED_UPGRADE_AT_A_TIME",
	} {
		inv, ok := Get(name)
		if !ok {
			t.Fatalf("invariant %s not registered", name)
		}
		if inv.Class != DBUnique {
			t.Errorf("%s class: got %q, want %q", name, inv.Class, DBUnique)
		}
	}
}

func contains(haystack, needle string) bool {
	for i := 0; i+len(needle) <= len(haystack); i++ {
		if haystack[i:i+len(needle)] == needle {
			return true
		}
	}
	return false
}
