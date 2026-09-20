# rc.20 upgrade-arc live triage

Run: `35502183500`
Candidate: `v2026.09.1-rc.20`
Candidate commit: `3d393d72548516bf74bcf4d559adb5917a9145ea`
Evidence directory: `tmp/rc20-arc-logs/`

## Scope and comparison baselines

This file is updated incrementally while the run is live. Each failure is classified from its completed per-job log, downloaded through `GET /repos/statisticsnorway/statbus/actions/jobs/<job-id>/logs`.

Comparison baselines:

- rc.18 profile defect (`tmp/rc18-arc-triage.md:9-65`): all affected jobs stopped before their scenario-specific path with `FAILED: Could not record immutable source image identities before target pull: source serving era cannot be established: restored source compose config has no image for app`.
- rc.17 five failures (`tmp/rc17-rca.md:100-203`): three product regressions (`postswap-stopped-proxy-recovery`, `restore-broke-reattempt`, `rollback-pair-terminal`) and two schema-floor harness drifts (`rollback-schema-floor-adoption`, `rollback-schema-floor-failure`).

## Live snapshot 1

Captured from `gh run view 35502183500 --json jobs` at approximately `2026-09-20T10:20Z`:

- Scenario jobs: 7 success, 6 failure, 3 in progress, 22 queued.
- Failed: `boot-migrate-churn-alive-idle`, `c-rollback-resurrection`, `deploy-status-proof`, `after-commit-before-recorded-kill`, `failing`, `postswap-between-migrations-kill`.
- In progress: `postswap-health-park`, `postswap-after-commit-kill`, `postswap-converged-selfheal`.

The six completed failed-job logs are being acquired and analyzed below.

## Initial six failures: evidence and classification

### Shared product defect affecting five ordinary rollback scenarios

Five failures have the same capture-to-loss sequence:

1. The daemon reports `Recording immutable source image identities ... ok` before target pull.
2. The post-swap continuation runs.
3. Rollback restores the snapshot and source tree.
4. Source service convergence then refuses with `source serving era cannot be established: recovery marker has no pre-upgrade source image identities`.
5. The row lands `failed` with `ROLLBACK INCOMPLETE` instead of `rolled_back`.

The marker loss is explained by the rc.20 code itself. `captureSourceServingImageIdentities` stores `flag.SourceServingImages` through `mutateHeldFlag` (`cli/internal/upgrade/service.go:8316-8337`). Later, `resumeNewSb` constructs a fresh `UpgradeFlag` literal and passes it to `acquireFlock`, which atomically replaces the marker, but that literal copies ID, commit, tags, trigger, recreate, backup path, and death-step state while omitting `SourceServingImages` (`cli/internal/upgrade/service.go:10480-10499`). The replacement therefore discards the identities that capture just persisted. `sourceServingExpectedImages` later fails closed when the map is absent (`cli/internal/upgrade/service.go:8345-8356`).

**Broken invariant:** every recovery-marker rewrite after immutable source identity capture must preserve `SourceServingImages` until the upgrade reaches a truthful successful or rolled-back terminal. The resuming-phase rewrite violates that invariant.

This is not rc.18's profile failure. In rc.18, capture aborted before target pull with `restored source compose config has no image for app`. Here capture succeeds, the scenario-specific migration/kill/failure is reached, and rollback fails much later because the successfully captured identities were erased.

It is also not any of rc.17's five final symptoms. The three rc.17 product failures concerned unconditional held-closed verification or failure to reconverge source services. The rc.20 five below reach explicit source service convergence, but its new immutable-era proof has been removed from the marker. The two rc.17 schema-floor harness drifts have different assertions and terminals.

