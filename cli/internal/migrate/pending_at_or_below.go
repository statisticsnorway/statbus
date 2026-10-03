package migrate

// HasPendingAtOrBelow reports whether any unapplied migration has a version at
// or below floor. Inline upgrade dispatch uses this to avoid launching a no-op
// pre-claim migration, whose post-restore hook would otherwise run outside the
// guarded upgrade pipeline.
func HasPendingAtOrBelow(projDir string, floor int64) (bool, error) {
	migrations, err := listMigrationFiles(projDir)
	if err != nil {
		return false, err
	}
	applied, err := listAppliedVersions(projDir)
	if err != nil {
		return false, err
	}
	return countPendingAtOrBelow(migrations, applied, floor) > 0, nil
}

// countPendingAtOrBelow is the DB-free core of HasPendingAtOrBelow.
func countPendingAtOrBelow(migrations []*MigrationFile, applied map[int64]bool, floor int64) int {
	n := 0
	for _, migration := range migrations {
		if migration.Version <= floor && !applied[migration.Version] {
			n++
		}
	}
	return n
}
