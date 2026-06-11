---
id: STATBUS-012
title: >-
  Latent product gap: boot-migrate-up emits no WATCHDOG=1 (large-DB boot-migrate
  >120s → watchdog-killed)
status: In Progress
assignee:
  - '@architect'
created_date: '2026-06-07 23:57'
updated_date: '2026-06-11 11:50'
labels:
  - upgrade
  - recovery
  - product
dependencies: []
references:
  - cli/internal/upgrade/service.go
  - ops/statbus-upgrade.service
  - >-
    .backlog/docs/doc-005 -
    STATBUS-012-—-boot-migrate-watchdog-gap-verdict-severity-RED-reproducer-fix-design.md
documentation:
  - >-
    doc-005 -
    STATBUS-012-—-boot-migrate-watchdog-gap-verdict-severity-RED-reproducer-fix-design.md
priority: high
ordinal: 12000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Every upgrade's migrations run at the WRONG site: after the binary-swap restart, boot-migrate (cli/internal/upgrade/service.go:1644) consumes the entire migration delta with NO watchdog heartbeat — systemd kills the service 120s in (WatchdogSec=120, ops/statbus-upgrade.service). Any single migration >~120s on a large DB (Norway 32GB) = indefinite kill-restart loop (start-limit never trips: ~160s cycle → 3.75 starts/600s < 5). The protected 30-min applyPostSwap migrate (service.go:3949-3953) never gets the work — boot-migrate always runs first. Same wedge shape as the rune 40h loop (017 fixed the TimeoutStartSec edition; this is the WatchdogSec edition). Also: boot-migrate's timeout is 5min (vs 30min at the protected site), and the inline `./sb install` twin (cli/cmd/install_upgrade.go:198) has NO timeout at all.

THE FIX (King-accepted design, 2026-06-11): (1) wrap boot-migrate with the existing always-ping watchdog ticker (runGatedWatchdogTicker with nil progress — same primitive the post-swap migrate uses); (2) raise its timeout 5→30 min as ONE shared constant with the protected site; (3) bound the inline twin at 30 min; (4) repair the two comments that falsely claim this protection exists (service.go:1637-1643, unit file :83-104).

THE PROOF: the existing watchdog scenario 3-postswap-migration-timeout is VACUOUS (dispatches inline → no systemd → no watchdog in its flow). Rewrite it to SERVICE dispatch → run → expect watchdog kill (RED) → land fix → rerun → GREEN. Same RED→GREEN VM protocol as 017.

KING DECISIONS: this task GATES the RC cut (no RC until fixed + VM-proven). Architect (Fable) executes end-to-end himself; engineer adversarially reviews the diff; King sees the product diff before it lands. Deep reference: doc-005 (full refutation table, severity model, design rationale).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Gap confirmed: boot-migrate runs with zero WATCHDOG=1 sources and carries the full migration delta on every upgrade (refutation table in doc-005)
- [ ] #2 RED observed on a real VM: rewritten service-dispatch slow-migration scenario shows the watchdog kill loop on current code
- [ ] #3 Product fix landed: boot-migrate under the always-ping ticker + shared 30-min timeout; inline ./sb install boot-migrate bounded at 30 min; both drifted comments repaired
- [ ] #4 Engineer adversarial review of the diff passed; King ratified before push
- [ ] #5 GREEN proven on a real VM: same scenario, zero watchdog restarts from post-stall baseline, upgrade completes — RED→GREEN pair recorded with run IDs
- [ ] #6 Follow-up audit task filed: recoveryRollback/restoreDatabase startup path checked for the same missing-heartbeat gap
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Rewrite test/install-recovery/scenarios/3-postswap-migration-timeout.sh to SERVICE dispatch: systemd user drop-in carrying the two inject env vars (STATBUS_INJECT_AT=migration-slower-than-systemd-unit-timeout + STALL release file), daemon-reload, schedule upgrade row + NOTIFY wake (watchdog-reconnect pattern), keep the synthetic 2099 stall-target migration. Baseline NRestarts AFTER stall detected (excludes the one legit exit-42 restart); assert delta==0 + Result≠watchdog + existing terminal/data/flag checks. This rewrite also repairs the suite's vacuous Race-B net.
2. Run on Hetzner VM → observe RED (expected: SIGABRT at ~READY+120s, NRestarts delta ≥1). If NOT red, the model is wrong — stop, re-question.
3. Implement the product fix (service.go:1644 ticker wrap + shared 30-min const with :3952 + install_upgrade.go:198 bound + comment repairs). Add a source-order unit test (resume_start_phase_test.go style) pinning the ticker arm.
4. Engineer adversarial review; present diff to King; push after ratification.
5. Rerun scenario → GREEN. Record RED+GREEN run IDs here.
6. File the recoveryRollback startup-coverage audit task.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
CONSOLIDATED 2026-06-11 (architect/Fable; prior forensic notes recoverable via git log on this file — they duplicated doc-005).

VERDICT: gap CONFIRMED + severity escalated, foreman-verified at byte level. Boot-migrate is the de-facto migration executor for EVERY upgrade (executeUpgrade Step 6b ALWAYS hands off: checkout → swap → exit-42/Exec → fresh boot runs :1644 before recoverFromFlag :1689). All four refutation avenues closed — no ambient pinger, PrefixWriter inert with onLine=nil, migrate child has no sdNotify + NotifyAccess=main drops child datagrams, idle ticker born :1736 after boot-migrate. Suite blind spot: 3-postswap-migration-timeout is vacuous (inline dispatch → no watchdog in flow) — why 24/28 green never caught this.

Full design + evidence: doc-005. Engram obs 157 (verdict) + 168 (King decisions). Execution per the plan above; architect executing.

DIAGRAM/DOC SYNC folds into the 012 fix commit (engineer's King-directed diagram<->reality audit, doc-006, 2026-06-11). upgrade-timeline.plantuml + .md are out of sync with 012 reality: the post-swap band omits the fresh process re-running boot-migrate (the 012 site where every upgrade's migrations ACTUALLY run) before recoverFromFlag; draws the applyPostSwap migrate as the executor when it's a structural no-op; asserts watchdog coverage that doesn't exist (migration-timeout); lists a deferred scenario (worker-ddl-deadlock) as coverage. Per the engineer's recommendation, fix the diagram/doc in the SAME commit as the 012 product fix so code + diagram move together (matches the project's code<->doc pairing discipline). Full gap table: doc-006.
<!-- SECTION:NOTES:END -->
