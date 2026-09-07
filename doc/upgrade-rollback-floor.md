# Upgrade rollback schema floor (STATBUS-354)

This document versions the accepted S3 design and its implementation plan
(both by Sol, 2026-09-04, accepted per STATBUS-347 / STATBUS-354). It is the
authoritative reference for the rollback reorder that re-establishes the
daemon schema floor inside rollback, and for the two mandatory VM arcs that
gate the first candidate carrying `public.upgrade.rollback_finish_pending_at`.

Ground truth on where the column protocol lives (2026-09-06): the column
commit is `012ca22da` on master, surgically removed by `8e021550e` for the
rc.14 line. "Merge the column branch" in the plan below means re-applying
the column portions of `012ca22da` on top of the S3 reorder; the named wip
branch is a 9-line backlog edit already on master. See the ticket's
ground-truth correction.

---

# S3 design: re-establish the daemon schema floor inside rollback

Date: 2026-09-04
Status: design only, no code in this change
Finding: SOL review 347 finding 3

King's ruling: NO inline DDL outside the migration table. NO idempotent-migration hacks. The only schema mechanism in this design is the existing `DaemonSchemaFloor` plus ordinary `sb migrate up --to <floor>` recording in `db.migration`.

## Decision summary

Run the existing bounded migration command after the database snapshot has been restored and before any SQL names `rollback_finish_pending_at`:

```text
./sb migrate up --to 20260907120000 --verbose
```

The target-version `./sb` must run this command while the target git tree is still checked out. It therefore reads the ordinary migration file from the target tree's `migrations/` directory and records success through the ordinary `db.migration` ledger. Do not inline DDL, do not make the migration idempotent, and do not invent a second migration recorder.

This requires reordering rollback. Today rollback restores the source git tree and `./sb.old` before `restoreDatabase`, which destroys both inputs needed by the floor command. The recommended order is:

1. Commit durably to rollback direction in the held marker.
2. Stop and positively verify the data-plane services.
3. Restore the database while the target tree and target `./sb` are still present.
4. Start only the existing DB container and wait for it.
5. Run target `./sb migrate up --to DaemonSchemaFloor --verbose` from the project root.
6. Only after the floor succeeds, restore the source git tree.
7. Keep target `./sb` as the canonical recovery binary. Run source-era config generation explicitly through `./sb.old config generate`.
8. Start and health-check the source-version services.
9. Write `rollback_finish_pending_at` with the still-running target process.
10. Lift SQL read-only and HTTP maintenance, finalize the row and marker, then atomically publish `./sb.old` as `./sb` last.

Two recovery-direction details are required. Reapplying the floor makes the restored database look migration-current, so observed migration state can no longer decide rollback direction by itself. Every rollback entry must durably stamp `StepRollback`, and recovery must route a `StepRollback` marker back into rollback before the ordinary post-swap at-target/behind decision. Also, final cleanup needs a recognized cleanup-only marker phase so there is no marker-free interval in which the target binary can self-heal to the source binary while the pending row is not yet committed.

## Why a floor command alone is not sufficient

The immediate SQL defect is simple: `restoreDatabase` rewinds the volume to a snapshot that predates migration `20260907120000`, then the live target process writes `rollback_finish_pending_at`. PostgreSQL returns `42703` because the column is gone.

Merely inserting a migrate command at the current location does not work:

- `restoreGitState` has already put the source tree back. The target migration file is no longer in `migrations/`.
- `restoreBinary` has already renamed `./sb.old` over `./sb`. A shell call to `./sb` therefore runs the source binary with the source binary's older `DaemonSchemaFloor`.
- The running Go process contains the target code, but migrations are not embedded. Calling code in memory does not provide the SQL file the migration engine reads from `projDir/migrations`.

A staged migration directory would require a new project-root or migration-directory override, special handling for `.env` and Docker Compose, and a staleness exemption for a target binary running against a source worktree. That is a new parallel mechanism with more recovery state. It is unnecessary.

Reordering is smaller and honest. Before source checkout, all required inputs already agree:

- executable: target `projDir/sb`
- git worktree: target commit
- migration source: target `projDir/migrations/*.up.sql`
- requested ceiling: target binary's checked-in `migrate.DaemonSchemaFloor`
- recorder: ordinary `db.migration`

## Proposed rollback phases

The current `restoreAndFinalize` combines binary restoration, config generation, database restoration, service startup, and terminal writes. It should be split conceptually so the schema floor sits at a real boundary.