| Scenario | Job | Failing assertion | Daemon terminal evidence | Classification |
|---|---:|---|---|---|
| `after-commit-before-recorded-kill` | `106056324091` | Log `3991`: row did not reach `rolled_back` in 600s; log `3998`: harness failure at arc line 175 | Capture succeeds at log `4222`; recovery boot sees `new-sb-swapped` at `4289`; source startup refuses missing identities at `4346`; row records rollback incomplete at `4353` | **Product bug**, shared marker-preservation invariant |
| `c-rollback-resurrection` | `106056324054` | Log `3875`: C reached `failed`, expected `rolled_back` | C capture succeeds at `4162`; recovery boot sees `new-sb-swapped` at `4223`; source startup refuses missing identities at `4288`; row records rollback incomplete at `4295` | **Product bug**, shared marker-preservation invariant |
| `deploy-status-proof` | `106056324057` | Log `4150`: B reached `failed`, expected `rolled_back` | Capture succeeds at `4321`; recovery boot sees `new-sb-swapped` at `4388`; source startup refuses missing identities at `4453`; row records rollback incomplete at `4459` | **Product bug**, shared marker-preservation invariant |
| `failing` | `106056324095` | Log `3969`: B reached `failed`, expected `rolled_back` | Capture succeeds at `4174`; recovery boot sees `new-sb-swapped` at `4241`; source startup refuses missing identities at `4306`; row records rollback incomplete at `4313` | **Product bug**, shared marker-preservation invariant |
| `postswap-between-migrations-kill` | `106056324121` | Log `4201`: unexpected terminal state `failed` | Capture succeeds at `4056`; the injected kill and exact V1-recorded/V2-pending gap are both proved at `4196-4198`; source startup refuses missing identities at `4185`; row records rollback incomplete at `4191` | **Product bug**, shared marker-preservation invariant |

### `boot-migrate-churn-alive-idle`: related terminal text, distinct carrier-loss path

Job `106056324041` deliberately destroys the recovery marker after the first mid-rollback kill:

- Initial immutable identity capture succeeds at log `3985`.
- The mid-rollback crash is proved at `4122`.
- The harness truncates the flag to invalid JSON at `4131-4132`.
- The next daemon fires `FLAG_CORRUPT` and removes the marker at `4136-4137`.
- The unit becomes active and its restart count remains bounded at `4144-4148`.
- Assertion D then fails at `4154`; the diagnostic query itself reports `service "db" is not running` at `4157` and exits 1 at `4158`.
- The daemon's terminal source-start error is again missing pre-upgrade identities at `4404`.

This scenario cannot be attributed specifically to `resumeNewSb`'s omission because the harness intentionally truncates and causes removal of the entire marker. Its distinct product invariant is: **corrupt-marker recovery must leave an operable, truthfully contained box even when the only marker copy of immutable source identities is lost**. The current flagless recovery creates/uses recovery intent without an independent source-identity carrier, then cannot restart the source stack and leaves the DB down. Classification: **product bug**, distinct persistence/recovery-carrier gap exposed by the new immutable source-era requirement, not harness drift and not infrastructure.

### `c-rollback-resurrection` held-closed message: expected fail-closed refusal, not a defect

The B health-failure park reaches the expected parked state, and its appended park reason says the held-closed era verifier found `app`, `rest`, and `worker` still running (`c-rollback-resurrection.log:3842`). Code and scenario ordering show this is **the verifier correctly refusing**, not an invariant violation:

1. `applyNewSbUpgrading` deliberately starts the complete target serving tier at step 11 (`docker compose up -d app worker proxy rest`) before step 12 performs the functional health gate (`service.go:9227-9298`). The deterministic health failure therefore occurs while target clients legitimately remain live.
2. `parkForDeterministicFailure` first persists the park, then calls `parkServiceRecovery` (`service.go:7885-7905`). The helper's explicit contract and structural test require that it only starts services and never stops anything (`service.go:7910-7917`; `park_service_recovery_test.go:59-88`). It must not destructively quiesce a serving tier merely to attempt an optional source retreat after the truthful park has landed.
3. A source retreat would compare schema eras and, on permit, restore source application containers. That transition requires clients held closed. Accordingly `parkEraVerdict` is intentionally one of exactly two callers of `StartDatabaseRouteServingMustBeStopped`; `TestRecoveryRouteCallersSplitByContract` pins the 2/2 caller split and states that the held-closed route belongs to the park-era schema comparison (`recovery_route_callers_test.go:9-49`). Replacing this caller with `StartDatabaseRouteServingMayRun` would weaken the rc.17 contract and permit the mixed-era transition the verifier exists to prevent.
4. `StartDatabaseRouteServingMustBeStopped` checks the serving tier before opening the database route and returns `RecoveryClientsLiveError` when any client is live (`exec.go:1412-1446,1487-1531`). The log's `still running` text is evidence that this check stopped the source-era verdict before a DB-era read or source restore, not evidence that code proceeded despite a violated precondition.
5. `parkServiceRecovery` then appends the refusal narrative and returns without stopping or starting the source tier (`service.go:7978-7985`). The same reason is correctly retained through recovery and displacement (`c-rollback-resurrection.log:4120-4124,4152-4153`) as audit history. The scenario itself requires broken B to remain the observed running version until C displaces it (`c-rollback-resurrection-arc.sh:5-32`).

