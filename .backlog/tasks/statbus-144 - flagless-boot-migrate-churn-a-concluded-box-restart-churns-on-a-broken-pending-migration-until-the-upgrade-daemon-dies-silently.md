---
id: STATBUS-144
title: >-
  flagless-boot-migrate-churn: a concluded box restart-churns on a broken
  pending migration until the upgrade daemon dies silently
status: Done
assignee: []
created_date: '2026-07-07 02:57'
updated_date: '2026-07-12 22:08'
labels:
  - upgrade
  - recovery
  - product
  - install-recovery
dependencies: []
references:
  - cli/internal/upgrade/service.go
  - cli/internal/migrate/exit_codes.go
  - STATBUS-136
  - STATBUS-046
ordinal: 145000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: a box that has already concluded (upgrade row at a terminal state, no recovery flag) must never restart-churn on a broken pending migration — one loud report, then alive-idle. BENEFIT: the git-corrupt abort's natural aftermath stops silently killing the upgrade daemon (no discovery, no scheduled pickup, no backup ticker) on exactly the boxes that just had their worst day. STAGE: Stage 1 (install/upgrade robustness). COMPLEXITY: mechanic/arc-lane (scenario variant only) — the fix shipped 46f979a3a (comment #2); AC#1/#2 checked. What remains: AC#3, the abort-oracle-without-cleanup scenario variant proving the daemon stays alive-idle. DEPENDS ON: nothing.

FOUND live (abort-oracle scenario first pass, 2026-07-07, kept-VM autopsy by the architect — NRestarts observed at 7 and climbing, ~30s cadence): after a terminal (row=failed, flag removed), a FLAGLESS boot whose boot-migrate hits a deterministically failing pending migration EXITS the process — the deferred-recovery path requires a service-held flag, and there is none — so systemd restarts it every RestartSec=30s until StartLimit (10 per 600s; a 30s cadence trips it, unlike the original rune loop's 150s) kills the unit into a silent 'failed' unit state. Terminal outcome: the upgrade DAEMON dead with no siren and no park, while app/db keep serving.

REACHABLE IN REALITY as the natural sequel of every git-corrupt abort: the abort's defining feature is that the git restore FAILED, so the new version's migrations (including whichever broke the upgrade) REMAIN on disk with row=failed and no flag — every subsequent service boot then churns to StartLimit death. Violates the recovery design's own standard for deterministic failures (fail fast + actionable ONCE, stay alive — never loop) in the one window the ratified budget boundary deliberately excluded (flagless, post-terminal).

SEVERITY, honest and modest: the abort itself already sirened and instructed the operator; services keep serving; the loop kills only the upgrade daemon — but "churn 10 times then die silently" is not a designed terminal.

FIX SHAPE (architect): in the service's FLAGLESS boot-migrate failure handling, classify deterministic failures (the migrate exit-code contract's exit 20) → log loud ONCE + CONTINUE to the main loop alive-idle (the daemon has normal duties; the broken migration resurfaces actionably on any deliberate operation). Keep exit-and-restart only for the transient/unclassified case.

ORACLE: the abort-write-lands scenario run WITHOUT its cleanup step reproduces this exactly (its first pass did, by accident — the r-ledger evidence); preserve as a variant assertion once the fix lands.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A flagless boot whose boot-migrate fails DETERMINISTICALLY (exit 20) logs one loud actionable report and continues to the main loop alive-idle — no restart churn, no StartLimit death
- [x] #2 Transient/unclassified boot-migrate failures keep the exit-and-restart behavior
- [x] #3 The abort-aftermath state (row=failed, no flag, broken migration on disk) leaves the daemon alive and serving its normal loop, verified by a scenario variant
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-07 03:07
---
LIVE SEVERITY EVIDENCE (banked from the kept abort-oracle VM 65.108.158.151 before reaping, systemd 255, operator empirics 2026-07-07): the flagless churn was observed running to its terminal — NRestarts climbed ~+1 per 30s (7 at the architect's read, 9 at the operator's) until the unit sat in state 'failed' — i.e. the StartLimit death is not hypothetical, it is the observed end state of this bug on a real box. Counter arithmetic for the fix's gate/tests, confirmed on the same box: `systemctl reset-failed` zeroes NRestarts in BOTH unit states (failed 9→0, active 1→0), and the counter increments by exactly +1 per restart (0→1→2, timestamped, no skips). The abort-oracle scenario now deletes its synthetic migration promptly and stays a narrow 136 oracle; THIS ticket's future oracle is that same scenario WITHOUT the cleanup step, asserting the StartLimit death (pointer in the scenario header).
---

