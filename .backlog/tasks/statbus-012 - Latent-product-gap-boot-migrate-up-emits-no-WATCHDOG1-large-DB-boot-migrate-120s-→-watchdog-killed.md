---
id: STATBUS-012
title: >-
  Latent product gap: boot-migrate-up emits no WATCHDOG=1 (large-DB boot-migrate
  >120s → watchdog-killed)
status: In Progress
assignee:
  - '@architect'
created_date: '2026-06-07 23:57'
updated_date: '2026-06-11 08:53'
labels:
  - upgrade
  - recovery
  - product
dependencies: []
references:
  - cli/internal/upgrade/service.go
  - ops/statbus-upgrade.service
priority: high
ordinal: 12000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Architect surfaced this during the archivebackup-resume diagnosis (it is NOT the cause of that failure — a separate latent product gap, found en route).

cli/internal/upgrade/service.go:1644 boot-migrate-up runs `./sb migrate up` with writer=io.Discard + onAdvance=nil, in the ACTIVE phase, BEFORE the applyPostSwap gated ticker arms (service.go:3734) — so it emits NO WATCHDOG=1 heartbeat. A large-DB boot-migrate exceeding WatchdogSec=120s would be watchdog-killed with no heartbeat. Invisible in tests (test boot-migrate is a fast no-op). The unit comment ops/statbus-upgrade.service:87 assumes boot-migrate is safely active-phase — only true if it finishes <120s.

Relevant for large external/standalone DBs (the upgrade-hardening-for-external-customers arc; rune/Norway). PRODUCT fix: emit WATCHDOG=1 during boot-migrate (an onAdvance heartbeat, or arm a heartbeat ticker before boot-migrate). Flagged for the King's review — recovery code, no autonomous change overnight. Full diagnosis: tmp/architect-archivebackup-resume-diagnosis.md.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Confirm boot-migrate-up runs active-phase with no WATCHDOG=1 before the gated ticker arms
- [ ] #2 Decide + implement the heartbeat (onAdvance WATCHDOG=1, or a ticker armed before boot-migrate)
- [ ] #3 A boot-migrate >120s no longer gets watchdog-killed (verify, e.g. an injected slow boot-migrate scenario)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
CONFIRMED PRODUCT GAP — foreman trace 2026-06-11 — promoted MEDIUM->HIGH. boot-migrate-up at cli/internal/upgrade/service.go:1644 runs './sb migrate up --verbose' with onAdvance=nil + io.Discard, in the active phase but BEFORE recoverFromFlag(:1689)/applyPostSwap. WATCHDOG=1 coverage lives ONLY in the applyPostSwap progress-gated ticker (:3692-3758), which is not running at :1644. While the main goroutine is parked in the migrate subprocess, nothing pings the watchdog (see :3698 'no opportunity to ping WATCHDOG=1 from the main loop'; exec.go:127-141: onAdvance fires per output line, and a SILENT CREATE INDEX emits no lines). ops/statbus-upgrade.service: Type=notify, WatchdogSec=120, Restart=always. => a boot-migrate >120s on a large DB (Norway=32GB) -> systemd kills the unit -> post-017 falls through to rollback -> upgrade never completes. Rune-wedge SIBLING: 017 killed the TimeoutStartSec version of this; :1644 is the WatchdogSec version. Symmetric gap at cli/cmd/install_upgrade.go:199-210. Invisible to the suite: NO scenario tests a slow boot-migrate (why 'zero product bugs' felt true). Comment drift: :1640 claims it 'survives (emits per-migration progress)' but wires no heartbeat hook. OPEN for architect: SEVERITY — do the heavy upgrade migrations run at :1644 or at the protected applyPostSwap site? RIGOR: produce a RED reproducing scenario (slow boot-migrate -> watchdog kill) BEFORE any fix (test-first as discovery). Likely fix: give boot-migrate the same always-ping / server-side-progress coverage applyPostSwap's migrate already has, at BOTH sites. Full trace in engram obs 153.

Dispatched to architect (running as Fable) 2026-06-11 for adversarial verification (refute-first) + severity call + fix-plan design. Recovery code is King-gated: DESIGN ONLY, no product edits. Plan to land under tmp/plans/architect-012-*.md.

ARCHITECT (Fable) ADVERSARIAL VERIFICATION 2026-06-11 — VERDICT: CONFIRMED, severity UPGRADED. All 4 refutation avenues closed with code evidence (no ambient pinger — emitHeartbeat callers are only progress.go:251 + service.go:1753; PrefixWriter fires nothing with onLine=nil; migrate child has no sdNotify code AND NotifyAccess defaults to 'main' so child pings would be dropped; the 30s idle tick is born at :1736 — AFTER boot-migrate). AC#1 checked.

SEVERITY KEY: executeUpgrade Step 6b (service.go:3560-3574) ALWAYS hands off (checkout → swap → PostSwap flag → exit-42/Exec), so boot-migrate at :1644 consumes the ENTIRE migration delta on EVERY upgrade, before recoverFromFlag(:1689). The protected applyPostSwap migrate (:3949-3953, 30-min + always-ping) is a structural NO-OP for migrations in the normal flow. Production migration budget = ~120s. A single >120s migration (Norway 32GB) = indefinite watchdog kill-loop (~160s cycle → 3.75 starts/600s < StartLimitBurst=5 → start limit never trips). Rune-wedge WatchdogSec edition. Plus: :1644's 5-min timeout vs protected site's 30-min; inline twin install_upgrade.go:198 runs via runCmdDir = NO timeout at all (install.go:2208).

SUITE BLIND SPOT: 3-postswap-migration-timeout (the only Race-B watchdog net) is VACUOUS — inline dispatch (no systemd → no watchdog anywhere), stall fires at the unbounded inline boot-migrate, NRestarts assertion reads an idle unit. One of the 24 greens masks this exact gap.

PLAN: tmp/plans/architect-012-boot-migrate-watchdog.md — RED repro = rewrite C12 scenario to SERVICE dispatch (unit-env drop-in, baseline NRestarts after stall, assert delta==0 + Result≠watchdog); FIX = runGatedWatchdogTicker(nil=always-ping) wrap at :1644 + shared 30-min const with :3952 + bound install_upgrade.go:198 + comment repairs (service.go:1637-1641, unit file :83-104). Follow-up audit flagged: recoveryRollback's pg_restore during Run() startup may share the gap (not traced to ground). Awaiting King ratification of the design; RED scenario is harness-only and can proceed without the gate.
<!-- SECTION:NOTES:END -->