Conclusion: this is case (a), a truthful held-closed refusal on a post-swap health park. The park reason text is correct. No product-code or caller-split change is warranted.

## Current root-cause verdict after snapshot 1

- Five of six failed jobs share one direct regression from rc.20's source-identity feature: the post-swap resuming marker rewrite drops `SourceServingImages`.
- The sixth, `boot-migrate-churn-alive-idle`, exposes a distinct loss-of-carrier problem after deliberate corrupt-marker removal.
- `c-rollback-resurrection`'s earlier held-closed message is a correct fail-closed refusal: the post-swap health gate runs after target clients start, and the optional source-retreat helper is starts-only, so the era verifier must refuse rather than weaken its held-closed contract.
- No initial failure matches rc.18's `no image for app` pre-pull profile defect.
- No initial failure is infrastructure. No initial failure is classified as harness drift from the available logs.

## Live snapshot 2

Captured at approximately `2026-09-20T10:23Z`:

- Scenario jobs: 5 success, 7 failure, 3 in progress, 20 queued.
- Newly completed success: `postswap-converged-selfheal`.
- Newly completed failure: `postswap-after-commit-kill` (`106056324156`).
- In progress: `postswap-health-park`, `postswap-mid-migration-kill`, `postswap-mid-tx-kill`.

### `postswap-after-commit-kill`

Classification: **product bug, the same marker-preservation invariant as the five ordinary rollback failures above**.

- Failing assertion: log `3789` says the row did not reach `rolled_back` in 600 seconds and remained `failed`; log `3796` identifies the harness failure at arc line 175.
- Capture succeeds at log `3992`.
- Recovery first reads `new-sb-swapped` at `4060`, then a later boot reads `new-sb-upgrading` at `4110`, proving the resuming-phase rewrite occurred.
- Source startup refuses because the marker has no pre-upgrade identities at `4143`.
- The row records `ROLLBACK INCOMPLETE` at `4150`.

This job directly strengthens the code-level diagnosis: the identities exist before the first handoff, then are absent after the `new-sb-upgrading` rewrite whose fresh `UpgradeFlag` literal omits `SourceServingImages`.

## Live status snapshot 3

Polled `2026-09-20T10:24:35Z`: counts `{"success":5,"failure":7,"in_progress":3,"queued":20}`.

- Failed: `boot-migrate-churn-alive-idle, c-rollback-resurrection, deploy-status-proof, after-commit-before-recorded-kill, failing, postswap-between-migrations-kill, postswap-after-commit-kill`
- In progress: `postswap-health-park, postswap-mid-migration-kill, postswap-mid-tx-kill`
- Queued: `postswap-migration-timeout, postswap-migration-ceiling, postswap-migration-oom, postswap-rollback-restore-watchdog, postswap-severed-proxy-refusal, postswap-stopped-proxy-recovery, postswap-watchdog-reconnect, preswap-backup-kill, preswap-binary-swap-kill, preswap-checkout-kill, preswap-fetch-returned-error, restore-broke-reattempt, rollback-kill, rollback-pair-terminal, rollback-schema-floor-failure, rollback-schema-floor-adoption, transient-db-backoff, un-park-to-completion, worker-wedge-mid-derive, working`

This is a status-only checkpoint. Newly failed completed jobs require the per-job log analysis appended below.

## Live status snapshot 4

Polled `2026-09-20T10:31:38Z`: counts `{"success":6,"failure":7,"in_progress":3,"queued":19}`.

