---
id: STATBUS-263
title: >-
  task-cleanup-fk: worker task_cleanup has been failing since 2026-05-13 on an
  FK violation — completed tasks cannot be deleted, and nobody was told
status: Done
assignee:
  - '@engineer'
created_date: '2026-08-27 12:41'
updated_date: '2026-08-27 17:38'
labels:
  - worker
  - norway
dependencies: []
priority: medium
type: bug
ordinal: 256000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found during the STATBUS-262 sweep on rune (no.statbus.org): worker.tasks row 536277, command task_cleanup, state failed, created 2026-05-13 — "update or delete on table \"tasks\" violates foreign key constraint" on DELETE FROM worker.tasks WHERE state = 'completed'. The box holds 605k completed task rows.

Two defects, not one: (1) the cleanup's DELETE collides with an FK referencing worker.tasks — either the FK lacks the right ON DELETE behaviour or the cleanup must delete dependents first; (2) a maintenance task failing continuously since May was invisible — same silence family as STATBUS-262's week-long read-only refusals (the loud-guard question there covers this case too).

Architect concurred on 2026-08-27 that this is its own root-cause, not foldable into 262. Investigate against the schema the box actually runs; check whether other fleet boxes show the same failed cleanup.

WHAT IS ACHIEVED: completed-task cleanup works again fleet-wide, and a failing maintenance task cannot stay silent for months.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: engineer
created: 2026-08-27 16:15
---
**DIAGNOSIS — no code written, awaiting the architect's verdict on shape.**

**Purpose in two sentences:** cleanup did not fail repeatedly since May; it failed ONCE and was never rescheduled, because the statement that reschedules it is the last statement in the procedure that threw. The FK collision is the trigger; the missing reschedule is why it never recovered, and it explains both the 605k backlog and the silence.

## The FK

Self-referential, no ON DELETE behaviour:
`tasks_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES worker.tasks(id)` — doc/db/table/worker_tasks.md:54.

Default NO ACTION, non-deferrable. Postgres implements NO ACTION as an AFTER-STATEMENT check, so one DELETE removing a parent AND all its children together is fine. **The violation requires a child that SURVIVES the statement.** That end-of-statement property is load-bearing for every shape below and is the first thing I will pin in pg_regress during the build — asserted here from documented semantics, not yet from a run.

## Why a child survives — the predicate is on the wrong column

`DELETE ... WHERE state='completed' AND process_start_at < now() - 7 days` (then failed/30 days).

`process_start_at` is when a task STARTED. A parent starts BEFORE its children, so **a parent becomes deletable before its own children do** — the predicate orders the tree in exactly the wrong direction. The schema says it: *"For parent tasks: completed_at > process_stop_at (gap = child execution time)"*.

A tree entirely on one side of the cutoff deletes cleanly; the failure needs a cutoff that BISECTS a tree. For a tree of duration D under daily cleanup that happens with probability ~D/24h — across hundreds of trees, a matter of time, and 2026-05-13 was the day. Independent second route: a **failed child is retained 30 days while a completed parent is retained 7** — a 23-day window where the parent is deletable and its child is not.

## Why it never came back — the real severity

`DELETE; DELETE; PERFORM worker.enqueue_task_cleanup(...)` — the reschedule is LAST. The DELETE raises → procedure aborts → transaction rolls back → the enqueue never runs. `idx_tasks_task_cleanup_dedup` (UNIQUE on command WHERE command='task_cleanup' AND state='pending') means cleanup exists only while a pending row does. No pending row, and no other periodic caller — the only other reference is `worker.setup()`, install/migration time only. **Cleanup was dead from that moment.** Not degraded: dead. One failed row from May beside 605k undeleted rows is exactly that signature.

## Proposed shape (for ruling, not built)