### Phase A: commit to rollback direction

Before stopping or restoring anything, write the held marker's recovery step as `StepRollback` for every rollback entry, including the in-process `newSbUpgradingFailure -> rollback` route. Today `recordRollbackCommit` is called only by `recoveryRollback`, so an in-process rollback does not carry this durable direction.

Move the one-per-pass step roll into the common rollback entry, or otherwise guarantee exactly one stamp on every route:

```text
PriorDeathStep <- current Step
Step           <- StepRollback
```

Recovery must test `StepRollback` before the normal post-swap observed-position routing. Its meaning is durable intent: this actor already chose rollback while the read-only window was closed. A later schema-floor replay must not turn that decision back into a forward resume merely because `db.migration` is now at the target floor.

This also preserves the existing bounded rollback-death rule. The first crash during rollback has `StepRollback` with a non-rollback prior step and gets one retry. A second consecutive rollback death produces `StepRollback/StepRollback` and reaches the existing human stop instead of looping.

### Phase B: restore the snapshot while target recovery assets still exist

Keep the target tree and target binary in place through `restoreDatabase`.

The data-plane remains stopped and both maintenance barriers remain active. A transient on-disk mixed era exists only while nothing serves:

```text
target tree + target binary + restored source snapshot
```

That transient is intentional. No source or target app process is allowed to run in it. It exists solely so the target recovery binary can repair its own schema prerequisite.

`restoreDatabase` already consumes the identity-keyed backup path. It does not need source application code to copy the volume. The source commit can still be resolved and preflighted before this point without checking it out.

### Phase C: start DB only and apply the floor through the normal migration engine

Start the existing DB container, not the complete application set. Use the existing recovery primitive that starts the stopped DB container without recreating the volume, then wait for health.

Launch:

```text
<projDir>/sb migrate up --to <migrate.DaemonSchemaFloor> --verbose
```

with:

- command directory `projDir`
- target `./sb` still on disk
- target git tree still checked out
- the normal target `.env` and Compose project
- the existing `MigrateUpTimeout`
- captured output in the rollback progress log
- the rollback watchdog ticker still feeding systemd

The subprocess reads `migrations/20260907120000_statbus_347_rollback_finish_pending_column.up.sql` from the target worktree. It applies every ledger-missing migration at or below the floor and writes each normal `db.migration` row, including content hash. No special SQL or alternate ledger write is permitted.

On the ordinary first adoption rollback, the migration ran once before the rollback, but the snapshot restore erased both its schema effects and its `db.migration` row. Running the unchanged migration again is therefore a clean application to the restored state, not an idempotence workaround.

### Phase D: restore source application assets, but retain the target recovery authority

After the floor command returns success:

1. Restore the source git tree.
2. Do not yet call `restoreBinary`.
3. Invoke `./sb.old config generate` explicitly. `./sb.old` is the source binary and now matches the source tree, so its staleness guard is satisfied.
4. Start source-version services and pass the existing health checks.

The canonical `./sb` remains the target binary until rollback is durably final. This is required because the source binary does not understand the pending protocol. The service containers can run the source application independently of which CLI executable remains at `./sb`.

While the source tree and target binary differ, the service-held rollback marker must keep the existing staleness guard on the recovery carve-out. If the process crashes, `upgrade service` or `install` must execute the target recovery binary, not procure the source binary from the worktree.

### Phase E: write pending, reopen, finalize, then publish the source binary

After snapshot restore, floor application, source service startup, and health have all succeeded, the live target process writes the existing pending row:

```sql
UPDATE public.upgrade
   SET state = 'failed',
       rollback_finish_pending_at = now(),
       ...
 WHERE id = $id;
```

The migration is now present in the ledger, so this statement resolves. From its commit onward, the existing rule applies: never restore the snapshot again.

Then:

1. Lift SQL read-only.
2. Lift HTTP maintenance.
3. Finalize the row to `rolled_back` while clearing `rollback_finish_pending_at`.
4. Remove the cleanup marker.
5. Atomically rename `./sb.old` over `./sb` with the existing `selfupdate.Rollback` primitive.

The source binary becomes canonical only after there is no recovery work left that needs target semantics.

## Cleanup marker transaction boundary

The current finalizer removes the filesystem marker before its database transaction commits the final `rolled_back` row. With the target tree already replaced by the source tree, a crash in that interval leaves:

```text
pending DB row + no marker + target ./sb + source worktree
```

The root staleness guard sees no service-held recovery marker and may self-heal `./sb` to the source binary. That binary cannot finish the pending protocol safely.

