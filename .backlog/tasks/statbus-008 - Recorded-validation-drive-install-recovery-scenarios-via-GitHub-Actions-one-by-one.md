---
id: STATBUS-008
title: >-
  Recorded validation: drive install-recovery scenarios via GitHub Actions (one
  by one)
status: In Progress
assignee:
  - operator
created_date: '2026-06-07 15:41'
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
