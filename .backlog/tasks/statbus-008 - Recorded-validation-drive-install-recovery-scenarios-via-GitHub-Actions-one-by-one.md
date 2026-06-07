---
id: STATBUS-008
title: >-
  Recorded validation: drive install-recovery scenarios via GitHub Actions (one
  by one)
status: In Progress
assignee:
  - operator
created_date: '2026-06-07 15:41'
updated_date: '2026-06-07 21:01'
labels:
  - install-recovery
  - validation
  - ci
dependencies: []
priority: high
ordinal: 8000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Drive each install-recovery scenario via GitHub Actions (`gh workflow run install-recovery-harness.yaml --ref master -f scenarios="<slug>"`), one at a time, so every pass/fail is RECORDED + queryable (vs ephemeral local runs). Confirms recovery behavior in reality and exercises the gate. Subsequent verdicts appended in notes.

Prereq per run: the Images workflow must have pushed the seed image (statbus-seed:<sha>) for the SHA first, else the harness build fails "manifest unknown" (ordering finding from the first attempt).

TALLY (--ref master @ 4e07dc4d):
- 0-happy-install: PASS — run 27096800159 (https://github.com/statisticsnorway/statbus/actions/runs/27096800159), 9m29s. First attempt 27096707578 failed on seed-image-not-yet-pushed timing; re-run green.
- 3-postswap-watchdog-reconnect: dispatched (in progress).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Baseline 0-happy-install driven + recorded (PASS)
- [ ] #2 The three sharpened-claim scenarios driven + recorded: watchdog-reconnect, migrate-killed-after-commit, archivebackup-resume
- [ ] #3 Each driven scenario's GitHub run URL + verdict captured in the notes tally
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
watchdog-reconnect (run 27097092218): FAILED — HARNESS BUG, not a real recovery failure. The scenario's systemd drop-in install used a here-document that collapsed newlines (log: `EOF[Service]Environment=...Environment=...EOF` on one line), so systemd couldn't parse the override and the unit stayed inactive — the scenario can't even stage its test (product code never exercised). Mechanic dispatched to fix the heredoc + assess scope (shared drop-in helper?). DRIVE-THROUGH PAUSED until the harness fix is committed + pushed; subsequent runs will be on the fixed SHA.

Harness fix pushed: 4e07dc4d5..2bc671ecf. Root cause was VM_EXEC's printf '%q' ANSI-C quoting collapsing the heredoc-over-bash-c; fixed to mktemp + local heredoc + scp + remote bash (the pattern the archivebackup scenarios already use). Fixed watchdog-reconnect AND the same LATENT bug in 1-boot-startup-timeout. Scope: 2 scenarios, NOT a shared helper. Pending: Images must build the seed image for 2bc671ecf, then re-run watchdog-reconnect, then continue (migrate-killed-after-commit, archivebackup-resume) on this SHA.

watchdog-reconnect re-run (run 27097723557 @ 2bc671ecf): harness heredoc fix WORKED ✓ (C15 drop-in installed cleanly, 'unit active with C15 env vars'). But FAILED on a NEW, deeper issue: the supervised upgrade unit did NOT transition the scheduled row to in_progress within 180s — row stayed 'scheduled', upgrade never started, so the C15 reconnect injection was never reached. Service was up + healthy (discovered 176 tags, verified images) but didn't pick up the scheduled upgrade. Either a REAL upgrade-service polling/NOTIFY bug or a scenario/supervised-path issue — engineer dispatched to diagnose (read-only). NOT a regression from our changes (none touched polling). Continuing drive-through with migrate-killed-after-commit (inline ./sb install path, independent of the supervised path) in parallel.

TALLY update: 0-happy-install PASS; watchdog-reconnect = harness-fix-confirmed but blocked on upgrade-pickup (under diagnosis); migrate-killed-after-commit dispatched.

watchdog NOTIFY fix (engineer, commit 3bb6d703d — verified correct/scoped: defines SHORT_SHA from HEAD_LOCAL, sends ./sb upgrade apply NOTIFY mirroring archivebackup-watchdog, fixes the stale 180s diagnostic) pushed 2bc671ecf..3bb6d703d. Operator driving: Images-green-for-3bb6d703d → re-run watchdog-reconnect (~12-15 min). The migrate INSTALL_VERSION fix (4568554b7) is now pushed too; migrate-killed-after-commit runs AFTER watchdog is green (one scenario at a time).

watchdog-reconnect re-run (run 27104216670 @ 3bb6d703d): NOTIFY FIX WORKED ✓ — NOTIFY → executeScheduled in 58s, stall held 180s > WatchdogSec=120s, NRestarts within tolerance (Race D fix holds), upgrade completed, flag absent, demo data intact. The CORE watchdog/reconnect recovery behavior is VALIDATED. Remaining failure: 'orphan backup(s) found' at test/install-recovery/lib/assertions.sh:100 — leftover backup files the assertion expects cleaned up. Engineer diagnosing: real product cleanup gap (pruneArchives / archiveBackup) vs over-strict assertion. Progress: harness heredoc + NOTIFY both fixed; one cleanup assertion left on this scenario.
<!-- SECTION:NOTES:END -->
