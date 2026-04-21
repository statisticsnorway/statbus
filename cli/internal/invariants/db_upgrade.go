package invariants

// init registers invariants enforced at the DB layer on public.upgrade.
// The constraint bodies live in migrations; this file couples the
// registered triad to the constraint name so MapPgConstraint can
// translate a pgconn.PgError back into the named invariant.
func init() {
	Register(Invariant{
		Name:             "SINGLE_IN_PROGRESS_UPGRADE_AT_A_TIME",
		Class:            DBUnique,
		SourceLocation:   "migrations/20260421113651_upgrade_state_singletons.up.sql",
		ExpectedToHold:   "At most one row in public.upgrade has state='in_progress' at any time.",
		WhyExpected:      "Previously enforced only by the install flock + upgrade-service sequencing; the partial unique index upgrade_single_in_progress now binds any future bypass path (manual UPDATE, future service split, recovery tooling). Pre-ship verified 2026-04-21: fleet-wide 0 in_progress rows.",
		ViolationShape:   "INSERT or UPDATE that would produce a second in_progress row fails with pgconn.PgError{Code=23505, ConstraintName=upgrade_single_in_progress}. Go-side sites translate via invariants.MapPgConstraint and MarkTerminal so the on-disk channel is identical to a Go-native fail-fast.",
		TranscriptFormat: "INVARIANT SINGLE_IN_PROGRESS_UPGRADE_AT_A_TIME violated (DB-enforced): SQLSTATE=23505 constraint=upgrade_single_in_progress detail=<detail> (caller:<file.go:line>, pid=<pid>)",
	})
	Register(Invariant{
		Name:             "SINGLE_SCHEDULED_UPGRADE_AT_A_TIME",
		Class:            DBUnique,
		SourceLocation:   "migrations/20260421113651_upgrade_state_singletons.up.sql",
		ExpectedToHold:   "At most one row in public.upgrade has state='scheduled' at any time.",
		WhyExpected:      "The admin UI and ./sb upgrade schedule expect one queued row to pick up at a time; the partial unique index upgrade_single_scheduled enforces the cross-row singleton at the DB layer. Pre-ship verified 2026-04-21: fleet-wide 0 scheduled rows.",
		ViolationShape:   "INSERT or UPDATE that would produce a second scheduled row fails with pgconn.PgError{Code=23505, ConstraintName=upgrade_single_scheduled}. Go-side sites translate via invariants.MapPgConstraint.",
		TranscriptFormat: "INVARIANT SINGLE_SCHEDULED_UPGRADE_AT_A_TIME violated (DB-enforced): SQLSTATE=23505 constraint=upgrade_single_scheduled detail=<detail> (caller:<file.go:line>, pid=<pid>)",
	})
}
