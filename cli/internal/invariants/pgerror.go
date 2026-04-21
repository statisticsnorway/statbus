package invariants

import (
	"errors"
	"fmt"
	"strings"

	"github.com/jackc/pgx/v5/pgconn"
)

// MapPgConstraint inspects a pgx error and — if it represents a
// constraint violation on a DB-promoted invariant — returns the
// registered invariant name and a short observed string suitable for
// MarkTerminal / stderr transcript. Returns ("", "") for non-pgx
// errors or for constraint violations that do not correspond to a
// registered invariant; callers then fall through to their normal
// error path.
//
// Authoritative constraint-name ↔ invariant-name mapping lives here.
// The migrations are the source of truth for the constraint bodies;
// this function is the translation layer between DB violation shape
// and registered triad name so tmp/install-terminal.txt / support-bundle
// grep behaviour is identical whether the check fired in Go or in PG.
func MapPgConstraint(err error) (invariantName, observed string) {
	if err == nil {
		return "", ""
	}
	var pgErr *pgconn.PgError
	if !errors.As(err, &pgErr) {
		return "", ""
	}
	switch pgErr.ConstraintName {
	case "upgrade_single_in_progress":
		return "SINGLE_IN_PROGRESS_UPGRADE_AT_A_TIME",
			fmt.Sprintf("SQLSTATE=%s constraint=%s detail=%q",
				pgErr.Code, pgErr.ConstraintName, pgErr.Detail)
	case "upgrade_single_scheduled":
		return "SINGLE_SCHEDULED_UPGRADE_AT_A_TIME",
			fmt.Sprintf("SQLSTATE=%s constraint=%s detail=%q",
				pgErr.Code, pgErr.ConstraintName, pgErr.Detail)
	case "chk_upgrade_state_attributes":
		// The CHECK has multiple per-state arms. The only arm promoted
		// as a named invariant is the 'completed' arm's
		// log_relative_file_path IS NOT NULL clause. Detect via the
		// Detail row-echo when Postgres provides it; otherwise fall
		// through to generic handling.
		if looksLikeLogPointerViolation(pgErr.Detail) {
			return "LOG_POINTER_STAMPED",
				fmt.Sprintf("SQLSTATE=%s CHECK %s: %s",
					pgErr.Code, pgErr.ConstraintName, pgErr.Detail)
		}
		return "", ""
	}
	return "", ""
}

// looksLikeLogPointerViolation inspects a pgconn.PgError.Detail from a
// chk_upgrade_state_attributes CHECK violation and returns true when it
// plausibly points at the log-pointer arm (state='completed' with a
// null value). Postgres Detail shape:
//
//	"Failing row contains (<id>, <sha>, completed, ..., null, ...)."
//
// Every other 'completed'-arm sub-clause (completed_at, error,
// rolled_back_at) is already upheld by the code paths that reach the
// final UPDATE, so in practice a completed-row CHECK violation after
// 2026-04-21 indicates the log-pointer clause.
func looksLikeLogPointerViolation(detail string) bool {
	d := strings.ToLower(detail)
	return strings.Contains(d, "completed") && strings.Contains(d, "null")
}