author: foreman
created: 2026-07-07 04:19
---
FIX SHIPPED 46f979a3a (2026-07-07), dual-reviewed (architect ship, both flags ruled; foreman first-hand). AC#1+AC#2 covered by unit tests (classification table + source-structure guard pinning no-return/no-markTerminal on the deterministic branch); AC#3 (scenario variant) is the next oracle unit. ARCHITECT RULINGS recorded: (1) BROAD SHAPE confirmed — continue on ANY flagless exit-20, not terminal-row-only: a flagless in_progress row with a deterministic pending migration is exactly what the flagless recovery routing handles (tri-state disposition reads Behind after boot-migrate → designed rollback); a terminal-only guard would re-create the churn one row-state to the left. Decisive autonomy argument for the schema-skew trade: a StartLimit-dead daemon can repair NOTHING — it cannot even receive the corrected version; an alive-degraded daemon IS the delivery channel for the fix. The 42703 residual is bounded and loud. (2) NO filename extraction from migrate's prose (text-as-classifier's cousin); the verbose tail names the file in practice, ./sb migrate up reproduces deterministically. SOMEDAY option noted: a structured filename side-channel in the migrate exit-code contract (data, not parsed prose) if a real operator is ever bitten.
---

author: foreman
created: 2026-07-11 20:20
---
STATUS SYNC (foreman, 2026-07-11): status corrected To Do → In Progress — the fix shipped 46f979a3a (comment #2's record stands). ACs #1/#2 now formally checked on the unit-test coverage recorded there (classification table + source-structure guard). OPEN: AC#3 only — the scenario variant (abort-oracle without its cleanup step, asserting the daemon stays alive-idle instead of the StartLimit death banked in comment #1). Queued as an arc-lane item behind the 154/wave-8 closure. Note for that variant's build: under the shipped 145 geometry the flagless boot-migrate is floor-bounded, so the broken-pending-migration inject must sit at or below the daemon floor to hit the boot path — confirm the inject site when building.
---

author: foreman
created: 2026-07-12 13:57
---
AC-3 SCENARIO BUILT + SHIPPED (e8cfb269a, 2026-07-12), architect SHIP with the break-construction explicitly credited: the base scenario's own proposed oracle (keep the far-future stall migration) was REFUTED against the STATBUS-145 floor geometry before building — boot-migrate's --to DaemonSchemaFloor never attempts a file above the floor, so that construction would prove nothing — and 4-rollback-abort-churn-then-alive-idle.sh instead injects a run-time-computed, at-or-below-floor, validly named, deterministically failing migration (floor read from the checked-out daemon_floor.go; version computed between the top two real migrations; loud refuse on collision), with the pre-apply capped so the pending state is genuine. Asserts the full 144 contract: unit active through a 90s watch, NRestarts ≤ 1, row stays failed (no false self-heal), nothing recorded on any boot, the loud-once deterministic-failure banner, services serving throughout. The variant joins the 4-rollback-abort INTERIM construction family (reciprocal headers name both members; one construction, three oracles) and retires with it when the restore-broke re-attempt arc goes green. AC-3 checks on the VM run — batched for tomorrow.
---

author: tester (relayed by foreman)
created: 2026-07-12 22:08
---
AC#3 RUN-PROVEN GREEN (tester, batch-3 VM run, 2026-07-12 night; log tmp/night-batch3-churn-retry2.log). The abort-aftermath scenario variant (4-rollback-abort-churn-then-alive-idle): row='failed' with ROLLBACK_FAILED_GIT_CORRUPT, upgrade flag absent (the ABORT's own terminal write landed, STATBUS-136), broken migration floor-bound on disk — and the daemon stayed ALIVE-IDLE: NRestarts=1 ≤ bound 1 (no churn), unit active through the full 90s watch, services serving, row correctly NOT self-healed to completed, neither migration applied, exactly one loud diagnostic banner, demo-data counts intact (statistical_unit=126, legal_unit=23, establishment=50). Never the pre-fix StartLimit death. A first attempt earlier tonight was a false RED from a foreman-caused binary/checkout race on the shared tree (freshness check refused, as designed) — re-run clean.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
A concluded box with a broken pending migration no longer restart-churns itself to death. Shipped across this ticket's arc: deterministic boot-migrate failures (exit 20) log one loud actionable report and leave the daemon alive-idle in its main loop instead of exit-restart churn into StartLimit death; transient failures keep exit-and-restart; and the abort-aftermath state (row='failed', no flag, floor-bound broken migration on disk) is run-proven to leave the daemon alive and serving. Final proof: batch-3 VM scenario green 2026-07-12 — NRestarts=1, unit active throughout, one diagnostic banner, no self-heal, data intact (log: tmp/night-batch3-churn-retry2.log).
<!-- SECTION:FINAL_SUMMARY:END -->
