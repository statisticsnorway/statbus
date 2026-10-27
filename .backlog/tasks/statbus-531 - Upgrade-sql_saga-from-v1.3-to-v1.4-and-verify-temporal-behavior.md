---
id: STATBUS-531
title: Upgrade sql_saga from v1.3 to v1.4 and verify temporal behavior
status: In Progress
assignee: []
created_date: '2026-10-27T13:45:00Z'
updated_date: '2026-10-27T17:45:00Z'
labels:
  - database
  - dependencies
  - sql-saga
dependencies: []
priority: high
type: enhancement
ordinal: 457204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
STATBUS runs sql_saga v1.4, with its fixes verified against our temporal merge and import workloads, and with no regression in database behavior.

### Zoom out
`postgres/Dockerfile` currently pins `sql_saga_release=v1.3`. The upstream `v1.4` tag exists at `8759b7b88`. A version pin alone does not prove that our stored procedures, imports and migrations still behave correctly.

### Zoom in
- Review the upstream v1.3..v1.4 changes, including extension SQL, planner behavior and pgrx/PostgreSQL 18 compatibility, before editing the pin.
- Update `postgres/Dockerfile` to `sql_saga_release=v1.4`, and any required build or runtime definitions that the upstream release changes.
- Do not edit released STATBUS migrations to accommodate the dependency. If the upstream release requires a new migration, explain why and test both fresh installs and upgrades.
- Run the relevant sql_saga/temporal pg_regress tests and the fast suite, not just a build. Regenerate `doc/db` and generated types only if the dependency changes their outputs.

### Closing review
- **Memory:** none needed; upstream tag and test evidence are in the ticket.
- **Documentation:** record behavior changes and the upstream tag in Implementation Notes; regenerate `doc/db` only if definitions changed.
- **Cleanup:** no temporary upstream checkout in the main tree.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The upstream v1.3..v1.4 changes are reviewed, with behavior and PostgreSQL 18/pgrx compatibility notes recorded in Implementation Notes
- [x] #2 postgres/Dockerfile pins sql_saga_release=v1.4; any upstream-required STATBUS migration is forward-only and explained
- [x] #3 Relevant sql_saga/temporal pg_regress tests and the fast suite pass on fresh install and upgrade
- [ ] #4 CI is green at the change commit, including the database image build, and generated doc/db/types are updated only if their contents changed
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Upstream v1.4 tag: 8759b7b88. No GitHub Release object exists, so v1.3..v1.4 commit and schema changes are the review source.

Upstream review v1.3..v1.4 (tag 8759b7b88, reviewed from scratch clone, upstream untouched):

SCOPE: 63 commits. Extension SQL rework across src/, C extension (sql_saga.c, ~1700 lines changed), new src/3g_private_function_acl.sql + src/3h_api_trampolines.sql. native/ Rust planner UNCHANGED (no diff) -> no pgrx/cargo-pgrx requirement change; PG18-only as before. sql_saga.control default_version 1.4. Build ships generated direct update scripts 1.0/1.1/1.2/1.3 -> 1.4 via devops/generate_update_scripts_1_4.py (python3 stdlib, same mechanism as v1.3 build -> no Dockerfile build-dep change needed).

BEHAVIOR CHANGES affecting STATBUS:
1. Management functions are now SECURITY INVOKER C trampolines (api_trampoline) over private SECURITY DEFINER workers; caller must OWN each table or have REFERENCES. STATBUS migrations run as POSTGRES_ADMIN_USER (superuser) and runtime goes through admin.* SECURITY DEFINER owned by that role -> unaffected (upstream verified this in commit 20e321b).
2. temporal_merge: referenced-side regular-FK triggers (uk_update/uk_delete_check_c) are now ALWAYS deferred, even with delay_constraints => false; a reshaped timeline (DELETE+INSERT) no longer refuses or cascades. Native constraints stay immediate when delay_constraints is false.
3. Regular-to-temporal FKs gain delete_action => CASCADE (1.4); SET NULL/SET DEFAULT refused. STATBUS addendum FKs (STATBUS-524) use NO ACTION and are unchanged; CASCADE adoption is future work, not part of this pin bump.
4. TRUNCATE of a referenced parent is refused (0A000) while a child references it; truncating parent+children together (our reset path) remains allowed.
5. Add-time FK validation now follows native RI_Initial_Check identity (caller LEFT JOIN when safe, else per-row as owner with SECURITY_NOFORCE_RLS). Predicate expressions in add_unique_key are canonicalized; existing predicates normalized by the update.
6. NOTICE/WARNING/error messages now name relations schema-qualified (public.t not t) because definer search_path no longer carries public. Upstream flagged test/expected/007 as needing its expected NOTICE updated.
7. pg_restore --clean teardown exemption is now superuser-only; our seed dump/restore runs as superuser -> unaffected. STATBUS-526 extension-version gate already forces full seed rebuild when extension versions change, so incremental seeds cannot restore 1.3 catalog rows into a 1.4 image.
8. Update is atomic: each generated update script ends in sql_saga.check_integrity(); refusal rolls back everything. Upgrade path per upstream doc/upgrade.md: restart into 1.4 libraries with writers stopped, then ALTER EXTENSION UPDATE directly to 1.4 (no intermediate hop; older update scripts refuse against the 1.4 native library).

