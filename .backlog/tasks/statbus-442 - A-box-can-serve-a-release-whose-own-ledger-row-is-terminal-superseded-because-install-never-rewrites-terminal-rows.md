---
id: STATBUS-442
title: >-
  A box can serve a release whose own ledger row is terminal superseded,
  because install never rewrites terminal rows
status: To Do
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

## Principled fix (to decide)

When an install completes at commit X and makes it the serving version, the ledger must say X is completed. That needs a deliberate, logged transition out of `superseded` for **exactly the row being installed**, and only when that row was superseded by a ranking rule rather than by an operator's act. The resurrection trigger exists to keep terminal history honest, so the exception needs a recorded reason (e.g. `completed_via = 'install'`, or a state-log entry naming the install). An alternative is to record a fresh completed fact elsewhere. Pick one with an independent review. Do not weaken the trigger generally.

## Acceptance criteria

- [ ] #1 A pg_regress test reproduces it: v2026.09.2-era supersede rule retires a newer prerelease row, then the install completion at that commit leaves the box with no completed row for its serving version (RED on current master).
- [ ] #2 After the fix, the same sequence ends with the serving commit's row `completed`, the transition is attributable in the state log, and `upgrade_block_terminal_resurrection` still refuses every other terminal-to-completed rewrite.
- [ ] #3 The canary gate's view of Norway is unaffected for the normal path (pinned install of a candidate that has no prior terminal row).