Use a recognized cleanup-only marker phase, for example `rollback_finishing`, and make it part of the handoff:

1. Once pending is durable, mutate the held marker to `rollback_finishing`.
2. Treat that phase as target-binary recovery in `IsServiceNewSbRecovery`, so staleness never replaces the recovery binary.
3. Route it before all destructive phase logic.
4. In finalization, commit `rolled_back` plus `rollback_finish_pending_at = NULL` first.
5. Remove the `rollback_finishing` marker after the commit.

Crash interpretation is then exact:

- `rollback_finishing` plus a pending row means finish the row and marker only.
- `rollback_finishing` plus a terminal `rolled_back` row means remove the stale marker only.
- Neither shape restores the snapshot.

The marker's ID and phase must be re-read from the held descriptor under the S2 existing-only flock rules. A stale cleanup actor cannot remove a newer marker.

## Floor migration failure

A floor migration failure is not permission to continue with source services or to fall back to source recovery code. The rollback has restored the data snapshot, but the target process cannot yet execute its own durable terminal protocol.

### Durable state

On floor failure:

- Do not restore the source git tree.
- Do not restore `./sb.old` over `./sb`.
- Do not write `rollback_finish_pending_at`.
- Do not lift SQL read-only or HTTP maintenance.
- Keep app, worker, and REST stopped. The DB may remain running for diagnosis and the next migration attempt.
- Keep the service-held marker with `StepRollback` and the target commit/backup identity.
- Keep the database row `in_progress`. Do not claim `failed` or `rolled_back` using a schema whose daemon floor was not established.
- Release the process flock on exit while retaining the marker.

The automatic daemon must not spin on a known floor failure. Record a recognized marker step or phase such as `rollback_schema_floor_failed` and hold alive-idle. `./sb install` is the deliberate human retry.

### Operator message

The error must be explicit and must not suggest starting services manually:

```text
ROLLBACK_SCHEMA_FLOOR_FAILED
The database snapshot was restored, but the recovery schema floor could not be re-applied.
Application services remain stopped. HTTP maintenance and SQL read-only remain active.
The target recovery binary and migration files were preserved.
Fix the reported migration/database error, then run: ./sb install
Do not replace ./sb, check out another commit, or start the application services.
```

Include the migration filename, exit class/code, captured stderr tail, row ID, backup identity, and progress-log path.

### What `./sb install` does next

Because the target tree and target `./sb` were deliberately retained, the next `./sb install` reaches crash recovery with the same floor constant and the same migration file available. It:

1. Quiesces the automatic daemon.
2. Acquires and revalidates the existing marker.
3. Re-enters the `StepRollback` route.
4. Restores the snapshot again before retrying if the previous migrate attempt may have committed SQL without recording the ledger row.
5. Starts DB only.
6. Runs the same ordinary `sb migrate up --to DaemonSchemaFloor` command.
7. Continues source restore and finalization only if the command succeeds.

If it fails again, it returns nonzero with the same closed-box state and updated diagnostics. There is no inline repair and no migration-file mutation.

A deterministic failure of migration `20260907120000` itself is a real adoption blocker. The first candidate must prove this rollback floor on dev before Norway is attempted. If Norway-specific data makes the migration fail, Norway stays closed and human-gated. It must not escape through the old binary's vulnerable rollback order.

## Crash boundary matrix