- Failed: `boot-migrate-churn-alive-idle, c-rollback-resurrection, deploy-status-proof, after-commit-before-recorded-kill, failing, postswap-between-migrations-kill, postswap-after-commit-kill`
- In progress: `postswap-health-park, postswap-mid-tx-kill, postswap-migration-ceiling`
- Queued: `postswap-migration-timeout, postswap-migration-oom, postswap-rollback-restore-watchdog, postswap-severed-proxy-refusal, postswap-stopped-proxy-recovery, postswap-watchdog-reconnect, preswap-backup-kill, preswap-binary-swap-kill, preswap-checkout-kill, preswap-fetch-returned-error, restore-broke-reattempt, rollback-kill, rollback-pair-terminal, rollback-schema-floor-failure, rollback-schema-floor-adoption, transient-db-backoff, un-park-to-completion, worker-wedge-mid-derive, working`

This is a status-only checkpoint. Newly failed completed jobs require the per-job log analysis appended below.

## Live status snapshot 5

Polled `2026-09-20T10:34:43Z`: counts `{"success":8,"failure":7,"in_progress":2,"queued":18}`.

- Failed: `boot-migrate-churn-alive-idle, c-rollback-resurrection, deploy-status-proof, after-commit-before-recorded-kill, failing, postswap-between-migrations-kill, postswap-after-commit-kill`
- In progress: `postswap-migration-ceiling, postswap-migration-oom`
- Queued: `postswap-migration-timeout, postswap-rollback-restore-watchdog, postswap-severed-proxy-refusal, postswap-stopped-proxy-recovery, postswap-watchdog-reconnect, preswap-backup-kill, preswap-binary-swap-kill, preswap-checkout-kill, preswap-fetch-returned-error, restore-broke-reattempt, rollback-kill, rollback-pair-terminal, rollback-schema-floor-failure, rollback-schema-floor-adoption, transient-db-backoff, un-park-to-completion, worker-wedge-mid-derive, working`

This is a status-only checkpoint. Newly failed completed jobs require the per-job log analysis appended below.

## Live status snapshot 6

Polled `2026-09-20T10:35:45Z`: counts `{"success":8,"failure":7,"in_progress":3,"queued":17}`.

- Failed: `boot-migrate-churn-alive-idle, c-rollback-resurrection, deploy-status-proof, after-commit-before-recorded-kill, failing, postswap-between-migrations-kill, postswap-after-commit-kill`
- In progress: `postswap-migration-timeout, postswap-migration-ceiling, postswap-migration-oom`
- Queued: `postswap-rollback-restore-watchdog, postswap-severed-proxy-refusal, postswap-stopped-proxy-recovery, postswap-watchdog-reconnect, preswap-backup-kill, preswap-binary-swap-kill, preswap-checkout-kill, preswap-fetch-returned-error, restore-broke-reattempt, rollback-kill, rollback-pair-terminal, rollback-schema-floor-failure, rollback-schema-floor-adoption, transient-db-backoff, un-park-to-completion, worker-wedge-mid-derive, working`

This is a status-only checkpoint. Newly failed completed jobs require the per-job log analysis appended below.

## Live status snapshot 7

Polled `2026-09-20T10:43:17Z`: counts `{"success":8,"failure":8,"in_progress":3,"queued":16}`.

- Failed: `boot-migrate-churn-alive-idle, c-rollback-resurrection, deploy-status-proof, after-commit-before-recorded-kill, failing, postswap-between-migrations-kill, postswap-after-commit-kill, postswap-migration-ceiling`
- In progress: `postswap-migration-timeout, postswap-migration-oom, postswap-rollback-restore-watchdog`
- Queued: `postswap-severed-proxy-refusal, postswap-stopped-proxy-recovery, postswap-watchdog-reconnect, preswap-backup-kill, preswap-binary-swap-kill, preswap-checkout-kill, preswap-fetch-returned-error, restore-broke-reattempt, rollback-kill, rollback-pair-terminal, rollback-schema-floor-failure, rollback-schema-floor-adoption, transient-db-backoff, un-park-to-completion, worker-wedge-mid-derive, working`

This is a status-only checkpoint. Newly failed completed jobs require the per-job log analysis appended below.

### Snapshot 7 failure analysis: `postswap-migration-ceiling`