STATBUS consequence: new forward-only migration ALTER EXTENSION sql_saga UPDATE TO '1.4' (same shape as 20261021130641_sql_saga_1_3.up.sql). No edits to released migrations.

BLOCKER DIAGNOSIS (2026-10-27): `migrate-and-test fast` failed in released migration 20261021130641_sql_saga_1_3 with `55000: native library version 1.4 does not match extension update version 1.3` (tmp/531-test-fast.log:1732). Root cause is environmental, not a migration defect: the long-lived dev container's template_statbus still carried sql_saga 1.1 (init-db.sh runs only on empty PGDATA, so the template keeps the extension version of the image that first created the volume). The STATBUS-526 era guard correctly refused the cached 1.3-era seed dump ("restore old sql_saga dumps per doc/upgrade.md") and fell back to FULL_REPLAY, which forks template_statbus. The fork started at extversion 1.1: migration 1_1 skipped (guard is `= '1.0'`), migration 1_3 fired `ALTER EXTENSION ... TO '1.3'` and the upstream native-library guard correctly refused against the 1.4 libraries. Evidence: tmp/531-template-version.log (template_statbus 1.1 vs image default 1.4; statbus_local already at HEAD with extension 1.4, proving the incremental 1.3 -> 1.4 upgrade path works).

REPAIR (no released migration edited, upstream guard untouched): brought template_statbus to the image default with the upstream-prescribed direct update `ALTER EXTENSION sql_saga UPDATE TO '1.4'` (same statement the new migration runs for app DBs; never a hop through 1.3 with 1.4 libraries). tmp/531-template-repair.log: 1.1 -> 1.4, check_integrity clean.

GREEN EVIDENCE: (1) `./dev.sh migrate-and-test fast` full replay then passed all migrations including 20261027135139; suite initially red on 3 expected-output files, all reviewed as legitimate 1.4 changes: 002 mermaid ER gains the new uk_truncate_trigger (upstream TRUNCATE refusal), 008 db-security-report regenerates for the INVOKER-trampoline/private-worker ACL rework (57 changed lines, all sql_saga.*), 321 import error scenarios differ only in temporal_merge_execute line number 929 -> 941. Non-strict explain/performance baselines refreshed by the run. (2) Rerun `./dev.sh test fast`: all 117 tests passed, EXIT=0 (tmp/531-test-fast-green.log). (3) Direct 1.4 verification rerun against the upgraded dev DB (upgrade half already proven in tmp/531-proof-1.4.log; its 1.3 precondition cannot be re-established because downgrade is refused by design): extension 1.4 == native 1.4, check_integrity ok, 0 of 9 public management functions SECURITY DEFINER (trampolines confirmed), regular_user temporal write through the app view ok, 1.4 dump restores in one transaction with integrity intact and 23 legal_unit rows (tmp/531-verify-1.4-after-repair.log). (4) doc/db regenerated: gains the uk_truncate triggers and a view-deparse alias change; app types unchanged.

DESIGN GAP REPORTED (not fixed here, needs a decision): any extension bump breaks full seed replay on long-lived PGDATA because template_statbus is never re-synced to the image's extension defaults, and released update migrations refuse against a newer native library. Alternatives: (a) seed create-db aligns forked-DB extensions to pg_available_extensions defaults after CREATE DATABASE ... WITH TEMPLATE; (b) the db container entrypoint upgrades template extensions on boot when the image default is newer (writers not yet started); (c) documented manual step per extension bump (what this ticket did). Production upgrade paths are unaffected: fresh installs get 1.4 from CREATE EXTENSION; app DBs at 1.3 go direct to 1.4 via migration 20261027135139.
<!-- SECTION:NOTES:END -->
