package releasecmd

import (
	"github.com/statisticsnorway/statbus/cli/internal/migrate"
	"github.com/statisticsnorway/statbus/cli/internal/release"
)

// MigrateProbes returns the release engine's answers to the four
// release-related questions migration code asks (see migrate.ReleaseProbes).
// main.go installs them once. Kept here, not in internal/migrate, so the
// import direction stays release -> migrate and the STATBUS-352 policy
// closure holds by construction.
func MigrateProbes() migrate.ReleaseProbes {
	return migrate.ReleaseProbes{
		BaselineTag:            release.CurrentImmutabilityBaselineTag,
		MigrationExistsInTag:   release.MigrationExistsInTag,
		MigrationInReleasedTag: release.MigrationInReleasedTag,
		FileIsDirty:            release.FileIsDirty,
	}
}