Job `106056324663` is **the same product marker-preservation bug**, not a migration-ceiling defect and not harness drift.

- The harness observes B in `failed` and expects `rolled_back` at log `4116-4117`.
- Immutable source identity capture succeeds at `4523`.
- The intended scenario behavior is reached: the migration exceeds its 20-second ceiling and is killed at `4469`; the daemon cancels the timed-out backend at `4470`, confirms the DB is behind at `4471`, and begins rollback at `4472-4473`.
- Snapshot restore, schema-floor replay, source checkout, and source config regeneration all succeed (`4483-4496`).
- Source startup then refuses missing marker identities at `4497`.
- The row records `ROLLBACK INCOMPLETE` at `4504`.

Therefore the ceiling mechanism itself worked. The rollback terminal failed only after the post-swap marker rewrite erased `SourceServingImages`.

## Live status snapshot 8

Polled `2026-09-20T10:46:23Z`: counts `{"success":8,"failure":9,"in_progress":3,"queued":15}`.

- Failed: `boot-migrate-churn-alive-idle, c-rollback-resurrection, deploy-status-proof, after-commit-before-recorded-kill, failing, postswap-between-migrations-kill, postswap-after-commit-kill, postswap-migration-ceiling, postswap-migration-oom`
- In progress: `postswap-migration-timeout, postswap-rollback-restore-watchdog, postswap-severed-proxy-refusal`
- Queued: `postswap-stopped-proxy-recovery, postswap-watchdog-reconnect, preswap-backup-kill, preswap-binary-swap-kill, preswap-checkout-kill, preswap-fetch-returned-error, restore-broke-reattempt, rollback-kill, rollback-pair-terminal, rollback-schema-floor-failure, rollback-schema-floor-adoption, transient-db-backoff, un-park-to-completion, worker-wedge-mid-derive, working`

This is a status-only checkpoint. Newly failed completed jobs require the per-job log analysis appended below.

## Live status snapshot 9

Polled `2026-09-20T10:48:26Z`: counts `{"success":9,"failure":9,"in_progress":3,"queued":14}`.

- Failed: `boot-migrate-churn-alive-idle, c-rollback-resurrection, deploy-status-proof, after-commit-before-recorded-kill, failing, postswap-between-migrations-kill, postswap-after-commit-kill, postswap-migration-ceiling, postswap-migration-oom`
- In progress: `postswap-rollback-restore-watchdog, postswap-severed-proxy-refusal, postswap-stopped-proxy-recovery`
- Queued: `postswap-watchdog-reconnect, preswap-backup-kill, preswap-binary-swap-kill, preswap-checkout-kill, preswap-fetch-returned-error, restore-broke-reattempt, rollback-kill, rollback-pair-terminal, rollback-schema-floor-failure, rollback-schema-floor-adoption, transient-db-backoff, un-park-to-completion, worker-wedge-mid-derive, working`

This is a status-only checkpoint. Newly failed completed jobs require the per-job log analysis appended below.

## Live status snapshot 10

Polled `2026-09-20T10:55:03Z`: counts `{"success":10,"failure":9,"in_progress":3,"queued":13}`.

- Failed: `boot-migrate-churn-alive-idle, c-rollback-resurrection, deploy-status-proof, after-commit-before-recorded-kill, failing, postswap-between-migrations-kill, postswap-after-commit-kill, postswap-migration-ceiling, postswap-migration-oom`
- In progress: `postswap-rollback-restore-watchdog, postswap-stopped-proxy-recovery, postswap-watchdog-reconnect`
- Queued: `preswap-backup-kill, preswap-binary-swap-kill, preswap-checkout-kill, preswap-fetch-returned-error, restore-broke-reattempt, rollback-kill, rollback-pair-terminal, rollback-schema-floor-failure, rollback-schema-floor-adoption, transient-db-backoff, un-park-to-completion, worker-wedge-mid-derive, working`

This is a status-only checkpoint. Newly failed completed jobs require the per-job log analysis appended below.

### Snapshot 8 failure analysis: `postswap-migration-oom`

Job `106056324678` is **the same product marker-preservation bug after the intended OOM path**.

