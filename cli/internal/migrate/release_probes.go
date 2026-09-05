package migrate

import "fmt"

// ReleaseProbes is the set of git-tree questions migration code asks about
// RELEASES ("is this migration in a cut release?", "which release am I
// protecting?"). They are handed in as callbacks rather than imported, so
// that internal/migrate does not depend on the release engine
// (internal/release). That import-direction rule is what lets the compiler
// prove the STATBUS-352 policy closure: ordinary box commands (cmd) reach
// internal/migrate, and must never reach release-engine code through it.
//
// The functions are supplied ONCE, by main.go, from internal/release
// (see cli/main.go and cmd/release.WireMigrateProbes). Nothing about the
// behaviour of the callers changed: the same four functions answer the same
// four questions; only their ownership moved to the process entrypoint.
type ReleaseProbes struct {
	// BaselineTag resolves the release tag the migrate-down guard protects,
	// i.e. exactly the tag the release cut's immutability gate compares
	// against (STATBUS-329: one definition of "released", never two).
	// ("", nil) means no previous release exists yet.
	BaselineTag func(projDir string) (string, error)
	// MigrationExistsInTag reports whether tag's tree holds the migration.
	MigrationExistsInTag func(projDir string, version int64, tag string) (bool, string, error)
	// MigrationInReleasedTag names the earliest release tag containing the
	// migration, or "" for genuine WIP.
	MigrationInReleasedTag func(projDir string, version int64) (string, error)
	// FileIsDirty reports whether relPath differs from HEAD.
	FileIsDirty func(projDir, relPath string) (bool, error)
}

// ReleaseProbe is the process-wide wiring. It is a zero value until main.go
// sets it; every use goes through check() first, so an unwired probe is a
// loud refusal, never a silent "nothing is released" that would let a
// released migration be reverted.
var ReleaseProbe ReleaseProbes

func (p ReleaseProbes) check() error {
	if p.BaselineTag == nil || p.MigrationExistsInTag == nil || p.MigrationInReleasedTag == nil || p.FileIsDirty == nil {
		return fmt.Errorf("release probes are not wired (BUG: main.go must set migrate.ReleaseProbe before any migration command runs)")
	}
	return nil
}