| Boundary | Durable observation after crash | Required next action |
|---|---|---|
| Before rollback-direction stamp | Existing pre-change recovery rules. No new rollback mutation has started. | Reclassify normally. |
| After `StepRollback`, before service stop | Target tree/binary, rollback marker, DB still target/current. | `StepRollback` overrides at-target forward routing and re-enters rollback. |
| During service stop/verification | Rollback marker, barriers active, no restore authorized until positive stop verification. | Retry stop and verify. Never restore while a client may still run. |
| During snapshot rsync | Target tree/binary retained, partial restored volume, marker says rollback. | Re-run the identity-keyed restore from the beginning. |
| After snapshot restore, before DB start | Target tree/binary retained, old schema, services stopped. | Start DB only, apply floor. |
| During a transactional migration before SQL commit | Transaction rolls back, ledger row absent. | Retry ordinary migrate. |
| After migration SQL commit but before `db.migration` insert | Schema effect may exist without ledger record. No idempotent DDL is allowed. | Recovery re-restores the snapshot, erasing the unrecorded effect, then retries ordinary migrate. |
| After floor ledger record, before source git restore | Target tree/binary, restored DB at floor. | Floor is a no-op on retry. `StepRollback` still forces rollback direction. |
| During source git restore | Target binary canonical, marker present, floor recorded. Worktree may be source or incomplete. | Staleness guard defers to recovery marker. Re-run rollback/source checkout. |
| After source git restore, before source config | Target binary canonical, source tree, marker present. | Use target recovery process. Run source config via `./sb.old`. |
| During source config/start/health | Pending is not set, so writes remain blocked. | Retry rollback. Re-restoring is safe because no external writes were accepted. |
| After health, before pending write | Floor exists, writes still blocked, `StepRollback` marker. | Retry rollback. Never choose forward merely because DB max equals target floor. |
| After pending commit, before either barrier lifts | Pending row plus recovery marker. | Cleanup only. Never restore. |
| After SQL lift or HTTP lift, before final row | Pending row protects accepted writes. | Cleanup only. Never restore. |
| During final row transaction before commit | `rollback_finishing` marker plus pending row. | Retry final row and marker cleanup only. |
| After final row commit, before marker removal | `rollback_finishing` marker plus terminal row. | Remove marker only. |
| After marker removal, before source binary rename | Terminal row, no marker, target `./sb`, source tree. | Data is safe. The staleness self-heal may publish the source binary, or the running process retries the atomic rename. |
| After source binary rename | Source tree/binary, terminal row, DB intentionally at the newer additive floor. | Normal source-version operation. |

## What the source binary can and cannot do

Migration `20260907120000` is forward-compatible with the source application after the new recovery process has finalized:

- `public.upgrade.rollback_finish_pending_at` is nullable.
- The two audit columns added to `public.upgrade_state_log` are nullable.
- Old INSERT statements omit the new columns, so PostgreSQL supplies NULL.
- Old UPDATE statements omit the new columns, so PostgreSQL preserves their existing value.
- The pre-column service's terminal updates name columns explicitly. For example, commit `56559fa7a6683b0d7e2f8727091ed5bb7eb678cf` writes `state`, `error`, `rolled_back_at`, `recovery_attempts`, and `backup_path`; it does not use a positional `upgrade.*` scan.
- Its shared returning clause is `RETURNING to_jsonb(upgrade.*)`. An added JSON key does not break a Go column scan because the result remains one JSON value.
- The widened audit trigger runs in PostgreSQL and accepts old callers without caller changes.
- The old binary's lower daemon floor never migrates down. The newer `db.migration` row stays recorded, and a later target containing the same migration sees it as already applied.

This compatibility is valid only after the target recovery process has cleared pending and made the final row terminal.

The source binary is not a valid recovery authority for an in-flight pending rollback:

- It does not recognize `rollback_finish_pending_at` as a cleanup-only discriminator.
- Its old `rolled_back` UPDATE does not clear the column. If pending is non-NULL, the new CHECK constraint rejects a direct state change to `rolled_back`.
- Before pending exists, it uses the old reopen-before-terminal order that finding 3 identified as vulnerable to a second restore.

Therefore the design must not publish or self-heal to the source binary while a rollback marker or pending row remains. The additive SQL shape permits steady-state source operation. It does not make old recovery semantics safe.

## First RC carrying migration 20260907120000

### Dev

The candidate first migrates dev normally. If a later target step forces rollback:

1. The pre-candidate dev snapshot is restored.
2. The candidate's target `./sb` applies migration `20260907120000` again through the ordinary ledger because the restore erased its first application.
3. The source git tree and source services are restored.
4. The target recovery process writes pending, reopens dev, finalizes `rolled_back`, and only then publishes the source binary.
5. Dev serves the previous application version with its database intentionally one additive daemon-floor migration ahead.

The dev rollback test must force a failure after the migration succeeded, then assert the migration row remains recorded after rollback, the source app serves, pending is NULL, the marker is absent, and the source binary is canonical.

If the floor migration itself fails, dev remains maintenance/read-only with target recovery assets retained. That candidate is not eligible for Norway.

### Norway

Norway follows the same state machine. The only expected difference is duration: restoring the large Norway volume dominates, while the nullable-column/trigger floor migration should be comparatively small. The rollback watchdog must cover both the restore and floor subprocess.

During the candidate's own rollback, Norway's pre-candidate snapshot also lacks `rollback_finish_pending_at`. The target binary reapplies and records migration `20260907120000` before any pending write. Norway then returns to the previous application version while retaining the additive floor in the database.

