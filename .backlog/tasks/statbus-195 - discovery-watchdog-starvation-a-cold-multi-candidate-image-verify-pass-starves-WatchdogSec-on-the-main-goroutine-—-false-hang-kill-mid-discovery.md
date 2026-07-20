---
id: STATBUS-195
title: >-
  discovery-watchdog-starvation: a cold multi-candidate image-verify pass
  starves WatchdogSec on the main goroutine — false 'hang' kill mid-discovery
status: To Do
assignee: []
created_date: '2026-07-20 15:30'
labels:
  - upgrade
  - recovery
  - defect
  - watchdog
dependencies: []
references:
  - cli/internal/upgrade/service.go
  - cli/internal/upgrade/watchdog.go
priority: medium
ordinal: 196000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: the watchdog kills HUNG daemons, never SLOW-BUT-LIVE ones — every false kill erodes the signal the watchdog exists to give.
> FOUND: 2026-07-20, harness run 29743621767 (deploy-status-proof arc), architect-read diagnostics. The FIRST daemon (pid 27566) was killed by systemd at 13:07:27 — 'Failed with result WATCHDOG', SIGABRT goroutine dump, exit status=2 — while demonstrably ALIVE and progressing: the journal shows a discovery pass serially verifying candidate images at ~17-21s each (13:05:48 f7a747e4, 13:06:09 fd368145, 13:06:30 91f947ce, 13:06:47 50fd4325, …). With 8 channel-matching candidates cold, the pass exceeds WatchdogSec=120s with no WATCHDOG=1 emitted — discovery runs on the MAIN goroutine (the select-loop tick), and its per-candidate verify emits no heartbeat.
> RECOVERY OBSERVED (why this is bounded, not urgent): systemd restarted the unit (counter=1); the second pass rode docker's surviving manifest cache, finished discovery in ~35s, claimed and ran the upgrade cleanly. Self-correcting by construction — but it burns a restart cycle, dumps a scary goroutine trace into the journal, and on a box with a slow registry + many candidates could take several kill/restart rounds to converge.
> CLASS: the known FALSE-KILL genre — 'the 120s detection was a FALSE kill of legitimate slow migrations' (service.go:2036, the boot-migrate precedent, fixed there with a watchdog cover bounded by the step's own timeout). This is the same gap at an uncovered site.
> NOT THIS ARC'S DEFECT: the arc VM's candidate set (186 tags, 8 stable matches + arc registrations) is unusually rich; production slots typically carry fewer candidates. Severity moderate; NOT release-gating (bounded, self-correcting, ledger untouched — the kill here landed pre-claim).

FIX SHAPE (architect): heartbeat cover for the discovery verify loop, following the established pattern — the cheapest faithful form is an emitHeartbeat() (or progress-equivalent) per candidate verified inside the loop: each completed verification IS genuine progress, so feeding the watchdog per candidate keeps the hang-detection property (a verify stuck on ONE candidate past its own timeout still starves and gets killed — correctly). Alternative if the loop lacks a per-candidate seam: the gated runGatedWatchdogTicker wrapper bounded by the verify step's own timeout (the boot-migrate form, service.go:2054-2076). Interaction check at build time: whether a kill mid-discovery AFTER a claim (row claimed, upgrade not started) recovers cleanly — in the observed run the kill landed pre-claim.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The discovery image-verify pass feeds the watchdog per candidate (or rides a gated ticker bounded by its own timeout) — a slow-but-progressing multi-candidate pass no longer gets killed; a verify genuinely stuck on one candidate still does
- [ ] #2 Build-time check recorded: a watchdog kill mid-discovery AFTER a claim (row claimed, upgrade not yet started) recovers cleanly on restart
- [ ] #3 Oracle named at build: Go test on the heartbeat seam (structural or behavioral); the arc fleet's journals stop showing 'Failed with result watchdog' during discovery
<!-- AC:END -->
