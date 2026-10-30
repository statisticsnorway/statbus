---
id: STATBUS-012
title: >-
  Latent product gap: boot-migrate-up emits no WATCHDOG=1 (large-DB boot-migrate
  >120s → watchdog-killed)
status: Done
assignee:
  - '@architect'
created_date: '2026-06-07 23:57'
updated_date: '2026-06-11 15:37'
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
- [x] #2 RED observed on a real VM: rewritten service-dispatch slow-migration scenario shows the watchdog kill loop on current code
- [x] #3 Product fix landed: boot-migrate under the always-ping ticker + shared 30-min timeout; inline ./sb install boot-migrate bounded at 30 min; both drifted comments repaired
- [x] #4 Engineer adversarial review of the diff passed; King ratified before push
- [x] #5 GREEN proven on a real VM: same scenario, zero watchdog restarts from post-stall baseline, upgrade completes — RED→GREEN pair recorded with run IDs
- [x] #6 Follow-up audit task filed: recoveryRollback/restoreDatabase startup path checked for the same missing-heartbeat gap
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
COMPLETE — RED→GREEN PROVEN ON REAL VMs (architect/Fable, 2026-06-11). Awaiting the King's review-against-proof (his gate: "commit, I review only if it provably works" — it provably works).

THE PAIR (one commit apart, same scenario 3-postswap-migration-timeout, service dispatch, real systemd):
- RED @ 78ab02598 (unfixed), run-7 / VM statbus-recovery-012-red7, log tmp/012-red-run-7.log: stall detected at the post-swap boot-migrate (probe PID parked in StallHere, flag=post_swap site-proof ✓), 180s hold → watchdog SIGABRT → NRestarts post-stall 1→2 delta=1, Result=watchdog, row stuck in_progress mid-kill-loop. Plus run-6 journal (informal first observation): TWO kills ~150s apart = the predicted loop cadence; after the stall released, the next boot self-healed and the upgrade COMPLETED (recovery path incidentally proven).
- GREEN @ 7c2511087 (the fix), run / VM statbus-recovery-012-green1, log tmp/012-green-run-1.log: same stall, same site, 180s hold → ticker pings → delta=0, Result=success, "no watchdog kill across 180s stall", upgrade completed t+31s after release, data intact, flag absent, restart counter bounded. PASS.

THE FIX (commit 7c2511087, engineer adversarial review PASS pre-landing): always-ping runGatedWatchdogTicker wrap at boot-migrate (child ctx, explicit inline cancel+join before error handling); shared MigrateUpTimeout=30m at both migrate sites; inline install crash-recovery migrate bounded (was unbounded); structural guard TestBootMigrateWatchdogCover_SourceOrder; comment/diagram repairs per doc-006 (A1-A6, B1; SVG regenerated).

HARNESS LEDGER (runs 1-6 were detection layers, each converted to a permanent guard): procurement short-circuit (cp + sbAlreadyAtCommit), binary↔row pairing assertion (board-in-git mid-run commits), dispatch-on-HEAD-binary restart (old binary lacks the skip), [/] pgrep bracket trick, scp'd quoting-proof stall probe + 600s budget. Scenario commits: 908191f0c, f1056ade4, 0904b4db4, 538b2edf4, 78ab02598.

FOLLOW-UPS: STATBUS-031 (recoveryRollback startup heartbeat audit — AC#6 ✓ filed). Proposed to the King, awaiting his word: a tag→tag upgrade-recovery scenario covering the manifest-download procurement path (replaceBinaryOnDisk) that this scenario's pre-stage skip bypasses. Foreman's C15-hardening task should absorb the wait_for_inject_stall_ready quoting fix (the scp'd-probe pattern).

CLOSED 2026-06-11 — fixed + proven + shipped. The King cut RC v2026.06.0-rc.01 carrying the fix (7c2511087). RED→GREEN differential pair, one commit apart: run-7 RED (78ab02598 — delta=1, Result=watchdog) → green1 GREEN (7c2511087 — delta=0, '✓ no watchdog kill across 180s stall', upgrade completed t+31s). Foreman master-health review PASS (always-ping ticker child-ctx cancel+join inline; shared MigrateUpTimeout=30m at both migrate sites; inline twin bounded; structural guard test; doc-006 diagram repairs folded in). Sibling gap STATBUS-031 (recoveryRollback restore) filed + CONFIRMED — gates the stable/Norway promotion. The boot-migrate watchdog wedge (rune wedge's WatchdogSec edition) is fixed and shipped.
<!-- SECTION:NOTES:END -->