If Norway-specific data or environment causes that floor migration to fail, the box remains closed with target tree/binary and marker intact. The operator runs `./sb install` only after investigating the captured migration failure. The source binary must not be restored as an escape hatch.

## Validation required when implemented

1. Unit/structural test that the post-restore floor command is between `restoreDatabase` and the first pending-column write.
2. Structural test that `restoreGitState` and `restoreBinary` do not precede the floor command.
3. Structural test that config generation uses `./sb.old` while target `./sb` remains canonical.
4. Recovery test that `StepRollback` overrides an apparently at-target observed state after floor replay.
5. Crash tests for the migration commit-to-ledger gap, proving the snapshot is restored before the non-idempotent migration is retried.
6. Cleanup-phase tests for both `pending + rollback_finishing marker` and `rolled_back + rollback_finishing marker`.
7. A live twin with a real non-empty snapshot whose schema predates `20260907120000`. It must restore the volume, run the floor through `sb migrate`, record `db.migration`, write pending, reopen, and finalize.
8. A live kill twin after floor success but before pending. Restart must choose rollback, not forward, despite DB max being at the target floor.
9. A live kill twin in finalization's filesystem/database boundary. Restart must stay on the target recovery binary and perform cleanup only.
10. Install-recovery VM arcs on dev before promotion. One healthy adoption rollback and one injected floor failure are minimum. Norway remains a deliberate human-canary run with the same observations.

## Recommendation

Implement the reorder, not a staged migration tree:

- Retain target tree and target `./sb` through snapshot restore and floor migration.
- Use the existing `sb migrate up --to DaemonSchemaFloor` and ordinary `db.migration` recording.
- Make rollback direction durable with `StepRollback` before any restore.
- Retain target `./sb` until pending cleanup is terminal.
- Add a recognized cleanup-only marker phase to close the finalizer's marker/DB commit gap.
- Publish the source binary last.

This is the smallest design that solves the actual first-adoption rollback. Running the floor without preserving target recovery authority fixes the `42703` but still hands crash recovery to code that can restore twice. That is not sufficient.


---

# S3 implementation plan: column protocol plus rollback schema-floor replay

Date: 2026-09-04
Source design: `tmp/sol-s3-design.md`
Preserved source branch: `wip/347-column-protocol` at `dceca3666f4d8d6dfb791165143b673f22df8a16`
Status: ready to implement after the prefix-only RC is cut

## Goal and non-negotiable mechanism

Land migration `20260907120000_statbus_347_rollback_finish_pending_column` and close finding 3 in the same RC. A rollback that restores a pre-column snapshot must re-apply `migrate.DaemonSchemaFloor` through the ordinary migration engine before the running target process writes `rollback_finish_pending_at`.

The only schema repair is:

```text
<target projDir>/sb migrate up --to <migrate.DaemonSchemaFloor> --verbose
```

The target binary runs it from the still-target worktree, reads the unchanged migration files from `<projDir>/migrations`, and records them in `db.migration`. There is no inline DDL, no idempotent migration, no embedded migration copy, and no alternate ledger.

## Branch preparation

1. Keep `wip/347-column-protocol` immutable as the exact pre-sequencing snapshot.
2. After the prefix RC is published, create the implementation branch from the then-current `master` so it includes any release-cut follow-up.
3. Restore the column protocol as an explicit forward commit using the preserved WIP branch as the source. The intended diff is the inverse of `8e021550e`, excluding any unrelated later master changes. Verify it reproduces migration `20260907120000`, its pg_regress repair coverage, `DaemonSchemaFloor = 20260907120000`, column readers, generated artifacts, and the column-form live twins while retaining S1, S2, `pgtype.Text`, and `execObserved`.
4. Implement S3 on top in reviewable phases below. Do not combine the protocol restoration and the rollback reorder into an opaque commit.

## Phase 1: make rollback direction durable before any destructive action

### Functions

- `cli/internal/upgrade/service.go`
  - `rollback`
  - `recoveryRollback`
  - `recordRollbackCommit`
  - `recoverFromFlag`
- `cli/internal/upgrade/recovery_escalation.go`
  - existing `StepRollback` interpretation and consecutive-death decision

### Changes

1. Move or invoke the `recordRollbackCommit` transition at the common `rollback` entry so every route, including in-process `newSbUpgradingFailure -> rollback`, durably writes:
   - `PriorDeathStep <- old Step`
   - `Step <- StepRollback`
