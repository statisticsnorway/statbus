# STATBUS-333 design clarification

Architect deliverable, 2026-09-01. Design only. No implementation or git operations were performed.

## Decision

Ship the minimal log-based design. Keep one `public.upgrade` row per commit, keep that row as the candidate's current standing, and archive the standing it replaces in `public.upgrade_state_log`.

The minimal design is sufficient with two required details:

1. The schedule reset must also clear `backup_path`, after the trigger snapshots its old value. A retained old path would break the install classifier's invariant that `failed AND backup_path IS NOT NULL` means restore-broke.
2. New attempt logs must be created without overwrite. The current second-resolution name plus `os.Create` does not guarantee a distinct file.

No `upgrade_attempt` table is needed for STATBUS-333.

## 1. Context

There are currently two schedule writes:

- `promoteExistingCandidate` resets lifecycle and recovery fields in `cli/internal/upgrade/service.go:5172-5211`.
- `scheduleStep`, used by `RunSchedule`, repeats the same reset in `cli/internal/upgrade/service.go:5553-5561` and `cli/internal/upgrade/service.go:5618-5654`, then supersedes older candidates at `cli/internal/upgrade/service.go:5670-5676`.
- The successful NOTIFY path also supersedes older candidates outside the write through `onApplyScheduled` at `cli/internal/upgrade/service.go:5162-5169`.
- The UI performs only a direct PATCH of `state` and `scheduled_at` at `app/src/app/admin/upgrades/page.tsx:746-751`, using the helper at `app/src/app/admin/upgrades/page.tsx:217-234`.

The table is commit-centric and enforces one row per commit through `upgrade_commit_sha_key` at `doc/db/table/public_upgrade.md:35-39`. A retry therefore resets the same row. The current Go reset clears `error` and `log_relative_file_path` at `cli/internal/upgrade/service.go:5182-5195` and `cli/internal/upgrade/service.go:5637-5651`, so evidence disappears from the current row.

`public.upgrade_state_log` already records every state or park transition at the database layer. Its original purpose and trigger predicate are in `migrations/20260711201432_upgrade_state_log_instrumentation_statbus_154.up.sql:4-14` and `migrations/20260711201432_upgrade_state_log_instrumentation_statbus_154.up.sql:64-69`. Reusing it is the smallest coherent preservation mechanism.

## 2. The one schedule function

### 2.1 Exact signature

```sql
CREATE FUNCTION public.upgrade_schedule(
    p_commit_sha text,
    p_recreate boolean DEFAULT false
)
RETURNS TABLE (
    schedule_result text,
    upgrade_id integer,
    landed_state public.upgrade_state,
    superseded_count integer
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp;
```

Use `commit_sha`, not `id`, as the function key.

- The service and CLI already resolve every accepted target form to the canonical 40-character SHA before scheduling at `cli/internal/upgrade/service.go:5086-5107` and `cli/internal/upgrade/service.go:5563-5577`.
- The UI row already contains `commit_sha` at `app/src/app/admin/upgrades/page.tsx:59-66`.
- `commit_sha` is the candidate identity enforced by the database, while `id` is an internal surrogate.
- A SHA-keyed function can return `unregistered` itself. The Go caller does not need a separate `SELECT id` existence probe.

The function returns exactly one row with one of these results:

| `schedule_result` | Meaning | Mutation |
|---|---|---|
| `scheduled` | The candidate was reset and landed as `scheduled` | Target reset plus eligible older supersede |
| `superseded` | The candidate is obsolete (a newer equal/higher completed candidate exists) | No mutation — the sub-block rolls the attempt back (foreman ruling 2026-09-01) |
| `already_scheduled` | The row was already queued | Target unchanged; older-candidate supersede may run idempotently |
| `in_progress` | The row is genuinely live, not parked | No mutation |
| `restore_reattempt_required` | The row is `failed` with a retained `backup_path` | No mutation; use `./sb install` |
| `unregistered` | No candidate row has that SHA | No mutation |

The result values are text rather than a new enum to keep the migration small. The migration comment and pg_regress test must pin the vocabulary.

### 2.2 Transaction semantics

The function performs this sequence in one database transaction:

