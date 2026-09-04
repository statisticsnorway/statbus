---
id: STATBUS-346
title: >-
  release stable refusal output: summarize per workflow, print each changed-file
  list once, details behind --verbose
status: Done
assignee:
  - '@mechanic'
created_date: '2026-09-03 05:53'
updated_date: '2026-09-03 16:33'
labels:
  - release
  - ux
dependencies: []
priority: medium
type: enhancement
ordinal: 339000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Issue: ./sb release stable's refusal output prints the full upgrade-sensitive changed-file list PER BLOCKED SCENARIO. At rc.12 that was 32 arc scenarios x 93 files plus 13 fleet scenarios x 29 files — thousands of repeated lines drowning the three facts that matter (which gate, how many covered, what command to run). King hit this live during the v2026.09.0 promotion morning.

Fix: group refusals by workflow. Print per workflow: one summary line (covered/total at target, anchor version, count of sensitive files changed since anchor), then one compact line per blocked scenario (name only, or name + its anchor when anchors differ), then the changed-file list ONCE per distinct (anchor, file-set), collapsed behind a --verbose flag or a 'run X to see the list' pointer. Keep the Trigger/Watch/Fix lines exactly as they are - they are the actionable part.

Acceptance: the rc.12-shaped refusal fits on one screen; every distinct file-set is printed at most once; --verbose (or equivalent) recovers today's full detail; no gate LOGIC changes - output shaping only (cli/cmd/release.go + release_coverage_authority.go printers).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A stable-preflight refusal with N blocked scenarios prints the shared changed-file list at most once, never per scenario
- [x] #2 Each blocked scenario costs one line (name + anchor + count), with the full list behind --verbose or a printed command
- [x] #3 Trigger/Watch/Fix command lines are preserved verbatim
- [x] #4 Existing gate logic unchanged — output shaping only
<!-- AC:END -->