2. Prevent `recoveryRollback` from double-stamping the same pass. There must be exactly one rollback-direction transition per actual rollback attempt.
3. In `recoverFromFlag`, route a held, revalidated `StepRollback` marker into rollback before ordinary observed-state routing. This route wins even if floor replay has made `MAX(db.migration.version)` look at-target.
4. Preserve the existing death budget:
   - first `StepRollback` death retries rollback
   - consecutive `StepRollback/StepRollback` reaches the existing human stop or park outcome
5. Keep S2 authorization: acquire the existing marker without `O_CREATE`, then re-read ID, holder, and phase/step from the held descriptor before acting.

### Tests

- Structural test that common `rollback` stamps `StepRollback` before stop/restore.
- Unit table for every rollback entry proving one stamp, not zero or two.
- Recovery routing test: `StepRollback` plus an apparently at-target ledger still chooses rollback, never forward resume.
- Existing rollback-death escalation tests remain green and gain the in-process entry case.

## Phase 2: retain target recovery assets through snapshot restore and floor migration

### Functions

- `cli/internal/upgrade/service.go`
  - `restoreAndFinalize`
  - `restoreDatabase`
  - `restoreGitState`
  - `restoreBinary`
  - `rollback`
  - `ReattemptRestore`
- Existing command runner and timeout:
  - `runCommandToLog`
  - `MigrateUpTimeout`
- Existing boot examples to mirror, not duplicate semantically:
  - `Service.Run` floor migrate
  - `cmd/runCrashRecovery` floor migrate in `cli/cmd/install_upgrade.go`

### Changes

Split the current restore tail into explicit boundaries, preferably small named helpers whose order is structurally testable:

1. `restoreRollbackSnapshotWithTargetAssets`
   - target worktree remains checked out
   - target `projDir/sb` remains canonical
   - app, worker, REST, and DB have been stopped and positively verified
   - call `restoreDatabase`
2. `startRollbackDatabaseOnly`
   - start only the existing DB container without recreating the restored volume
   - wait for DB health
   - reconnect the running target process as needed
3. `reapplyRollbackDaemonSchemaFloor`
   - run `filepath.Join(projDir, "sb"), "migrate", "up", "--to", strconv.FormatInt(migrate.DaemonSchemaFloor, 10), "--verbose"`
   - working directory is `projDir`
   - output is appended to the rollback progress log
   - timeout is `MigrateUpTimeout`
   - the existing rollback watchdog ticker remains active
4. Only after that command succeeds may the flow call `restoreGitState`.
5. Do not call `restoreBinary` at the beginning of `restoreAndFinalize`. Publishing the source binary moves to the final phase.

The temporary state `target tree + target binary + restored source snapshot` is permitted only with all data-plane services stopped and both maintenance barriers active.

### Failure contract

If the floor command fails:

- keep target tree and target `./sb`
- keep app, worker, and REST stopped
- keep SQL read-only and HTTP maintenance active
- keep the service-held marker, its backup identity, and `StepRollback`
- keep the upgrade row `in_progress`
- leave DB running only for diagnosis/retry
- release the process flock while retaining the marker
- return nonzero with `ROLLBACK_SCHEMA_FLOOR_FAILED`
- include migration ceiling/file, subprocess exit class/code, stderr tail, row ID, backup path identity, and progress-log path
- tell the operator only to correct the reported cause and run `./sb install`

Add a recognized durable failure phase/step such as `rollback_schema_floor_failed`. Automatic daemon starts must hold alive-idle rather than repeatedly executing a known deterministic floor failure. `./sb install` quiesces the unit, acquires and revalidates the existing marker, re-enters rollback, restores the snapshot again to erase any SQL-commit-before-ledger gap, and retries the ordinary floor migrate.

## Phase 3: restore source tree and services while target binary remains recovery authority

### Functions

- `restoreAndFinalize`
- `restoreGitState`
- config-generation call currently near the start of `restoreAndFinalize`
- `restoreBinary`

### Changes

1. After floor success, call `restoreGitState` for the source commit.
2. Keep target `./sb` canonical.
3. Run source-era configuration explicitly with `filepath.Join(projDir, "sb.old"), "config", "generate"`. `sb.old` is the source binary and now matches the source worktree, so its staleness check is valid.
4. Start the source-version services and perform the existing DB, REST, app, and reconnect health checks.
5. Treat any source restore/config/start/health failure as rollback-incomplete while writes remain blocked. Do not publish the source binary or claim healthy rollback.

### Tests

