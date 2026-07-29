---
id: STATBUS-195
title: >-
  discovery-watchdog-starvation: a cold multi-candidate image-verify pass
  starves WatchdogSec on the main goroutine — false 'hang' kill mid-discovery
status: Done
assignee:
  - architect
created_date: '2026-07-20 15:30'
updated_date: '2026-07-29 11:12'
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
- [x] #1 The discovery image-verify pass feeds the watchdog per candidate (or rides a gated ticker bounded by its own timeout) — a slow-but-progressing multi-candidate pass no longer gets killed; a verify genuinely stuck on one candidate still does
- [x] #2 Build-time check recorded: a watchdog kill mid-discovery AFTER a claim (row claimed, upgrade not yet started) recovers cleanly on restart
- [x] #3 Oracle named at build: Go test on the heartbeat seam (structural or behavioral); the arc fleet's journals stop showing 'Failed with result watchdog' during discovery
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-07-29 11:09
---
BUILT (architect hands-on, 2026-07-29) — frozen in the tree for the foreman's line review + commit. AC#1: emitHeartbeat(d.projDir) at the top of verifyArtifacts' pending-candidate loop — each completed candidate feeds the watchdog; a verify stuck on ONE candidate emits nothing further and still starves it (the correct kill preserved); comment carries the run citation + the false-kill class. The seam existed, so the per-candidate form was used (cheaper and more faithful than the gated-ticker alternative). AC#2 RECORDED: the observed pre-claim kill recovered cleanly (run evidence); the post-claim sub-second window [in_progress row + no flag + backup_path NULL] is DB-SAFE by the existing empty-backup refusal (exec.go:858-874) but raises a stale-pre-upgrade-pin question on the GIT side — split to STATBUS-197 (triage, analysis-only, no observed occurrence) rather than resolved from the chair. AC#3: structural pin TestVerifyArtifacts_FeedsWatchdogPerCandidate (heartbeat INSIDE the loop, order-asserted) — passing; the behavioral half is the standing arc fleet: journals stop showing 'Failed with result watchdog' during discovery, checked by observation on subsequent runs. go build + vet + targeted tests green, gofmt clean.
---

author: foreman
created: 2026-07-29 11:12
---
FOREMAN LINE REVIEW + COMMIT (2026-07-29): reviewed the frozen diff in full — the per-candidate emitHeartbeat(d.projDir) sits at the top of verifyArtifacts' pending loop (service.go:1508), same form as the existing boot-migrate cover call site (service.go:2300); the structural pin order-asserts heartbeat INSIDE the loop and self-invalidates loudly if the loop is renamed. Independently verified: go build + vet green, gofmt clean on both changed files, targeted tests green, FULL upgrade-package suite green (9.3s). COMMITTED a316b1a2b, pushed to master. Closing Done: all three ACs checked; AC#3's behavioral half (arc-fleet journals stop showing 'Failed with result watchdog' during discovery) is a standing observation on every subsequent arc run — any recurrence reopens loudly against the pin's run citation. Side hygiene rider, separate commit 341175701: gofmt drift in four untouched upgrade files (formatting only). The AC#2 git-side question lives on in STATBUS-197 (triage, analysis-only).
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Watchdog false-kill during cold multi-candidate discovery fixed at the uncovered site: emitHeartbeat per completed candidate inside verifyArtifacts' pending loop (each completed candidate is genuine progress; a verify stuck on one candidate still starves the watchdog — the correct kill preserved). Structural pin TestVerifyArtifacts_FeedsWatchdogPerCandidate order-asserts the heartbeat inside the loop. Built by architect, foreman line-reviewed + committed a316b1a2b. Behavioral oracle stands on every subsequent arc run: journals must stop showing 'Failed with result watchdog' during discovery. Post-claim sub-second-window git-side question split to STATBUS-197.
<!-- SECTION:FINAL_SUMMARY:END -->
