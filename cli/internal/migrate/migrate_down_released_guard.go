package migrate

import (
	"fmt"
	"os"
	"strings"

	"github.com/statisticsnorway/statbus/cli/internal/release"
)

// IntentionallyRevertReleasedMigrationEnvVar names the environment variable
// that bypasses releasedMigrationDownGuard. Set only to deliberately revert a
// released migration in a database — e.g. to reproduce a bug against an
// older schema. The name IS the guard (matching
// release.IntentionallyFixBrokenImmutableMigrationEnvVar's naming style,
// STATBUS-172, INCLUDING its STATBUS_ prefix — team-lead's amendment,
// 2026-08-31: the ticket's bare spelling was drafting shorthand, and the
// consistency is load-bearing — one grep for STATBUS_INTENTIONALLY_ must
// find every dangerous override in the product): a cold agent reading
// STATBUS_INTENTIONALLY_REVERT_RELEASED_MIGRATION=1 in a command, script, or
// log must stop and escalate, never read it as a routine flag. There is no
// other bypass.
const IntentionallyRevertReleasedMigrationEnvVar = "STATBUS_INTENTIONALLY_REVERT_RELEASED_MIGRATION"

// releasedMigrationDownGuard refuses migrate down / down all / down --to when
// any migration about to be reverted is RELEASED — present in the previous
// release tag's migrations/ directory (STATBUS-329).
//
// NORTH STAR (the ticket): a destructive capability is guarded at the point
// of destruction, not by hoping something downstream notices.
// checkMigrationImmutability (cli/cmd/release.go) guards the release CUT —
// it diffs migrations/ FILES between git tags and never observes database
// state, so it cannot see a migrate down that reverts a migration in a
// database while leaving the file untouched. On dev the next migrate up
// self-corrects, which is why this never bit; on the SEED target, a build
// from the reverted state publishes an artifact missing that migration, and
// every installation born from that image inherits the gap invisibly.
//
// SHARED DEFINITION, NOT A SECOND ONE: "released" here is EXACTLY
// checkImmutabilityGate's own notion — release.CurrentImmutabilityBaselineTag
// resolves the identical tag checkImmutabilityGate would compare HEAD
// against right now (moved out of cli/cmd specifically so this guard could
// reuse it, STATBUS-329), and release.MigrationExistsInTag is the same
// git-tree-probe primitive release.MigrationInReleasedTag already uses for
// the runtime content-hash immutability check (eagerContentHashCheck below).
// Two independently-computed answers to "is this migration released" would
// drift silently; this guard computes zero of its own.
//
// Refuses on BOTH dev and seed targets deliberately (AC#3/architect's
// design): reverting a released migration on dev means testing against a
// schema no fleet box has — the legitimate case (reproducing a bug against
// an older schema) is exactly what the override exists for.
//
// versions is the full set about to be reverted for THIS invocation (down =
// one version; down all / --to = a range) — checked and refused atomically
// BEFORE any rollback SQL runs, so a range crossing the released/WIP boundary
// never partially reverts before refusing.
func releasedMigrationDownGuard(projDir string, versions []int64) error {
	if len(versions) == 0 {
		return nil
	}

	prevTag, err := release.CurrentImmutabilityBaselineTag(projDir)
	if err != nil {
		return fmt.Errorf("migrate down: could not resolve the previous release tag to check against: %w", err)
	}
	if prevTag == "" {
		// No previous release exists yet (the very-first-release base case) —
		// nothing can be "released", so nothing to refuse. Same "nothing to
		// check" state checkImmutabilityGate treats as an automatic pass.
		return nil
	}

	type releasedMigration struct {
		version int64
		file    string
	}
	var releasedMigrations []releasedMigration
	for _, v := range versions {
		exists, file, err := release.MigrationExistsInTag(projDir, v, prevTag)
		if err != nil {
			return fmt.Errorf("migrate down: checking whether migration %d is released: %w", v, err)
		}
		if exists {
			releasedMigrations = append(releasedMigrations, releasedMigration{v, file})
		}
	}
	if len(releasedMigrations) == 0 {
		return nil
	}

	if os.Getenv(IntentionallyRevertReleasedMigrationEnvVar) == "1" {
		// Loud acknowledgment (AC#4): the override does not silently proceed —
		// every bypassed migration is named on its own line before the
		// rollback runs, so the operator's own terminal/log carries the
		// record of what was overridden and against which release.
		for _, rm := range releasedMigrations {
			fmt.Printf("⚠ %s=1: reverting RELEASED migration %d (%s) — released in %s\n",
				IntentionallyRevertReleasedMigrationEnvVar, rm.version, rm.file, prevTag)
		}
		return nil
	}

	target, _ := currentMigrationTarget(projDir)

	var b strings.Builder
	fmt.Fprintf(&b, "migrate down refuses: %d released migration(s) among the target(s) to revert:\n", len(releasedMigrations))
	for _, rm := range releasedMigrations {
		fmt.Fprintf(&b, "  %d (%s) — released in %s\n", rm.version, rm.file, prevTag)
	}
	fmt.Fprintf(&b, "  Reverting a released migration means testing against a schema no fleet box has.\n")
	if target == "seed" {
		fmt.Fprintf(&b, "  On the SEED target: proceeding would publish an artifact MISSING this migration — every installation born from it inherits the gap.\n")
	}
	fmt.Fprintf(&b, "  Override (only to reproduce a bug against an older schema — never routine): %s=1",
		IntentionallyRevertReleasedMigrationEnvVar)
	return fmt.Errorf("%s", b.String())
}