- The harness observes B in `failed` and expects `rolled_back` at log `4030-4033`.
- The migration subprocess exits 137 and the DB container is identified as SIGKILLed during migration at `4333-4338`.
- The next recovery boot reads phase `new-sb-upgrading` at `4358`, confirms the DB is behind at `4365`, and starts rollback at `4366-4367`.
- Snapshot restore, schema-floor replay, source checkout, and source config regeneration succeed at `4377-4390`.
- Source startup then refuses missing identities at `4391`.

The OOM detection/recovery direction worked. The terminal fails because the resuming-phase marker replacement lost `SourceServingImages`, so this is product, not infra or harness drift.

## Live status snapshot 11

Polled `2026-09-20T10:57:59Z`: counts `{"success":11,"failure":9,"in_progress":3,"queued":12}`.

- Failed: `boot-migrate-churn-alive-idle, c-rollback-resurrection, deploy-status-proof, after-commit-before-recorded-kill, failing, postswap-between-migrations-kill, postswap-after-commit-kill, postswap-migration-ceiling, postswap-migration-oom`
- In progress: `postswap-rollback-restore-watchdog, postswap-watchdog-reconnect, preswap-backup-kill`
- Queued: `preswap-binary-swap-kill, preswap-checkout-kill, preswap-fetch-returned-error, restore-broke-reattempt, rollback-kill, rollback-pair-terminal, rollback-schema-floor-failure, rollback-schema-floor-adoption, transient-db-backoff, un-park-to-completion, worker-wedge-mid-derive, working`

This is a status-only checkpoint. Newly failed completed jobs require the per-job log analysis appended below.

## Live status snapshot 12

Polled `2026-09-20T11:00:03Z`: counts `{"success":11,"failure":10,"in_progress":3,"queued":11}`.

- Failed: `boot-migrate-churn-alive-idle, c-rollback-resurrection, deploy-status-proof, after-commit-before-recorded-kill, failing, postswap-between-migrations-kill, postswap-after-commit-kill, postswap-migration-ceiling, postswap-migration-oom, postswap-rollback-restore-watchdog`
- In progress: `postswap-watchdog-reconnect, preswap-backup-kill, preswap-binary-swap-kill`
- Queued: `preswap-checkout-kill, preswap-fetch-returned-error, restore-broke-reattempt, rollback-kill, rollback-pair-terminal, rollback-schema-floor-failure, rollback-schema-floor-adoption, transient-db-backoff, un-park-to-completion, worker-wedge-mid-derive, working`

This is a status-only checkpoint. Newly failed completed jobs require the per-job log analysis appended below.

## Live status snapshot 13

Polled `2026-09-20T11:07:22Z`: counts `{"success":12,"failure":10,"in_progress":2,"queued":11}`.

- Failed: `boot-migrate-churn-alive-idle, c-rollback-resurrection, deploy-status-proof, after-commit-before-recorded-kill, failing, postswap-between-migrations-kill, postswap-after-commit-kill, postswap-migration-ceiling, postswap-migration-oom, postswap-rollback-restore-watchdog`
- In progress: `preswap-backup-kill, preswap-binary-swap-kill`
- Queued: `preswap-checkout-kill, preswap-fetch-returned-error, restore-broke-reattempt, rollback-kill, rollback-pair-terminal, rollback-schema-floor-failure, rollback-schema-floor-adoption, transient-db-backoff, un-park-to-completion, worker-wedge-mid-derive, working`

This is a status-only checkpoint. Newly failed completed jobs require the per-job log analysis appended below.

### Snapshot 12 failure analysis: `postswap-rollback-restore-watchdog`

Job `106056324698` is **the same product marker-preservation bug after the intended watchdog-cover behavior succeeds**.

- The harness proves the rollback restore remains alive and parked for 240 seconds, with `NRestarts` frozen at 1 and zero systemd watchdog kills, at log `4015-4026`.
- After releasing the deliberate stall, the row reaches `failed` instead of the required `rolled_back` terminal at `4028-4030`.
- Immutable source identity capture succeeded before the handoff at `4273-4275`.
- The new binary resumes from `new-sb-swapped` at `4341`, reaches the deliberate migration failure at `4369-4379`, confirms the database is behind, and starts rollback at `4380-4382`.
- The injected restore stall is reached at `4392-4393`; after release, restore, schema-floor replay, source checkout, and source config regeneration succeed at `4394-4406`.
- Source startup then refuses `recovery marker has no pre-upgrade source image identities` at `4407`, and the row records `failed-rollback-incomplete` at `4414`.