- Structural order test: `restoreDatabase < DB-only start < floor migrate < restoreGitState < sb.old config generate < source service start < pending write`.
- Negative structural assertions: neither `restoreGitState` nor `restoreBinary` may precede the floor command.
- Structural test that config generation names `sb.old`, not canonical `sb`.
- Existing staleness tests updated to prove a service-held rollback marker keeps target `sb` authoritative over a source worktree.

## Phase 4: add a cleanup-only marker phase and publish source binary last

### Functions

- `UpgradeFlag` phase constants and JSON compatibility in `service.go`
- `UpgradeFlag.IsServiceNewSbRecovery`
- `recoverFromFlag`
- `restoreAndFinalize`
- `finalizePendingRollbacks`
- `finalizePendingRollback`
- `clearRollbackFinishFlag`
- root/install staleness gates in:
  - `cli/cmd/root.go`
  - `cli/cmd/install_upgrade.go`
- `restoreBinary`, which calls `selfupdate.Rollback`

### Changes

1. Add a forward-compatible marker phase, for example `rollback_finishing`.
2. After the column-form pending row commits, mutate the held marker to `rollback_finishing` using the held descriptor.
3. Classify that phase as target-binary recovery in `IsServiceNewSbRecovery`; root and install staleness guards must not self-heal target `sb` away.
4. Route cleanup phase before every destructive/observed-state branch:
   - pending row + cleanup marker: finalize row, then remove marker
   - `rolled_back` row + cleanup marker: remove stale marker only
   - mismatched ID/phase: loud refusal
   - no row matching either valid shape: loud refusal, no restore
5. Reverse the current finalizer boundary:
   - lock and re-read the pending row under advisory xact lock and `FOR UPDATE`
   - commit `state='rolled_back'` and `rollback_finish_pending_at=NULL`
   - only after commit remove the cleanup marker
6. After row terminal and marker absent, call `restoreBinary`/`selfupdate.Rollback` to atomically publish `sb.old` as canonical `sb`.
7. A crash after marker removal but before rename is data-safe. The running target process retries the rename, or ordinary flagless staleness repair may publish the source binary because no target recovery semantics remain.
8. Preserve S2 rules for every cleanup actor: existing-only flock, read held descriptor, verify ID and cleanup phase before unlinking.

### SQL compatibility assertions for the old binary

Pin these facts in tests and review notes:

- `rollback_finish_pending_at` and both state-log audit columns are nullable.
- Old INSERTs omit them and receive NULL.
- Old named-column UPDATEs do not clear or corrupt them.
- `RETURNING to_jsonb(upgrade.*)` remains one JSON value despite the additive key.
- The widened trigger is server-side and accepts old callers.
- The old binary never migrates down, so migration `20260907120000` remains recorded.
- Old recovery code is not allowed to own an in-flight pending row because it neither recognizes nor clears the column.

## Phase 5: crash-boundary live twins

All Docker-reaching tests run only from the root checkout, never from a git worktree. Use two `Service` instances in one process where actor races are required. Reuse the PATH-shim and real Compose patterns from `live_restore_finalize_test.go`.

### Required live twins

1. **Real pre-column snapshot adoption rollback**
   - create a non-empty snapshot with schema max `20260901212308`
   - move to target column tree/binary
   - restore the real volume
   - assert column absent immediately after restore
   - start DB only and run target `sb migrate up --to 20260907120000`
   - assert schema column exists and `db.migration` has the exact version/hash
   - write pending, lift barriers, finalize
   - assert `rolled_back`, pending NULL, marker absent, data byte/row fingerprint unchanged, source services healthy, source binary canonical
2. **Kill after floor success, before pending write**
   - after the floor ledger row exists, kill at a dedicated injection point before pending
   - restart through plain `./sb install`
   - assert `StepRollback` overrides apparent at-target state
   - assert no forward migration/application resume and eventual healthy rollback
3. **Migration SQL commit before ledger record**
   - inject the existing commit-to-record gap during the rollback floor migrate
   - next install must restore the snapshot again before retrying the non-idempotent migration
   - assert one recorded migration and no duplicate/partial schema effect
4. **Floor failure hold and human retry**
   - inject a deterministic floor command failure
   - assert target tree/binary retained, row in_progress, marker retained, app/worker/REST stopped, SQL read-only and HTTP maintenance active, daemon alive-idle
   - remove the injected cause and run only `./sb install`
   - assert convergence through ordinary migrate
