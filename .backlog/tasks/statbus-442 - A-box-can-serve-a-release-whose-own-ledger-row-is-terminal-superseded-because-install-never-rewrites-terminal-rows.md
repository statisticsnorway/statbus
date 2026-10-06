---
id: STATBUS-442
title: >-
  A box can serve a release whose own ledger row is terminal superseded,
  because install never rewrites terminal rows
status: In Progress
assignee: []
created_date: '2026-10-02 17:05'
labels:
  - upgrade
  - ledger
  - install
dependencies: []
references:
  - STATBUS-435
  - STATBUS-436
priority: medium
---

## Issue

After a successful version-pinned install of v2026.10.0-rc.12 onto a v2026.09.2 box, the box served rc.12 but the ledger row for rc.12 was `superseded`, not `completed`. Nothing in `public.upgrade` then says which release the box is running. `completeInstallUpgradeRow` (cli/cmd/install.go) upserts the installed row as `completed`, but its `ON CONFLICT` clause refuses to touch terminal states (`WHERE upgrade.state NOT IN ('completed','superseded','failed','rolled_back','skipped','dismissed')`). The `upgrade_block_terminal_resurrection` trigger enforces the same rule. So a row that was retired before the install stays retired, even though the install made that exact commit the serving version, and the step prints "already recorded in upgrade table (no change)".

## Evidence

The STATBUS-436 operator-path proof against rc.12 (2026-10-02 16:37–16:57 UTC, guest `…-30587`, log `tmp/436-operator-rc12.PASS.log` in `$JCODE_SCRATCH_DIR/436-run-rc12`) showed all of these:
- final checkout `7ec86ac2`
- resident daemon running `v2026.10.0-rc.12`
- all containers on `:7ec86ac2`
- the query `SELECT … WHERE commit_sha = '7ec86ac2…'` returning `2|v2026.10.0-rc.12|…|superseded|`

The guest was deleted at the end of the run, so the row's transition history (who wrote `superseded`, and when) was not captured.

Likely mechanism (from source, not observed): the guest follows `prerelease`, so the v2026.09.2 daemon discovered rc.12 as an `available` prerelease row (id 2). The harness then scheduled `v2026.09.3`. v2026.09.2's `upgrade_supersede_older` (migration 20260923084454) ranks tiers first (`u.release_status < _status`), so scheduling the `release`-tier v2026.09.3 superseded every `available` prerelease row, including the newer rc.12. STATBUS-435 (migration 20261001163000) removed that tier ranking, but only for code running after the floor. Rows already retired under the old rule stay retired.

## Why it matters

The ledger is how the admin UI, `./sb upgrade list`, the canary gate (`checkOneCanary` looks for a `completed` row at the candidate), retention, and supersession reason about "what this box runs". A box whose serving release has no `completed` row reads as never installed. If the box is Norway, the stable-promotion canary gate would not see a completed install. Demo (stable channel, no rc.12 row) is not exposed for this install. Any prerelease-channel box on v2026.09.2 or earlier that discovered a candidate before scheduling a stable release is exposed.

## Principled fix

When an install completes at commit X and makes it the serving version, the ledger must say X is completed. That needs a deliberate, logged transition out of `superseded` for **exactly the row being installed**, and only when that row was superseded by a ranking rule rather than by an operator's act. The resurrection trigger exists to keep terminal history honest, so the exception needs a recorded reason (e.g. `completed_via = 'install'`, or a state-log entry naming the install). An alternative is to record a fresh completed fact elsewhere. Pick one with an independent review. Do not weaken the trigger generally.

## Acceptance criteria

- [ ] #1 A pg_regress test reproduces it: v2026.09.2-era supersede rule retires a newer prerelease row, then the install completion at that commit leaves the box with no completed row for its serving version (RED on current master).
- [x] #2 After the fix, the same sequence ends with the serving commit's row `completed`, the transition is attributable in the state log, and `upgrade_block_terminal_resurrection` still refuses every other terminal-to-completed rewrite.
- [x] #3 The canary gate's view of Norway is unaffected for the normal path (pinned install of a candidate that has no prior terminal row).

## Implementation and evidence | October 6, 2026

Selected correction uses the existing audited `upgrade_schedule` route for exactly the successfully installed full SHA, only when the latest retained event proves ranking retirement and the row has no attempt/backup/park evidence. It synchronously records the installed SHA, log and ranking-event reference before the transition. Other terminal rows and the terminal-resurrection trigger are unchanged. Production correction is committed at `d61ba605fd985275faf80d453e99f4f014357612`.

- SQL `131_statbus_442_pinned_install_ranking_retirement` reproduces the actual legacy ranking rule and the pre-fix terminal-excluding upsert, then verifies the existing attributable scheduling/completion route and rejection of unrelated direct terminal writes. The golden deliberately records the pre-fix no-completed-row state. This is a passing SQL reproduction, not a claimed baseline pg_regress exit-1 result.
- The actual Go completion/install route was RED on the unchanged baseline and GREEN on the correction. Nine real-PostgreSQL `runInstall` controls include ranking retirement, direct operator retirement, absent/stale/cross-SHA history, failed install and normal candidate completion/canary observation.
- Independent review found a real row-wait race: a statement waited for the row lock but retained an older latest-event snapshot. The correction now locks the exact row in a separate statement, then reads eligibility/history with a fresh READ COMMITTED snapshot. The unchanged two-connection probe and actual waiting-install route are GREEN, preserving the newer operator retirement and emitting no rearm audit.
- The sole final local full gate at `d61ba605` passed build, vet, regular and livedb-tagged lint plus ordinary Go tests. All seven stored exits are zero. Prior lint/unit failures and the original independent BLOCK remain retained.
- Full 127-line independent Skunk MERGE at exact `8c985741fe485ee0fd07383c62dd2eb08fd84f9e` is recorded in `tmp/442-overnight-final-review.md`. The unchanged formerly failing two-connection race, nine actual-install modes, five audit/rollback and seven attempted-metadata controls passed independently. Sixteen unchanged 452 preservation cases passed after a private fixture password omission was corrected. The original timeout/exit-1 log remains retained, not relabelled green or dismissed as flaky.
- AC #2 and #3 are supported by real PostgreSQL/actual-install-route observations and unchanged terminal guards. AC #1's SQL reproduction is present, but its literal baseline pg_regress RED requirement is not claimed complete: baseline RED is the actual Go install/completion route, while SQL131's golden transparently records the before-fix state and audited remedy. New-source hosted CI and named-candidate shipped-image acceptance remain pending.

The deleted rc.12 guest's historical supersession cause remains unproven. These controlled reproductions do not retroactively establish that lost history or certify a released-image guest installation.
