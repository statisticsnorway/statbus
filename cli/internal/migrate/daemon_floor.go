package migrate

// STATBUS-145 slice 1 — the DAEMON SCHEMA FLOOR substrate (zero behavior change).
//
// The floor is the migration version the upgrade daemon's schema must reach for
// the daemon ITSELF to operate — query public.upgrade, read the observed state
// from db.migration, sync public.system_info, and run the release-supersede
// bookkeeping — BEFORE any upgrade's real migration delta applies. Under the
// STATBUS-145 redesign (slice 2) the two boot sites catch the schema up only to
// THIS floor with `migrate up --to DaemonSchemaFloor`; the full delta then runs
// exactly once inside the guarded applyPostSwap pipeline step. This file only
// DECLARES the floor + the relation set the bump guard enforces — it changes no
// boot behavior on its own.
//
// DECIDED (architect, over build-time ldflags derivation): a checked-in const +
// a mechanical bump-guard test. A deterministic binary and a reviewable diff beat
// build-step magic, and the guard (daemon_floor_test.go) makes forgetting to bump
// the floor impossible: any migration NEWER than the floor that touches a daemon
// relation fails the test until the floor is bumped in the same commit.
//
// VALUE: today 20260711201432 (the STATBUS-154 upgrade-state-log instrumentation
// trigger on public.upgrade), bumped from 20260703210000 in the same commit that
// added the STATBUS-154 parked-invariant constraint (20260711201431) and this
// state-write trigger (20260711201432) — both migrations touch public.upgrade, so
// the bump guard forced this floor re-decision. Both only ADD objects (a CHECK
// constraint, a diagnostic table + its AFTER UPDATE trigger); no daemon query
// loses a column, so the daemon operates cleanly at the raised floor and the
// new floor-era trigger fires on the floor-era table (internally self-consistent
// per the exclusions rule below — public.upgrade_state_log is NOT a daemon
// relation, the daemon's Go never SQL-references it). Nothing is above the floor
// again, so the boot-to-floor form (slice 2) is once more a no-op vs boot-to-HEAD.
const DaemonSchemaFloor int64 = 20260711201432

// DaemonRelationNames is the schema surface the daemon's OWN SQL touches — the
// set whose shape the floor must satisfy. The bump guard flags any migration
// above DaemonSchemaFloor that references one of these, forcing a floor review.
//
// SCOPE RULE (architect): the floor set is the daemon binary's ENTIRE SQL
// surface across the whole cli/internal/upgrade package — NOT just the boot +
// recovery path. Under STATBUS-145 the alive-idle states (a parked upgrade, the
// STATBUS-144 flagless exit-20 continue) run the FULL main loop — discover, claim,
// supersede, retention — at floor schema, so every daemon query must resolve
// there. The completeness sweep test (upgrade pkg) enforces this mechanically:
// every schema-qualified identifier in the package's non-test .go must be in this
// set or a named exclusion, so "enumerated from one file" cannot recur.
//
// Schema-qualified so the bump guard's word-boundary match is exact (e.g.
// `public.upgrade` does not match `public.upgrade_supersede_older`, listed
// separately).
//
//   - public.upgrade            — the upgrade ledger: claim, state writes, and the
//                                 read/write sites; the floor migration adds its
//                                 recovery-park columns.
//   - db.migration              — the observed-state read (MAX(version), the
//                                 Behind/AtNew verdict, service.go:2463).
//   - public.system_info        — config sync + self_update_error (service.go:2987/
//                                 3005/3617/7361, progress.go).
//   - public.release_status_type       — enum cast in upgrade INSERT/UPDATE
//                                        (service.go:3428/3540/3677, github.go).
//   - public.release_builds_status_type — the sibling release-build status enum.
//   - public.upgrade_supersede_older             — CALLed in discover (service.go:3019).
//   - public.upgrade_supersede_completed_prereleases — CALLed in discover (:3036).
//   - public.upgrade_retention_plan   — set-returning fn, SELECTed in retention
//                                        (exec.go:980).
//   - public.upgrade_retention_apply  — CALLed in retention (exec.go:1020).
//
// EXCLUSIONS (why NOT in the set — the architect's self-consistency principle):
// the floor schema is INTERNALLY SELF-CONSISTENT — floor-era triggers fire on
// floor-era tables — so the floor guards ONLY against a daemon-SQL-vs-schema
// mismatch, i.e. the daemon's Go referencing a relation the floor schema lacks.
// Objects the daemon's Go never SQL-references are therefore out of scope:
// public.upgrade_retention_caps (zero Go refs), the trigger functions
// upgrade_block_obsolete_pending / upgrade_reap_ancestors_of_completed (appear
// only in a comment at service.go:3933), and public.docker_images_status_type
// (doc-comment-only at image_claim_gate.go:13 — the daemon never casts to it
// qualified in SQL). See the completeness sweep test's named-exclusion list.
var DaemonRelationNames = []string{
	"public.upgrade",
	"db.migration",
	"public.system_info",
	"public.release_status_type",
	"public.release_builds_status_type",
	"public.upgrade_supersede_older",
	"public.upgrade_supersede_completed_prereleases",
	"public.upgrade_retention_plan",
	"public.upgrade_retention_apply",
}