**(a) Retention on `completed_at`, not `process_start_at`.** Semantically right — "keep N days after it FINISHED" — and it inverts the ordering into the safe direction, since a parent's completed_at is later than every child's. Verified non-NULL for exactly the states cleanup targets: completed (worker_process_tasks:230-231), all three failed branches (:249, :266, :275), parents (complete_parent_if_ready:59,67), cascade-failed descendants (:18); NULL only for `waiting`, which cleanup never touches.

**(b) `AND NOT EXISTS (SELECT 1 FROM worker.tasks c WHERE c.parent_id = t.id)`** on both DELETEs, for the residual asymmetry. Index-supported by `idx_tasks_parent_id`. Deletes bottom-up; deep trees peel over successive runs — or the run iterates to a fixpoint, which is a sub-question for the architect.

**(c) The reschedule must survive a failed run — the half that matters most.** With (a) and (b) perfect, the next unforeseen error still kills cleanup permanently. The procedure is one transaction, so an early enqueue rolls back too; it cannot simply move to the top. **Genuine design question, and why this is a ruling not a build:** does "a recurring maintenance task must be rescheduled even when its run fails" belong in this procedure (catch, record, re-enqueue, re-raise) or in the worker's task runner for the whole maintenance family? The latter is the general answer and neighbours STATBUS-267. I have not assumed.

**REJECTED, named so it is not re-proposed: `ON DELETE CASCADE`** — it would cascade the deletion of an old completed parent into children that are pending or processing, destroying live work to tidy history.

## Defect 2 — the silence

The failed row was there all along; nothing looked. Not building 267 here, but whatever (c) becomes must make a failed cleanup audible rather than a row nobody queries.

## Fleet check — not yet answered

No fleet reads in this unit. Read-only query for the operator, per box:
`SELECT id, state, created_at, left(error,120) FROM worker.tasks WHERE command='task_cleanup';` and `SELECT count(*) FROM worker.tasks WHERE state='completed';`

**A box with NO pending task_cleanup row has the same dead cleanup, whatever its row count says today** — that absence, not the count, is the discriminator.
---

author: architect (pinned by foreman)
created: 2026-08-27 16:18
---
RULING (2026-08-27). (c) is FORCED, not chosen: in-procedure reschedule is structurally impossible — catch/record/re-enqueue/re-raise puts the enqueue inside the transaction the re-raise rolls back; catching without re-raising swallows the failure. The choice in-procedure is between losing the reschedule and losing the signal; Postgres has no autonomous transaction. THEREFORE THE WORKER'S RUNNER schedules — for the WHOLE maintenance family (any recurring task with its enqueue inside its own transaction carries the identical landmine), and DECOUPLED FROM OUTCOME: the runner schedules the next occurrence regardless of how this one ended; a result determines whether we alarm, never whether it runs again.

GENERAL PRINCIPLE, named for faster recognition next time: WHAT MUST SURVIVE A FAILURE CANNOT LIVE INSIDE THE THING THAT FAILS — the flag file across a volume rewind, the runner across a transaction rollback: same shape, different layer.

(a) retention on completed_at CONFIRMED (correct semantics and correct topology — children deletable before parents). (b) NOT EXISTS guard CONFIRMED, with the recorded consequence: a stuck task pins its ancestors forever — the stuck-task wedge gains a second symptom (unbounded retention growth), another reason 267 earns its place; noted in both tickets. CASCADE rejection RATIFIED: on a self-referential parent FK with live children, CASCADE is a data-loss mechanism wearing a cleanup costume — recorded at the line.

(c) IS NOT COMPLETE ALONE: re-enqueueing restores recurrence; a persistently failing daily task is still the six-day silence — that half belongs to 267's family, built knowing about each other.

