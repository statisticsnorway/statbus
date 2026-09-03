package migrate

// STATBUS-145 slice 1 — the DAEMON SCHEMA FLOOR substrate (zero behavior change).
//
// The floor is the migration version the upgrade daemon's schema must reach for
// the daemon ITSELF to operate — query public.upgrade, read the observed state
// from db.migration, sync public.system_info, and run the release-supersede
// bookkeeping — BEFORE any upgrade's real migration delta applies. Under the
// STATBUS-145 redesign (slice 2) the two boot sites catch the schema up only to
// THIS floor with `migrate up --to DaemonSchemaFloor`; the full delta then runs
// exactly once inside the guarded applyNewSbUpgrading pipeline step. This file only
// DECLARES the floor + the relation set the bump guard enforces — it changes no
// boot behavior on its own.
//
// DECIDED (architect, over build-time ldflags derivation): a checked-in const +
// a mechanical bump-guard test. A deterministic binary and a reviewable diff beat
// build-step magic, and the guard (daemon_floor_test.go) makes forgetting to bump
// the floor impossible: any migration NEWER than the floor that touches a daemon
// relation fails the test until the floor is bumped in the same commit.
//
// VALUE: today 20260831124944 (STATBUS-308/STATBUS-326's COMMENT ON TABLE
// public.system_info, documenting that the upgrade service and the install verb
// write their own keys over a superuser connection that bypasses RLS), bumped
// from 20260828225222 in the same commit that landed it. THIS BUMP IS AN
// ACKNOWLEDGED FALSE POSITIVE — the King's ruling on STATBUS-326 (2026-08-31):
// teaching the guard to ignore comment-only statements requires semantically
// analyzing SQL, which is a hack, so the sibling guard-exemption ticket was
// killed and the guard stays exactly as it is. A COMMENT ON TABLE changes
// nothing any daemon query reads, so the daemon operates identically at this
// floor as at the one before it — the bump is honest paperwork, not a real
// schema dependency, and is taken deliberately rather than smuggling a guard
// edit into a documentation unit.
//
// Prior value: 20260828225222 (STATBUS-304's forward repair for tag-object-SHA
// pollution on the rc.14/rc.15 rows), bumped from 20260712024457 in the same
// commit that landed it. The repair migration touches public.upgrade — two
// guarded UPDATEs correcting commit_sha on rows matching the exact documented
// defect shape, plus a NOTICE — so the bump guard forced this floor
// re-decision. It is a pure DATA correction: no column added, removed,
// renamed, or retyped, and no trigger/function change, so every daemon query
// against public.upgrade resolves identically at the raised floor. Nothing is
// above the floor again, so the boot-to-floor form (slice 2) is once more a
// no-op vs boot-to-HEAD.
//
// Prior value: 20260712024457 (the STATBUS-160 upgrade_block_terminal_resurrection
// BEFORE-UPDATE trigger on public.upgrade), bumped from 20260711201432 in the same
// commit that added it. The trigger migration touches public.upgrade, so the bump
// guard forced that floor re-decision — same reasoning and approved precedent as the
// STATBUS-154 bump before it. It only ADDED a guard (a BEFORE UPDATE trigger + its
// function) that raises on the terminal→completed transition; no daemon query lost
// a column, and no legitimate daemon write performs that transition (pipeline
// completions are in_progress→completed), so the daemon operated cleanly at that
// floor too.
// Prior value: 20260901212308 (STATBUS-333's upgrade_state_log columns), bumped
// in the same commit that lands STATBUS-347's rollback_finish_pending_at column
// on public.upgrade plus its CHECK and the widened state-log trigger. The daemon
// SELECTs and UPDATEs that column at claim, at recovery, and in the finisher, so
// it cannot operate below this floor; the bump is a real schema dependency.
const DaemonSchemaFloor int64 = 20260903205636

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
//     read/write sites; the floor migration adds its
//     recovery-park columns.
//   - db.migration              — the observed-state read (MAX(version), the
//     Behind/AtNew verdict, service.go:2463).
//   - public.system_info        — config sync + self_update_error (service.go:2987/
//     3005/3617/7361, progress.go).
//   - public.release_status_type       — enum cast in upgrade INSERT/UPDATE
//     (service.go:3428/3540/3677, github.go).
//   - public.release_builds_status_type — the sibling release-build status enum.
//   - public.upgrade_supersede_older             — CALLed in discover (service.go:3019).
//   - public.upgrade_supersede_completed_prereleases — CALLed in discover (:3036).
//   - public.upgrade_schedule        — SELECTed by both daemon schedule doors.
//   - public.upgrade_retention_plan   — set-returning fn, SELECTed in retention
//     (exec.go:980).
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
	"public.upgrade_schedule",
	"public.upgrade_retention_plan",
	"public.upgrade_retention_apply",
}