5. **Pending plus cleanup marker**
   - kill after pending commit and marker phase mutation
   - accept a sentinel write after reopen
   - restart and assert cleanup-only finalization preserves the sentinel and never calls restore
6. **Terminal row plus cleanup marker**
   - kill after DB commit but before marker unlink
   - restart and assert only marker removal and source-binary publication
7. **Cleanup actor race**
   - two services contend; delayed actor acquires existing-only flock after winner finishes or replaces marker
   - assert it cannot create, rewrite, or unlink a marker and cannot touch the row
8. **Old-binary additive-schema compatibility**
   - after successful target rollback finalization, explicitly run representative old `sb` read/write paths against the newer additive schema and assert success.

Add injection sites only where they correspond to a named durable boundary. Every twin must assert terminal row, migration ledger, marker, binary/worktree identity, maintenance/read-only state, health, and data fingerprint, not merely process exit.

## Phase 6: local validation before every commit

Before every commit, from `cli/`:

```bash
go test ./...
go vet ./...
golangci-lint run ./...
STATBUS_LIVE_DB=1 go test -run TestLive ./internal/upgrade ./internal/install
```

Then run the relevant pg_regress tests and `./dev.sh migrate-and-test fast 2>&1 | tee tmp/s3-fast.log`. Preserve all logs under `tmp/`. Regenerate types, data-model docs, `doc/db`, and Mermaid output after the migration is restored. Confirm the full-from-scratch replay and migration down/up cycle agree.

## Phase 7: two mandatory VM arcs

These cannot be substituted by local reasoning or live twins. Follow `doc/install-upgrade-testing.md`: commit, push after authorization for that future task, wait for the exact per-commit images, run on fresh paid VMs, observe, and iterate. Do not promote to Norway until both are green.

### Arc A: healthy first-adoption rollback floor replay

Create `test/install-recovery/arcs/rollback-schema-floor-adoption-arc.sh` or the catalogue-consistent equivalent.

- Install source A whose schema max is `20260901212308` and load non-empty sentinel data.
- Register and schedule target B, the first candidate carrying migration `20260907120000` and S3.
- Let B apply and record the migration, then inject a deterministic post-migration failure that enters built-in rollback.
- Observe the pre-B snapshot restore erase the column and ledger row.
- Assert the target recovery process starts DB only and re-applies the floor from B's worktree with B's `sb`.
- Assert final state `rolled_back`, migration `20260907120000` recorded with correct hash, pending NULL, marker absent, source A app healthy, source A binary canonical, no automatic restart loop, sentinel fingerprint intact.
- Assert logs show the exact order: `StepRollback`, restore, DB-only start, floor migrate, source checkout/config/start, pending/finalize, binary publish.

### Arc B: injected rollback floor failure, closed hold, install recovery

Create `test/install-recovery/arcs/rollback-schema-floor-failure-arc.sh` or the catalogue-consistent equivalent.

- Use the same real A -> B lineage and non-empty data.
- Make only the rollback-time floor reapplication fail after the snapshot restore, without corrupting the original forward application.
- Assert `ROLLBACK_SCHEMA_FLOOR_FAILED`, row remains `in_progress`, target tree and target `sb` remain, marker is `StepRollback`/failure phase, app/worker/REST remain stopped, maintenance and SQL read-only remain active, DB is available for diagnosis, daemon restart count becomes bounded and frozen.
- Assert no source checkout, no source binary publication, no pending-column write, no `rolled_back`, and no callback claiming healthy rollback.
- Remove the injected cause, run plain `./sb install`, and assert it restores the snapshot before retrying, re-applies the ordinary migration, finishes rollback, publishes source binary last, preserves data, and returns healthy.

After both arcs are green on dev, the first column RC may be offered to Norway's deliberate human canary. During Norway's own rollback, observe the same ledger reapplication and target-authority handoff. If the floor migration fails on Norway-specific data, stop: the box must remain closed with target recovery assets and wait for `./sb install` after diagnosis. Never restore the old binary as an escape hatch.

## Commit sequence recommendation

1. `upgrade: restore rollback finish column protocol`
2. `upgrade: make rollback direction durable`
3. `upgrade: reapply daemon floor after snapshot restore`
4. `upgrade: retain target binary through rollback cleanup`
5. `upgrade: cover rollback floor crash boundaries`
6. Generated artifact commit if kept separate

Each commit gets the complete mandated Go/vet/lint/live suite. The final implementation is not complete until both VM arcs have been run against the exact built commit and their observed logs support every acceptance assertion.