The watchdog cover itself passed its explicit assertions. The terminal failure occurs only when rollback consumes the post-handoff marker whose `SourceServingImages` were erased. Classification: **product**, shared marker-rewrite invariant, not watchdog harness drift and not infrastructure.

## Live status snapshot 14

Polled `2026-09-20T11:08:24Z`: counts `{"success":12,"failure":10,"in_progress":3,"queued":10}`.

- Failed: `boot-migrate-churn-alive-idle, c-rollback-resurrection, deploy-status-proof, after-commit-before-recorded-kill, failing, postswap-between-migrations-kill, postswap-after-commit-kill, postswap-migration-ceiling, postswap-migration-oom, postswap-rollback-restore-watchdog`
- In progress: `preswap-backup-kill, preswap-binary-swap-kill, preswap-checkout-kill`
- Queued: `preswap-fetch-returned-error, restore-broke-reattempt, rollback-kill, rollback-pair-terminal, rollback-schema-floor-failure, rollback-schema-floor-adoption, transient-db-backoff, un-park-to-completion, worker-wedge-mid-derive, working`

This is a status-only checkpoint. Newly failed completed jobs require the per-job log analysis appended below.

## Live status snapshot 15

Polled `2026-09-20T11:09:26Z`: counts `{"success":13,"failure":10,"in_progress":3,"queued":9}`.

- Failed: `boot-migrate-churn-alive-idle, c-rollback-resurrection, deploy-status-proof, after-commit-before-recorded-kill, failing, postswap-between-migrations-kill, postswap-after-commit-kill, postswap-migration-ceiling, postswap-migration-oom, postswap-rollback-restore-watchdog`
- In progress: `preswap-binary-swap-kill, preswap-checkout-kill, preswap-fetch-returned-error`
- Queued: `restore-broke-reattempt, rollback-kill, rollback-pair-terminal, rollback-schema-floor-failure, rollback-schema-floor-adoption, transient-db-backoff, un-park-to-completion, worker-wedge-mid-derive, working`

This is a status-only checkpoint. Newly failed completed jobs require the per-job log analysis appended below.

## Live status snapshot 16

Polled `2026-09-20T11:11:30Z`: counts `{"success":14,"failure":10,"in_progress":3,"queued":8}`.

- Failed: `boot-migrate-churn-alive-idle, c-rollback-resurrection, deploy-status-proof, after-commit-before-recorded-kill, failing, postswap-between-migrations-kill, postswap-after-commit-kill, postswap-migration-ceiling, postswap-migration-oom, postswap-rollback-restore-watchdog`
- In progress: `preswap-checkout-kill, preswap-fetch-returned-error, restore-broke-reattempt`
- Queued: `rollback-kill, rollback-pair-terminal, rollback-schema-floor-failure, rollback-schema-floor-adoption, transient-db-backoff, un-park-to-completion, worker-wedge-mid-derive, working`

This is a status-only checkpoint. Newly failed completed jobs require the per-job log analysis appended below.

## Live status snapshot 17

Polled `2026-09-20T11:18:52Z`: counts `{"success":15,"failure":10,"in_progress":3,"queued":7}`.

- Failed: `boot-migrate-churn-alive-idle, c-rollback-resurrection, deploy-status-proof, after-commit-before-recorded-kill, failing, postswap-between-migrations-kill, postswap-after-commit-kill, postswap-migration-ceiling, postswap-migration-oom, postswap-rollback-restore-watchdog`
- In progress: `preswap-fetch-returned-error, restore-broke-reattempt, rollback-kill`
- Queued: `rollback-pair-terminal, rollback-schema-floor-failure, rollback-schema-floor-adoption, transient-db-backoff, un-park-to-completion, worker-wedge-mid-derive, working`

This is a status-only checkpoint. Newly failed completed jobs require the per-job log analysis appended below.