BUILD HAZARD: first post-fix run faces 3.5 months of backlog (rune 605k rows) no steady-state run ever faced — measure before shipping, batch if warranted (STATBUS-172's rule: correct against data written under the corruption). Migration discipline: \sf dump first, forward migration.
---

author: engineer
created: 2026-08-27 16:22
---
**THE PREMISE IS NOW PROVEN BY A RUN, NOT BY DOCUMENTATION.** Shape-independent groundwork, built on the foreman's go while the (c) ruling is pending. One new test, frozen:

- `test/sql/095_worker_task_parent_fk_delete_semantics.sql`
- `test/expected/095_worker_task_parent_fk_delete_semantics.out`

Fast tier, GREEN. Two untracked files are the whole diff; no git operations.

## What it establishes, against the real table and the real constraint

My diagnosis rested on one property I had asserted from the manual: NO ACTION is an AFTER-STATEMENT check. Everything downstream turns on it — if it were per-row, the remedy would have to be ORDERING (delete leaves first, walk up); because it is per-statement, the remedy is instead to make the statement's SELECTION coherent (never leave a child behind). Those are different repairs, so the premise had to come from a run before any fix is written.

It does. Three arms:

1. **ONE statement deleting parent AND child together SUCCEEDS** — 0 rows remain. The parent is unreferenced only by the end of the statement, and that is enough.
2. **Deleting ONLY the parent RAISES**, with the constraint named in the asserted output:
   `ERROR: update or delete on table "tasks" violates foreign key constraint "tasks_parent_id_fkey"` / `DETAIL: Key (id)=(999263001) is still referenced from table "tasks".` Both rows then survive — the refusal rolled back rather than partially applying.
3. **Deleting the CHILD alone succeeds** — the constraint is directional; it only ever objects to a referenced row leaving while its referrer stays. Stated so the fix is not over-built.

**This is the production failure reproduced in miniature**: the bulk DELETE's predicate selected a parent but not its child. It confirms the mechanism in comment #1 and rules out the ordering-based repair.

## RED-verified — four mutations, each site asserted

`tmp/red_verify_095.sh`, log `tmp/red_verify_095.log`. Verdict AND divergence captured per mutation:

- ARM 1 made parent-only → the FK error **appears** where none belongs → red (arm 1's success is the assertion)
- ARM 2 made a joint delete → the FK error **disappears** → red (the refusal is asserted, not assumed)
- child seeded with `parent_id NULL` → the FK error disappears → red (the LINK is what raises it)
- `ROLLBACK TO SAVEPOINT` removed → everything after arm 2 dies on an aborted transaction → red (the savepoint recovery is real, not decorative)

Restored byte-identical; re-run green.

**One mutation was deliberately NOT made:** turning the closing `ROLLBACK` into `COMMIT`. It would leak seeded rows into the SHARED test database and poison later tests. The isolation property is asserted instead by the final arm — after the rollback, 0 seeded rows remain — and the reason is written at the line in the harness so nobody adds that mutation later thinking it was an oversight.

## Boundary

This constrains the fix; it does not choose it. It stays true under (a), (b), or whatever shape the (c) ruling produces, and it should land with the fix rather than before it. **Still blocked on (c)** — whether a recurring maintenance task's reschedule belongs in the procedure or in the worker's task runner.
---

author: engineer
created: 2026-08-27 16:34
---
**BUILT TO THE RULING — one step short of frozen: 096's expected output needs a seed/template rebuild, which is a shared-resource call, not mine to make.** (Correcting my #3: it closed "still blocked on (c)" — that crossed the ruling in #2 and was stale on arrival.)

## Files

- `migrations/20260827162703_task_cleanup_retention_on_completed_at_with_child_guard.{up,down}.sql`
- `migrations/20260827163000_runner_owns_recurring_maintenance_scheduling.{up,down}.sql`
- `cli/src/worker.cr` — startup seed + post-batch scheduling
- `test/sql/095_...` (+ expected) — GREEN, RED-verified, from the earlier step
- `test/sql/096_worker_recurring_maintenance_survives_failure.sql` — written, behaviour proven by prototype, expected output pending

Both down migrations were seeded from `\sf` dumps taken with stderr kept OFF the dump, per migration discipline.

## The build hazard, measured rather than guessed

Synthetic 600k backlog shaped like rune's (200k parents × 2 children), on a rolled-back transaction:

| pass | rows after | time |
|---|---|---|
| 1 (leaves) | 600k → 201k | **12.7 s** |
| 2 (parents freed by pass 1) | 201k → 1.5k | **7.6 s** |

Residue 1,500 = 1,000 stuck children + the 500 ancestors they pin — **the ruling's recorded consequence, reproduced as a number**, and written at the line.

Two design consequences fell out of the measurement, neither guessable:

1. **BATCHING IS WARRANTED** — not because 20 s is impossible but because it is an unbounded DELETE holding row locks on the worker's hottest table, and rune is slower than this machine. Batched at 10k with a runaway ceiling.
2. **THE LOOP MUST RUN TO A FIXPOINT INSIDE ONE RUN.** The guard deletes bottom-up, so a tree of depth D needs D+1 passes. Single-pass-per-day would drain **one tree level per day** — a 3.5-month backlog would take as many days as the trees are deep. That answers the sub-question I had left open.

## A second family member with the identical landmine

`worker.command_import_job_cleanup` also ends with `PERFORM worker.enqueue_import_job_cleanup()`. Same shape, same permanent-death exposure; it has survived only because its per-job DELETEs are individually wrapped — so its failures are swallowed into WARNINGs instead of raising. It is fixed here too, which is exactly why the ruling said the family, not the command.

## Shape of the (c) fix

Recurrence is now **data**: `worker.command_registry.schedule_interval` (NULL = event-driven), declared beside `handler_procedure`/`before_procedure`/`after_procedure`, which already establish that the registry describes behaviour rather than a client hard-coding it. Three functions: `ensure_recurring_task` (idempotent via the existing per-command dedup indexes — that one property makes "schedule next" and "seed if absent" the same request), `schedule_recurring_after(since)` for the runner's post-batch call, `seed_recurring_tasks()` for startup.

**Seed-if-absent lives at worker startup, beside the crash-recovery reset** as suggested — it is the one moment guaranteed to come round again, and a box with nothing pending has nothing else to trigger recovery. **Loud:** only genuinely absent rows are reported, so a healthy box says nothing and a wedged one names its own repair.

Verified empirically (`tmp/verify_263_behaviour.sql`, rolled back): recurrence declared as data ✓; **a FAILED task_cleanup still schedules the next occurrence, pending 0 → 1** ✓; seed repairs the rune case ✓; second seed reports `f`/`f`, claiming nothing ✓; non-recurring command refused loudly ✓.

Crystal type-checks clean **through the entrypoint** (`crystal build --no-codegen src/statbus.cr`) — the only build that bites.

## One trap caught before it bit

096's structural arm asserts the handlers no longer self-schedule via `pg_get_functiondef`, which returns the body **including comments** — and my migration comment quotes `PERFORM worker.enqueue_task_cleanup(...)` verbatim to explain its removal. Raw matching would have found the explanation and reported the bug it explains. Comments are stripped before matching, with the reason written at the line.

## The blocker

`./dev.sh test` now refuses correctly: `source DB "statbus_seed" is BEHIND HEAD by 2 migration(s)`, fix `./dev.sh migrate-and-test fast` — which rebuilds seed + template and runs the full fast suite under the shared test lock. **That is a shared-resource decision while others are running tests, so I have not fired it.** It blocks 096's expected output and re-running 095. I deleted the 0-byte placeholder the refused run left, so no bogus expected file is frozen into the unit.
---

author: engineer
created: 2026-08-27 17:27
---
**FROZEN — every leg green, all four suite failures resolved and attributed.** No git operations; the unit sits on disk for staging.

## Per-leg results

| leg | verdict | log |
|---|---|---|
| 096 expected via guarded `safe_update_expected` | copied, no BLOCKED | `tmp/263-step-a.log` |
| 096 verify | **ok 1 — 48 ms** | `tmp/263-step-a.log` |
| RED: fix-revert (transactional) | **RED on all arms**, restored | `tmp/red_verify_096_fix_revert.log` |
| RED: 096 test-file ×3 | **all RED**, byte-identical restore | `tmp/263-step-b.log` |
| RED: 095 test-file ×4 | **all RED**, byte-identical restore | `tmp/red_verify_095.log` |
| `generate-doc-db` | **verified whole** — 378 fn / 83 table dumps | `tmp/263-step-b.log` |
| full `migrate-and-test fast` | **85 / 89**, only the attributed four | `tmp/263-step-b.log` |
| 110 individually | **ok 1 — 69,594 ms** | `tmp/263-step-c.log` |
| 301 individually | **ok 1 — 20,257 ms** (after 2 corrupted attempts) | `tmp/263-step-c.log`, `tmp/263-step-d.log` |
| 002 + 123 baselines updated + confirmed | **ok 1, ok 2** | `tmp/263-step-e.log` |

Crystal type-checks clean through the entrypoint. Both RED harnesses verified to have restored their test files byte-identically.

## The four suite failures, all resolved

- **002** and **123** — MINE and intended. 002 gains `interval schedule_interval` in the ER diagram; 123's `p_info` now reports `{"failed_tasks_deleted": 0, "completed_tasks_deleted": 0}` per the Info Principle. Baselines updated through the guarded path (no new ERROR lines, so the errors-into-expected guard passed them on merit) and both confirmed green.
- **110** and **301** — NOT failures: corrupted artifacts (STATBUS-286). 110 also green in CI at `4a3609ede` pre-263. Their baselines were never touched.

## Unit file list (18 files)

**Migrations (4)** — both down files seeded from `\sf` dumps with stderr kept OFF the dump:
`migrations/20260827162703_task_cleanup_retention_on_completed_at_with_child_guard.{up,down}.sql`
`migrations/20260827163000_runner_owns_recurring_maintenance_scheduling.{up,down}.sql`

**Code (1):** `cli/src/worker.cr`

**Tests (4):** `test/sql/095_...sql` + `test/expected/095_...out`, `test/sql/096_...sql` + `test/expected/096_...out`

**Baselines (2):** `test/expected/002_generate_mermaid_er_diagram.out`, `test/expected/123_worker_maintenance_cleanup.out`

**doc/db (6):** 3 new — `worker_ensure_recurring_task(text, jsonb).md`, `worker_schedule_recurring_after(timestamptz).md`, `worker_seed_recurring_tasks().md`; 3 modified — both cleanup handlers + `worker_command_registry.md`

**Doc (1):** `doc/data-model.md` — one line, `command_registry(…, schedule_interval)`

## NOT part of this unit — recommend discard

`test/expected/explain/303_*` (2 files) and `test/expected/performance/109_*`. Checked rather than assumed, per the testing rules: plan shapes unchanged (25 `Seq Scan` lines added, 25 removed — same plans re-emitted), no order-of-magnitude shift (timings ~2× but entirely sub-millisecond, 0.117 → 0.251 ms), remainder is run timestamp and cost-estimate jitter. Trivial drift from the suite having run.

## STATBUS-286 evidence gathered on the way

`tmp/forensics-263/` holds three corrupted artifacts plus `notes.md`. The sharpest datum is 301: **two instances at IDENTICAL total size (68,397 bytes) with DIFFERENT zeroed regions** — start 1×4096 / 1,864 NULs, then 12×4096 / 2,705 NULs — then a clean pass. Deterministic output length, moving discontinuity, intermittent. The second instance occurred in a run where 301 was the **only** test, which removes suite concurrency, ordering and long-run duration as causes. My `blocks=4104` reading is corrected to **2304 (ratio 1.00)** in notes.md, and my "single writer" premise is recorded there as unproven — `pgrep` is point-in-time and cannot see host-side holders of the bind mount.
---

author: architect (pinned by foreman)
created: 2026-08-27 17:32
---
LANDING VERDICT (2026-08-27): AMEND, then LAND — rides rc.11. BLOCKER: both new down migrations are missing the statement terminator after the closing dollar-quote (162703 down :24, 163000 down :32) — the \sf-dump trap AGENTS.md names: the dump ends `$procedure$` with no `;`, the ups got one added, the downs did not, so the up-vs-down diff read clean while both downs are unexecutable SQL. WHY EVERY GREEN LEG MISSED IT, recorded deliberately: the suite, the RED-verifications and generate-doc-db all run migrations UP — nothing in the unit's evidence ever executed a down; the greens are real and simply do not cover the rollback path. Architect swept the last 40 down migrations: the defect is confined to these two (older flagged matches carry the `;` on the next line — checked, not counted). LATENT (six lines in 096): ensure_recurring_task's idempotence rests on a per-command partial unique index but nothing ties membership to it — both current members have theirs (idx_tasks_task_cleanup_dedup, idx_tasks_import_job_cleanup_dedup); a future third member without one would accumulate duplicate pending rows and make seed_recurring_tasks report a repair every boot (the wedge alarm crying wolf). Extend 096 Property 1 to assert index existence per recurring command. VERIFIED SOUND at the line: current_timestamp captured before the batch (worker.cr:1350→:1413 — the ordering that would silently drop occurrences if reversed); the untargeted ON CONFLICT is effectively targeted for both current members; consistent_command_in_payload survives both callers; the concurrent-child FK race is non-fatal by construction (runner schedules the next occurrence on failure — the design pays for itself on exactly its target hazard); 096 Property 5's comment-stripping praised. Foreman added to the amendment: EXECUTE both downs on the dev DB and migrate back up — close the zero-scope rollback gap empirically, not syntactically.
---

author: engineer
created: 2026-08-27 17:36
---
**AMENDED AND RE-FROZEN.** All three items done; file list unchanged at 18.

## (1) BLOCKER — the two missing terminators, fixed

```
migrations/20260827162703_..._child_guard.down.sql:24   $procedure$  ->  $procedure$;
migrations/20260827163000_runner_owns_..._scheduling.down.sql:32   $procedure$  ->  $procedure$;
```

The architect's read of the cause is exactly right, and it is worth stating plainly because it is the trap AGENTS.md names: **the `\sf` dump ends WITHOUT a terminator.** I wrote the up migrations by hand and added `;` there (:147 and :175 both carry `$procedure$;`); the down migrations I built by concatenating the dump straight in, so neither got one. And because the SAME unterminated dump seeded both sides, the up-vs-down diff looked clean — the defect was invisible to exactly the review that would normally catch it. Nothing but running the down would have found it.

## (3) THE ZERO-SCOPE GAP, CLOSED EMPIRICALLY — not "it parses now"

Ran the rollback for real on the dev database, with a probe on each side. Log: `tmp/263-step-f.log` (first attempt `tmp/263-roundtrip.log`).

| probe | scheduler_exists | seeder_exists | schedule_interval col |
|---|---|---|---|
| **A** — at head | t | t | 1 |
| **B** — after `./sb migrate down` ×2 | **f** | **f** | **0** |
| **C** — after `./sb migrate up` | t | t | 1 |

Version moved head → `20260714100527` → head. **Probe B is the point:** the rollback did not merely parse, it observably REMOVED the functions and the column. Under the unterminated files the down would have died on a syntax error and B would have read `t | t | 1`.

**A self-caught error inside this leg, reported rather than buried:** my first probe was written inline in a double-quoted shell string, so `$$` expanded to the shell PID and it failed with `trailing junk after numeric literal at or near "17364worker"` — a check that examined nothing, the exact failure mode this ticket keeps circling. The round trip itself was valid; only my probe was junk. I re-ran the whole thing with the probe in a FILE piped to psql, per CLAUDE.md's rule about SQL and shell quoting. The table above is from the corrected run.

## (2) THE LATENT GAP — 096 Property 1b, and it is load-bearing

New arm asserts, per recurring command, that its per-command partial unique index exists. Expected now pins:

```
      command       | has_dedup_index
--------------------+-----------------
 import_job_cleanup | t
 task_cleanup       | t
```

Regenerated through the guarded path (no BLOCKED) and green: `ok 1 - 096_worker_recurring_maintenance_survives_failure`.

**RED-verified, which the amendment did not ask for but a new assertion has to earn:** mutating the index predicate so it cannot match flips both rows and fails the diff —

```
- import_job_cleanup | t        + import_job_cleanup | f
- task_cleanup       | t        + task_cleanup       | f
```

So the arm reads real catalogue state rather than being vacuously true. File restored byte-identical afterwards (`diff -q` verified), and re-confirmed green on the restored bytes.

The reasoning is written at the line: a third member declared without its index would not fail loudly — `seed_recurring_tasks` would insert a duplicate pending row every boot and the startup warning, which exists to announce a wedged box, would cry wolf on every healthy start until nobody read it. **That is this ticket's own failure arriving by the opposite door: silence by noise instead of silence by absence.**

## File list — UNCHANGED, still 18

The amendment edited three existing files in place (two down migrations, one test) and regenerated one expected output. No file added, none removed. Dirty tree remains 18 unit + 3 discard (`explain/303_*` ×2, `performance/109_*`) + 1 ticket.
---

author: foreman
created: 2026-08-27 17:38
---
LANDED at b319ae4be (18 files, 1268 insertions) after the architect's LAND confirmation — he verified the amended bytes on disk rather than the report: terminators fixed on both downs (re-swept, no bare terminator remains), 096 Property 1b present with the why-silence-not-loudness reasoning at the line, and the empirical down/up round-trip praised as the correct remedy for a zero-scope green ('the remedy for a zero-scope green is to give the check scope'). Probe B (f/f/0 after the downs) is a direct empirical refutation of the defect's presence, not an inference from the fix. The engineer's self-caught $$-expands-to-shell-PID probe error — reported, corrected from a file per the quoting rule — is on the record as the recurring hazard it is. ONE NON-BLOCKING NOTE, deferred to STATBUS-267's neighbourhood: Property 1b matches indexdef LIKE '%'||command||'%', so a future command whose name is a SUBSTRING of an already-indexed one (e.g. job_cleanup vs idx_tasks_import_job_cleanup_dedup) would match the wrong index and report t — a one-line tightening when someone next opens the file; the realistic no-index-at-all case is caught correctly. Rides rc.11.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Norway's frozen-box root cause is fixed at the foundation: task_cleanup died permanently on 2026-05-13 because its reschedule lived as the last statement of the procedure that threw — one FK collision (retention cutoff bisecting a parent/child tree) rolled back the next occurrence along with the failed run, and 605k completed rows accumulated in silence. The ruling's principle — what must survive a failure cannot live inside the thing that fails — is now structure: recurrence is data (command_registry.schedule_interval), the worker's runner schedules the next occurrence regardless of outcome, startup seeds absent rows loudly (a healthy box says nothing; a wedged box names its own repair), retention follows completed_at with a NOT EXISTS child guard, batched fixpoint deletes measured against a rune-shaped 600k backlog, and command_import_job_cleanup's identical landmine is defused in the same commit. Proven by: 095 (FK statement-semantics reproducer, RED-verified x4), 096 (five properties incl. failure-survives-scheduling and per-member dedup-index existence, RED-verified), transactional fix-revert red on all arms, full fast suite 85/89 with all reds attributed, and an executed migrate-down/up round trip that empirically refuted the down-migration defect the architect's review caught (the \sf-dump missing-terminator trap — invisible to diff review because both sides seeded from the same dump). Landed at b319ae4be; rides v2026.08.0-rc.11.
<!-- SECTION:FINAL_SUMMARY:END -->
