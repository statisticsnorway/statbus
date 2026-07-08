package migrate

// STATBUS-145 — the daemon-floor pending-delta query. Kept in its own file so the
// slice-2 addition stays a disjoint file-set from other in-flight migrate.go edits
// (commits stage whole files). Pairs with pending_above_test.go.

// HasPendingAbove reports whether any UNAPPLIED migration has a version strictly
// greater than `floor`, and how many. STATBUS-145: a flagless boot catches the
// schema up only to the daemon floor (`migrate up --to floor`); migrations ABOVE
// the floor are the real upgrade delta, applied EXACTLY ONCE inside the guarded
// applyPostSwap pipeline (or by the deliberate `./sb install` step-table), never
// blindly at boot. The count lets the flagless boot log one loud line naming how
// many migrations are deferred rather than applying them silently.
func HasPendingAbove(projDir string, floor int64) (pending bool, count int, err error) {
	migrations, err := listMigrationFiles(projDir)
	if err != nil {
		return false, 0, err
	}
	applied, err := listAppliedVersions(projDir)
	if err != nil {
		return false, 0, err
	}
	count = countPendingAbove(migrations, applied, floor)
	return count > 0, count, nil
}

// countPendingAbove is the DB-free core of HasPendingAbove: how many migrations
// have a version strictly greater than `floor` and are not in `applied`.
// Factored out so the floor arithmetic is unit-testable without a cluster.
func countPendingAbove(migrations []*MigrationFile, applied map[int64]bool, floor int64) int {
	n := 0
	for _, m := range migrations {
		if m.Version > floor && !applied[m.Version] {
			n++
		}
	}
	return n
}