1. Select and lock the target row by `commit_sha` with `FOR UPDATE`.
2. Return `unregistered` if absent.
3. Return `in_progress` if `state = 'in_progress'` and `recovery_parked_at IS NULL`.
4. Return `restore_reattempt_required` if `state = 'failed' AND backup_path IS NOT NULL`.
5. If already scheduled, leave the target row unchanged, call `upgrade_supersede_older` idempotently, and return `already_scheduled`.
6. Otherwise, inside a plpgsql sub-block (BEGIN...EXCEPTION): call `public.upgrade_supersede_older` first, then perform the target reset, then read `RETURNING state`. If it landed `superseded` (`upgrade_block_obsolete_pending` rewrote it), RAISE a sentinel exception — the sub-block handler catches it, rolling back BOTH the reset and the older-supersedes, and the function returns `superseded` as a no-mutation refusal.
7. Return `scheduled` when the reset landed scheduled.

FOREMAN RULING (2026-09-01, from the engineer's repro tmp/statbus-333-superseded-evidence-repro.out): an already-superseded row reset by this function would have its evidence destroyed and land back in `superseded` with NO state-log row (OLD.state = NEW.state), falsifying section 6.3 for that one path. The sentinel-rollback keeps the obsolete-pending trigger as the single obsoleteness oracle (no duplicated condition probe), makes every refusal uniformly no-mutation, and makes 6.3 structurally true: any schedule that COMMITS changed state.

The reset is:

```sql
UPDATE public.upgrade AS u
   SET state = 'scheduled',
       recreate = p_recreate,
       scheduled_at = now(),
       started_at = NULL,
       completed_at = NULL,
       error = NULL,
       rolled_back_at = NULL,
       skipped_at = NULL,
       dismissed_at = NULL,
       superseded_at = NULL,
       log_relative_file_path = NULL,
       backup_path = NULL,
       recovery_attempts = 0,
       recovery_parked_at = NULL,
       recovery_parked_reason = NULL
 WHERE u.id = v_target.id
   AND (u.state <> 'in_progress' OR u.recovery_parked_at IS NOT NULL)
RETURNING u.state;
```

This preserves the current lifecycle reset at `cli/internal/upgrade/service.go:5182-5195` and `cli/internal/upgrade/service.go:5637-5651`, including the exact recovery budget values at `cli/internal/upgrade/service.go:8185-8203`.

It also adds `backup_path = NULL`. That is required, not optional:

- `failUpgrade` is expressly a pre-backup failure path at `cli/internal/upgrade/service.go:8805-8825` and writes `state='failed'` without touching `backup_path` at `cli/internal/upgrade/service.go:8831-8840`.
- The install classifier states that pre-backup failed rows have `backup_path NULL`, and that `failed AND backup_path IS NOT NULL` is exactly the restore-broke set at `cli/internal/install/state.go:250-269`.
- Today a same-row retry can retain an old backup pointer because neither Go schedule reset clears it. If the retry then fails before its own backup, it becomes a failed row with an old pointer and is misclassified as restore-reattemptable.
- Snapshotting `OLD.backup_path` in the state log before clearing it preserves the diagnostic fact without carrying the prior attempt's recovery identity into the new attempt.

### 2.3 Supersede ordering and singleton indexes

Call `public.upgrade_supersede_older` before the target reset, inside the function's transaction. The existing procedure is the authoritative hierarchy and age rule at `doc/db/function/public_upgrade_supersede_older(text, integer).md:21-45`. Do not duplicate its SQL inside the new function.

The ordering is deliberate:

- `upgrade_single_scheduled` permits at most one scheduled row at `migrations/20260421113651_upgrade_state_singletons.up.sql:19-33` and `doc/db/table/public_upgrade.md:38-39`.
- If an older eligible row is already scheduled, resetting the newer target first would hit the unique index before the older row could be superseded.
- Superseding eligible older rows first frees the singleton. If the target reset then fails, the function transaction rolls the supersede back too.
- A newer scheduled row, or one protected by release-status hierarchy, is not silently displaced. The unique index remains the final backstop and the whole function fails atomically.

`upgrade_single_in_progress` remains unchanged. The schedule function never creates an in-progress row. It only moves the same parked target from `in_progress` to `scheduled`, or leaves a live in-progress row untouched.

### 2.4 Parked rows and STATBUS-159

The existing guard is the correct distinction:

```sql
state <> 'in_progress' OR recovery_parked_at IS NOT NULL
```

It allows deliberate rescheduling of a parked row while refusing a genuinely live upgrade. The rationale is already documented at `cli/internal/upgrade/service.go:5618-5629` and `cli/internal/upgrade/service.go:8185-8203`.

There are two separate parked interactions:

1. Rescheduling the same parked commit moves that row to `scheduled` and clears its recovery budget atomically. This is the schedule function's un-park contract.
2. Scheduling a different fix release while another row is parked leaves the parked row alone. `upgrade_supersede_older` intentionally does not supersede `in_progress` rows at `doc/db/function/public_upgrade_supersede_older(text, integer).md:21-37`. The claim path then displaces the standing park and claims the new row in one transaction at `cli/internal/upgrade/service.go:5931-5959` and `cli/internal/upgrade/service.go:6026-6056`.

Do not move STATBUS-159 displacement into the schedule function. Claim-time displacement is what keeps the parked-to-superseded transition atomic with the new row becoming in progress.

### 2.5 Obsolete candidate trigger

`upgrade_block_obsolete_pending` can rewrite an attempted `scheduled` state to `superseded` when a newer completed candidate of equal or higher release status exists. The trigger body is at `doc/db/function/public_upgrade_block_obsolete_pending().md:7-24`.

The function must return the actual `RETURNING state`. Callers must not announce or redirect to maintenance when `schedule_result = 'superseded'`.

### 2.6 Already-scheduled behavior

An already-scheduled target is a no-op on the target row. This preserves the NOTIFY loop protection described beside `promoteExistingCandidate` at `cli/internal/upgrade/service.go:5172-5179`.

This is a small clean break from `RunSchedule`, which currently refreshes `scheduled_at` and can change `recreate` on an already-scheduled row. The unified function should not add a caller-specific repoke flag. If an operator needs to change queued recreate intent, unschedule and schedule again. One function should have one behavior regardless of caller.

## 3. Security model

Use `SECURITY INVOKER`, explicitly.

The state-log capture trigger was changed away from `SECURITY DEFINER` because a definer context makes `auth.uid()` observe the function owner rather than the authenticated caller. That would turn verified UI actor attribution into `absent`. The reasoning and correction are at `migrations/20260829201426_add_actor_to_upgrade_state_log.up.sql:49-64`, and the current invoker trigger body is at `migrations/20260829201426_add_actor_to_upgrade_state_log.up.sql:65-105` and `doc/db/function/public_upgrade_state_log_capture().md:2-42`.

The same rule applies one level above. A definer schedule function would cause the UPDATE and its trigger to execute under the owner identity. An invoker function preserves the caller identity.

Privileges:

```sql
REVOKE EXECUTE ON FUNCTION public.upgrade_schedule(text, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upgrade_schedule(text, boolean) TO admin_user;
```

Callers:

- The UI calls through PostgREST as an authenticated admin. `admin_user` has the write RLS policy on `public.upgrade` at `doc/db/table/public_upgrade.md:56-63` and the matching state-log write policy at `migrations/20260711201432_upgrade_state_log_instrumentation_statbus_154.up.sql:38-44`.
- The CLI and service connect as `POSTGRES_ADMIN_USER`, currently `postgres` by default, at `cli/internal/upgrade/service.go:4043-4083`. The superuser can execute the invoker function and bypasses RLS.
- CLI operator attribution must remain in the same transaction as the function call. `withActorTx` provides exactly that contract at `cli/internal/upgrade/actor.go:10-28` and `cli/internal/upgrade/actor.go:28-50`.

The function should not be granted to `authenticated` generally. Admin email roles inherit `admin_user`; regular users should fail at EXECUTE before reaching the mutation.

## 4. How every caller changes

### 4.1 Service NOTIFY path

`promoteExistingCandidate` at `cli/internal/upgrade/service.go:5180-5211` stops issuing a raw UPDATE. It calls:

```sql
SELECT schedule_result, upgrade_id, landed_state, superseded_count
FROM public.upgrade_schedule($1, false);
```

Map the returned result onto the existing Go classification around `cli/internal/upgrade/service.go:5018-5040`, extended for `in_progress`, `restore_reattempt_required`, and `superseded`.

The existing unregistered race repair remains:

- `unregistered` still enters `registerTarget`, then calls the same function again at the current flow in `cli/internal/upgrade/service.go:5122-5158`.
- `scheduled` calls `onApplyScheduled`.
- `already_scheduled` and `in_progress` retain their no-action messages.
- `restore_reattempt_required` records an actionable refusal naming `./sb install`.
- `superseded` records that the candidate is obsolete rather than claiming it was queued.

`onApplyScheduled` at `cli/internal/upgrade/service.go:5162-5169` becomes announce plus `clearApplyRefused` only. Delete its `supersedeOlderReleases` call because supersede is inside the database function.

### 4.2 CLI `RunSchedule`

Keep target resolution and the off-channel notice at `cli/internal/upgrade/service.go:5563-5617`. Inside `withActorTx`, replace the raw UPDATE at `cli/internal/upgrade/service.go:5634-5654` with the same function call, passing the CLI's `recreate` flag. Delete the later Go supersede call at `cli/internal/upgrade/service.go:5670-5676`.

Result handling:

- `scheduled`: print the existing scheduled message.
- `already_scheduled`: print that it is already queued.
- `in_progress`: retain the current refusal wording from `cli/internal/upgrade/service.go:5658-5668`.
- `restore_reattempt_required`: direct the operator to `./sb install`.
- `unregistered`: use `errNotRegistered` at `cli/internal/upgrade/service.go:5042-5047`.
- `superseded`: say the candidate is older than an installed completed candidate and was not queued.

### 4.3 UI RPC and retry controls

Replace the PATCH in `onScheduleNow` at `app/src/app/admin/upgrades/page.tsx:746-751` with a direct PostgREST RPC:

```http
POST /rest/rpc/upgrade_schedule
Content-Type: application/json

{"p_commit_sha":"<40-hex>","p_recreate":false}
```

The page already has a direct RPC pattern at `app/src/app/admin/upgrades/page.tsx:492-505`. A typed browser client call is also consistent with `app/src/app/admin/users/user-delete-action.tsx:48-61`.

On `scheduled` or `already_scheduled`, refresh and redirect to maintenance. On all other results, keep the page up and show the returned condition.

Changing only the handler is not enough to satisfy retry acceptance. The present UI exposes `onScheduleNow` only for `available` cards at `app/src/app/admin/upgrades/page.tsx:1222-1281`. Failed and rolled-back cards only offer Dismiss at `app/src/app/admin/upgrades/page.tsx:1318-1345`. Every in-progress row, including a park, is shown as Upgrading at `app/src/app/admin/upgrades/page.tsx:1311-1316`. The TypeScript `Upgrade` interface also omits `recovery_parked_at`, `recovery_parked_reason`, and `recovery_attempts` at `app/src/app/admin/upgrades/page.tsx:59-86`.

The UI part of STATBUS-333 therefore includes:

- Add the recovery fields to `Upgrade`.
- Treat `state='in_progress' AND recovery_parked_at IS NOT NULL` as Parked, not Upgrading.
- Offer the same RPC-backed Retry action for:
  - `failed` rows with `backup_path IS NULL`;
  - `rolled_back` rows;
  - parked rows.
- Do not offer RPC retry for `failed` rows with `backup_path IS NOT NULL`. Show the restore-reattempt guidance from the recovery model instead. That state is human-gated through `./sb install` at `doc/upgrade-recovery-model.md:35-39` and is selected by `cli/internal/install/state.go:250-274`.

The function enforces the restore-broke refusal as a database backstop, so a future UI or CLI cannot bypass it by mistake.

## 5. State CASE contract

The schedule reset must continue to NULL both `skipped_at` and `dismissed_at`.

The CLI list CASE deliberately places decision states above historical fields. Its tripwire explains that a rescheduled row would be rendered as dismissed or skipped if those columns survived at `cli/cmd/upgrade.go:227-276`. The new function preserves the NULLing. Update that comment to name `public.upgrade_schedule` as the one source of the contract.

Any Go source-audit tests that whitelist the old raw UPDATE, including the schedule reset roster in `cli/internal/upgrade/terminal_rewind_audit_test.go`, must be updated to assert that the raw per-door UPDATEs are gone and that callers invoke the database function instead.

## 6. Evidence preservation in `upgrade_state_log`

### 6.1 Columns

Add these nullable columns:

```sql
ALTER TABLE public.upgrade_state_log
    ADD COLUMN old_error text,
    ADD COLUMN old_log_relative_file_path text,
    ADD COLUMN old_backup_path text,
    ADD COLUMN old_recovery_parked_reason text,
    ADD COLUMN old_recovery_attempts integer;
```

Reasons:

- `old_error`: preserves the failure text by value.
- `old_log_relative_file_path`: preserves the pointer to the full attempt narrative.
- `old_backup_path`: records the recovery identity that the schedule reset now clears. This is historical metadata only. The underlying path is mutable, discussed in section 7.2.
- `old_recovery_parked_reason`: preserves the canonical park reason when un-parking or displacing.
- `old_recovery_attempts`: preserves the recovery budget value that the reset returns to zero.

Do not add old copies of every lifecycle timestamp. `old_state`, `new_state`, `old_parked_at`, `new_parked_at`, and `logged_at` already locate the transition. Omitting full attempt timestamps is part of the transition-grained trade-off.

Historical log rows remain NULL in the new columns. Do not backfill facts that were not captured at the time.

### 6.2 Capture trigger change

The current trigger function inserts transition, connection, and actor fields at `doc/db/function/public_upgrade_state_log_capture().md:7-40`. Widen only its INSERT and VALUES lists:

```sql
INSERT INTO public.upgrade_state_log (
    upgrade_id,
    old_state,
    new_state,
    old_parked_at,
    new_parked_at,
    application_name,
    query,
    backend_pid,
    logged_at,
    actor,
    actor_source,
    old_error,
    old_log_relative_file_path,
    old_backup_path,
    old_recovery_parked_reason,
    old_recovery_attempts
)
VALUES (
    NEW.id,
    OLD.state,
    NEW.state,
    OLD.recovery_parked_at,
    NEW.recovery_parked_at,
    current_setting('application_name', true),
    current_query(),
    pg_backend_pid(),
    clock_timestamp(),
    v_actor,
    v_actor_source,
    OLD.error,
    OLD.log_relative_file_path,
    OLD.backup_path,
    OLD.recovery_parked_reason,
    OLD.recovery_attempts
);
```

Keep the trigger predicate unchanged:

```sql
WHEN (
    OLD.state IS DISTINCT FROM NEW.state
    OR OLD.recovery_parked_at IS DISTINCT FROM NEW.recovery_parked_at
)
```

### 6.3 Does OLD capture the evidence before reset?

Yes. The trigger is `AFTER UPDATE FOR EACH ROW`; its `OLD` record is the pre-update row. Every relevant reset changes state, parked status, or both.

| Path | Trigger predicate | Evidence captured |
|---|---|---|
| failed to scheduled | state changes | Old error, log path, backup path, recovery count |
| rolled_back to scheduled | state changes | Old error, log path, backup path |
| completed to scheduled | state changes | Old completed attempt log path |
| dismissed, skipped, or superseded to scheduled | state changes | Old decision/failure evidence |
| parked in_progress to scheduled | state and parked timestamp change | Old park time, reason, error, log, backup, recovery count |
| `UnparkByID` | parked timestamp changes even though state stays in_progress | Old park evidence and recovery count |
| STATBUS-159 displacement | state changes and parked timestamp clears | Old park evidence before the displacement update |

The standalone un-park resets only the recovery fields at `cli/internal/upgrade/service.go:8205-8224`, so the parked timestamp leg guarantees a log row. The claim displacement changes both state and park marker at `cli/internal/upgrade/service.go:6026-6043`.

`appendParkNarrative` changes error and reason without changing state or parked timestamp at `cli/internal/upgrade/service.go:7099-7115`, so it does not create an immediate log row. That is acceptable for this design: the next un-park, reschedule, or displacement snapshots the final OLD narrative. This is one example of transition-grained rather than mutation-grained history.

## 7. On-disk evidence audit

### 7.1 Attempt logs are not guaranteed distinct today

The current name is:

```text
<upgrade-id>-<safe-version>-<UTC timestamp to one second>.log
```

`BuildLogRelPath` formats only to seconds at `cli/internal/upgrade/progress.go:103-111`. `createProgressLogFile` uses `os.Create` at `cli/internal/upgrade/progress.go:123-141`, which truncates an existing file. `executeUpgrade` creates the file at each fresh run at `cli/internal/upgrade/service.go:6194-6206`.

Therefore:

- Attempts that start in different seconds get different names and the old file remains.
- Two fresh attempts for the same row and version in the same second get the same name.
- The second `os.Create` truncates the first file.

The preservation design must close this collision. Change `NewUpgradeLog` to reserve a path with `O_CREATE | O_EXCL`. Keep the current human-readable base name, and on `EEXIST` add a numeric suffix before `.log` until creation succeeds. Persist the actual chosen basename on `public.upgrade.log_relative_file_path` as today.

Do not rely only on a higher-resolution clock. Exclusive creation is the guarantee. Add a unit test that creates two logs with the same id, version, and `startTime`, then proves the paths differ and the first file's contents remain intact.

Crash recovery is different from a fresh attempt. It intentionally reopens the current attempt's log in append mode at `cli/internal/upgrade/progress.go:172-189`, with recovery call sites such as `cli/internal/upgrade/service.go:1261-1275` and `cli/internal/upgrade/service.go:3375-3385`. That continuation should remain one file.

### 7.2 Backup paths are not immutable attempt artifacts

The database backup uses a mutable active directory. The service comments state that the same directory is reused across upgrades at `cli/internal/upgrade/service.go:6415-6428`, and the row pointer is overwritten after reconnect at `cli/internal/upgrade/service.go:7372-7391`.

`old_backup_path` therefore preserves what the row pointed to at transition time. It does not preserve the old backup bytes. A later attempt can reuse the same path for different contents. This is sufficient for diagnostic history but not for historical restore.

A full attempt table would not solve this by itself. Immutable historical backup retention would require a separate storage policy.

### 7.3 Retention consequence

Current retention reads and deletes only each upgrade row's current `log_relative_file_path` at `cli/internal/upgrade/exec.go:1082-1129`. Archived prior-attempt paths in `upgrade_state_log` are not part of that plan.

The minimal design can leave retention unchanged. Prior attempt logs may accumulate until manual cleanup, and a manually removed file leaves `old_error` intact while the old file pointer returns no content. If retry volume later makes this material, retention can consult the archived pointers in a separate change.

## 8. Trade-offs

### A. Unified reset with no evidence preservation

This is the smallest code change, but pressing Retry removes the old error and log pointer from the only candidate row. The on-disk file may still exist, but the database no longer identifies it. This does not meet the operator need behind the King's question.

Recommendation: do not choose it.

### B. Reuse `upgrade_state_log`

Benefits:

- No new attempt table.
- No multiple upgrade rows for one commit.
- No new attempt writers throughout the recovery pipeline.
- The database trigger already sees UI, CLI, service, recovery, procedure, and future writers.
- The reset transition itself performs the archival automatically.
- Error text is preserved by value even if the file disappears.

Costs and limits:

- History is transition-grained, not attempt-grained. An attempt is reconstructed from ordered transitions rather than selected directly by attempt id.
- Error text is stored directly, while the full narrative is a file pointer.
- Evidence changes that do not change state or park status are captured only at the next transition.
- The current UI fetch at `app/src/app/admin/upgrades/page.tsx:243-261` reads only `public.upgrade`. Showing prior attempts requires a second filtered query to `upgrade_state_log`, or a later view.
- `upgrade_state_log` currently has only its primary key index at `doc/db/table/public_upgrade_state_log.md:17-18`. This is acceptable for the present low-volume acceptance query. Add `(upgrade_id, id DESC)` when the UI begins loading history routinely, not merely for the DB test.

Recommendation: choose this design.

### C. Full `upgrade_attempt` table

Benefits:

- First-class attempt ids and explicit attempt start/end fields.
- Straightforward UI and analytics queries.
- Natural ownership of immutable log and artifact pointers.

Costs:

- New table, RLS, grants, retention, types, UI, and migration work.
- Every claim, terminal writer, crash recovery writer, park writer, rollback writer, and volume-rewind re-imposition path must keep the attempt row consistent.
- It overlaps the existing state log and creates a second history mechanism.
- Historical attempt backfill cannot be complete from current data.

Recommendation: do not add it for STATBUS-333. Revisit only if the product needs first-class attempt analytics or attempt-owned artifacts rather than retry evidence.

## 9. Migration sketch

Create one migration for the schema and function. Follow the function-dump rule before editing the trigger:

```bash
echo "\sf public.upgrade_state_log_capture" | ./sb psql > tmp/statbus-333-upgrade-state-log-capture.sql
```

Do not redirect stderr. The local database consulted for this design is running but behind the current actor-attribution migration: its read-only `\sf` output still showed the older `SECURITY DEFINER` body. The implementation must migrate the local database to current HEAD before taking the dump. The expected current definition has actor fields and no `SECURITY DEFINER`, as shown in `doc/db/function/public_upgrade_state_log_capture().md:2-42`.

### Up migration

1. `BEGIN`.
2. Add the five nullable evidence columns. No backfill.
3. `CREATE OR REPLACE` the trigger function from the current `\sf` dump, changing only the INSERT column and value lists.
4. Create `public.upgrade_schedule(text, boolean)` as specified.
5. Revoke PUBLIC execute and grant execute to `admin_user`.
6. Add comments to the columns and function.
7. `END`.

### Down migration

1. `BEGIN`.
2. Drop `public.upgrade_schedule(text, boolean)`.
3. Restore the exact pre-change trigger function from the unmodified `\sf` dump.
4. Drop the five evidence columns.
5. `END`.

Restore the trigger function before dropping the columns so no installed function references missing columns.

Companion non-migration changes in the same release:

- Replace both Go schedule UPDATEs with calls to the function.
- Remove Go-side supersede calls from schedule success paths.
- Update the CLI state CASE tripwire comment.
- Change the UI handler to RPC and add retry/parked controls.
- Make upgrade log creation exclusive and collision-safe.
- Regenerate database TypeScript types with `./sb types generate`.

## 10. Verification

### 10.1 pg_regress

Extend the canonical upgrade procedure test `test/sql/327_test_upgrade_procedures.sql`, rather than creating another fragmented upgrade-procedure test. Its existing supersede fixtures and assertions are at `test/sql/327_test_upgrade_procedures.sql:1-24` and `test/sql/327_test_upgrade_procedures.sql:47-146`.

Add a STATBUS-333 section with these eleven cases:

1. **Failed retry through the UI role**
   - Insert older candidate A as available.
   - Insert target B as failed with `backup_path NULL`, `error='attempt one failed'`, a non-null old log path, non-null started/scheduled timestamps, and nonzero recovery attempts.
   - Switch to the real admin fixture with `CALL test.set_user_from_email('test.admin@statbus.org')`, following the verified-actor pattern at `test/sql/128_statbus_317_upgrade_actor_attribution.sql:46-65`.
   - Call `public.upgrade_schedule(B.commit_sha, false)`.
   - Assert `schedule_result='scheduled'`, `landed_state='scheduled'`, and `superseded_count=1`.

2. **Current row clean**
   - Assert B has scheduled state and a new `scheduled_at`.
   - Assert `started_at`, `completed_at`, `error`, `rolled_back_at`, `skipped_at`, `dismissed_at`, `superseded_at`, `log_relative_file_path`, and `backup_path` are NULL.
   - Assert `recovery_attempts=0`, `recovery_parked_at IS NULL`, and `recovery_parked_reason IS NULL`.

3. **Old evidence archived before NULLing**
   - Query B's newest state-log row.
   - Assert `old_state='failed'`, `new_state='scheduled'`, the old error and log path match, the old recovery count matches, and `actor_source='verified'`.

4. **Older candidate superseded**
   - Assert A is superseded with `superseded_at` set.

5. **Parked same-row retry**
   - Create a parked in-progress target with error, log path, backup path, park reason, and recovery count.
   - Schedule it.
   - Assert it becomes scheduled and clean.
   - Assert the reset log row contains the old park time, reason, error, log path, backup path, and recovery count.

6. **Standalone un-park capture**
   - Exercise the SQL shape used by `UnparkByID`: state remains in progress while `recovery_parked_at` clears.
   - Assert one log row was added and OLD park evidence was captured.

7. **Live in-progress refusal**
   - Call the function for an in-progress row with no park marker.
   - Assert `schedule_result='in_progress'`, no row fields changed, and no state-log row was added.

8. **Restore-broke refusal**
   - Create `state='failed' AND backup_path IS NOT NULL`.
   - Assert `schedule_result='restore_reattempt_required'`, no reset occurred, and no older row was superseded.

9. **Unregistered and already-scheduled results**
   - Assert both are idempotent and do not create false state transitions.

10. **Obsolete superseded refusal is no-mutation**
    - Create an already-superseded target with retained error, log, backup, and recovery evidence plus a newer completed candidate that keeps it obsolete.
    - Add an eligible older available row that `upgrade_supersede_older` would otherwise supersede.
    - Assert `schedule_result='superseded'`, the target row is byte-identical, the eligible older row remains available, and no state-log row was added.

11. **Regular-user boundary**
    - Switch to `test.regular@statbus.org` and assert function execution is refused, following `test/sql/128_statbus_317_upgrade_actor_attribution.sql:67-77`.

This directly proves the requested acceptance path: failed row scheduled through the UI role, old error visible in the state log, current row clean, and older candidate superseded.

### 10.2 Go tests

- Add a test proving `promoteExistingCandidate` and `scheduleStep` contain no raw `UPDATE public.upgrade SET state = 'scheduled'` and both call `public.upgrade_schedule`.
- Update `scheduleResult` tests for all function outcomes.
- Add the same-second log collision test described in section 7.1.
- Keep the existing `recoveryBudgetResetGuard` tests for `UnparkByID`. Add a test or comment making clear that schedule semantics now live in SQL while install un-park remains the separate parked-only recovery action.

### 10.3 UI tests

- Available, failed-without-backup, rolled-back, and parked actions call the same RPC.
- Parked rows render Parked, not Upgrading.
- Failed-with-backup renders `./sb install` guidance and no retry button.
- `superseded`, `in_progress`, and `restore_reattempt_required` responses do not redirect to maintenance.
- `scheduled` and `already_scheduled` do redirect after refresh.

## 11. Critical files

- `.backlog/tasks/statbus-333 - schedule-function-one-door-one-database-side-schedule-function-both-UI-and-CLI-call.md:16-23`
- `cli/internal/upgrade/service.go:5018-5047`
- `cli/internal/upgrade/service.go:5060-5211`
- `cli/internal/upgrade/service.go:5553-5683`
- `cli/internal/upgrade/service.go:5931-6066`
- `cli/internal/upgrade/service.go:8185-8224`
- `cli/internal/upgrade/progress.go:103-189`
- `cli/internal/install/state.go:250-274`
- `cli/cmd/upgrade.go:227-276`
- `app/src/app/admin/upgrades/page.tsx:59-86`
- `app/src/app/admin/upgrades/page.tsx:217-234`
- `app/src/app/admin/upgrades/page.tsx:746-751`
- `app/src/app/admin/upgrades/page.tsx:1222-1345`
- `doc/db/table/public_upgrade.md:35-84`
- `doc/db/table/public_upgrade_state_log.md:1-35`
- `doc/db/function/public_upgrade_state_log_capture().md:2-42`
- `doc/db/function/public_upgrade_supersede_older(text, integer).md:2-47`
- `doc/db/function/public_upgrade_block_obsolete_pending().md:2-26`
- `doc/upgrade-recovery-model.md:25-45`
- `migrations/20260711201432_upgrade_state_log_instrumentation_statbus_154.up.sql:16-69`
- `migrations/20260829201426_add_actor_to_upgrade_state_log.up.sql:41-105`
- `test/sql/327_test_upgrade_procedures.sql:1-146`
- `test/sql/128_statbus_317_upgrade_actor_attribution.sql:35-85`
