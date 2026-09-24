---
id: STATBUS-382
title: >-
  After a binary swap, the upgrade service runs the new binary's logic for every
  source-sensitive step
status: To Do
assignee: []
created_date: '2026-09-22 17:01'
updated_date: '2026-09-24 14:53'
labels:
  - upgrade
  - recovery
  - cli
dependencies: []
references:
  - STATBUS-377
  - a96751064
priority: high
type: bug
ordinal: 24
---

## Incident

Norway attempted rc.28 while its checkout, on-disk `sb`, generated environment,
and serving containers were rc.20. The running
`statbus-upgrade@statbus.service` process was instead a deleted rc.18 executable:
`/proc/<pid>/exe` pointed to `sb (deleted)`, its hash differed from the on-disk
binary, and embedded strings identified rc.18.

Rc.18's pre-pull source capture runs `docker compose config --format json`
without `--profile all`. Norway's `app` service is profile-gated, so the stale
daemon emitted `restored source compose config has no image for app`. Commit
`a96751064` fixed this in rc.19 and later binaries, but the resident rc.18 daemon
continued executing its captured code after the on-disk swap.

The failure occurs before claim, target pull, backup, migration, or recovery
accounting. Rc.18 sends it through ordinary failure/reclaim rather than the park
path. Attempts repeated every 1-2 seconds: 190 attempts were observed, then
360 attempts per 10 minutes. The row kept `recovery_attempts=0`,
`recovery_parked_at=NULL`, and `failure_code=NULL`.

## Durable guard work

1. Before source-sensitive dispatch, assert that the running daemon identity
   (`/proc/self/exe`, embedded version/commit, and deleted-executable state)
   matches the on-disk `sb` and worktree identity. A mismatch refuses dispatch
   before stale source logic can run.
2. Reconcile a successfully replaced on-disk binary with the supervised upgrade
   service at a lifecycle boundary that does not interrupt a live upgrade.
3. Classify pre-claim deterministic failures as bounded park-class outcomes,
   with a causal failure code and daemon/tree provenance. They must not return
   the same candidate to an unbounded automatic reclaim loop.
4. Add an executable regression that starts an rc.18 daemon, advances the
   on-disk binary/tree/serving stack to rc.20 without restarting that process,
   schedules a profile-gated target, and proves bounded refusal or handoff.

## Done when

The daemon cannot execute source-sensitive upgrade logic under a mismatched or
deleted executable, pre-claim deterministic failures are bounded and recorded,
and the stale-rc.18/rc.20-tree regression passes through the real supervised
register/schedule/service path.

## Update 2026-09-22

Read-only rc.18 tracing and Norway box query confirm that operator dismissal is not authoritative against a reclaim loop. The resident daemon claims the candidate and its ordinary terminal failure write is an unguarded id-only statement:

```sql
UPDATE public.upgrade
   SET state = 'failed', failure_code = $1, error = $2, scheduled_at = NULL
 WHERE id = $3;
```

It can therefore clobber an operator decision that commits while the upgrade is in flight. The rc.18 claim itself only sets `state`, `started_at`, and `from_commit_version`, while the inspected `FOR UPDATE` query near the cited line is restore-reattempt authorization, not a failed-row reclaim sweep. The box still has the same row id 43727 for `fae6fa58...`, with `state=failed` and `dismissed_at` NULL, not a newly registered row.

No designed rc.18/rc.20 operator verb was found that makes all stale-daemon claim/retry paths ignore the row. `dismiss` is therefore not a loop-proof stop for this failure mode. No `skip`, pause, maintenance-wide intake brake, or `UPGRADE_*` disable toggle was found in the inspected CLI/service source. Under the owner’s no-restart/no-kill constraint, the loop requires a shipped fix or daemon lifecycle intervention.

## Reconciliation 2026-09-23

Classification: PARTIAL. Evidence: problem and exec-in-place design are established; no handoff implementation exists.

Remaining: Implement PID-preserving exec after PhaseNewSbSwapped, test flock/watchdog/error behavior, and retain crash backoff compatibility.

The rc.31 planned handoff exposed a 30.17-second gap caused by `RestartSec=30`; exit 42 does not bypass it. `tmp/handoff-and-banner.md` Task B recommends exec-in-place after the durable `PhaseNewSbSwapped` stamp, preserving PID/MainPID and normal crash backoff while reacquiring the marker flock in the new image.

## Provisional decisions for the 2026-09-23 implementation stab

1. **provisional, owner to confirm:** `./sb install` may use evidence-gated `DAEMON_TAKEOVER [STALE_BINARY_LOOP]` authority only when the resident MainPID is binary-stale, state churn proves a reclaim loop, and the durable phase is pre-destructive. Destructive phases continue to refuse takeover (R11).
2. **provisional, owner to confirm:** dismissal of a live, unparked `in_progress` row is refused at the database layer. Dismissal remains legal from `available`, `scheduled`, `failed`, `rolled_back`, and parked `in_progress` (R2).
3. **provisional, owner to confirm:** the paid harness pair is N = rc.18 (`7244856d`) and N+1 = the fix candidate. Checked 2026-09-23: the `statbus-app`, `statbus-worker`, `statbus-db`, `statbus-proxy`, and `statbus-seed` manifests tagged `7244856d` are all still retained on GHCR.

## 2026-09-23 implementation scope and remaining order

Completed in this stab: Fable step 1 (DB trigger, actor-gated `upgrade_schedule`, `claim_token`) and step 2 (NOTIFY handler discipline, deterministic pre-destructive park routing, claim-token CAS, pre-claim flock probe, flag-contention reschedule, and dismissal park cleanup).

Remaining, deliberately not started tonight:

3. Fingerprint helper and exit-42 service gate (R3-R6).
4. Install reporting sink, `os.Exit` inventory, churn diagnosis, and evidence-gated takeover (R11-R12).
5. Daemon reconciliation while the install flock remains held, plus inline-path unification (R7).
6. Paid VM harness using rc.18 (`7244856d`) to the fix candidate.

## North star

Once the new binary is swapped in, every source-sensitive step of the upgrade runs the new binary's code. A daemon still running the old image hands over to the new one before such a step.

## 2026-09-24 status

Steps 1-2 are on master at `8fcc7d8e4`. Steps 3-4 are on
`next/382-steps-3-4`, branched from `4d7ade5cf`, and are under review. Steps
5-6 have not started.

Owner decision: R11 takeover is **APPROVED** (2026-09-24 14:04) for the stale
binary, churn, and pre-destructive-phase case. Still **OPEN with the owner**:
dismissal refusal for a live, unparked `in_progress` row at the database layer,
and the harness VM pair question, including why the previous release is not
the starting point. Next step: resolve those two owner questions, then finish
steps 5-6 and run the paired harness proof.
