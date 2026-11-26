---
id: bysgyd
title: "Demo file legal_units_with_source_dates has garbled Gøta Kanal"
state: "doing"
type: feature
priority: ""
assignee: ["rabbit"]
labels: []
group: ""
rank: "zzzzzzzzzzzy"
created: 2026-11-26
updated: 2026-11-26
doing_since: "2026-11-26T10:17"
doing_with: "ca6dk5"
stage: "active"
model: "claude-opus-5-5"
branch: "master"
worktree: "/Users/jhf/ssb/statbus_test"
---

## Goal
Every shipped demo file passes the upload encoding check, so Upload demo data works again.

## Purpose
Hedda 2026-11-25: dev refused the demo file: line 15 'GÃ¸te Kanal'. The check (e1z8va) is a true positive: the file has carried mis-encoded text since 51d48e623 (2025-09-13).

## Principle
Repair the data at its source; keep the check strict. A Jest test runs the upload check over every file in app/public/demo.

## Details
Rows 15-16: physical_postplace 'GÃ¸te Kanal' (one round of UTF-8 read as Windows-1252) -> 'Gøte Kanal'; postal_postplace garbled three rounds -> 'Gøta Kanal'. Row 14 already had 'Gøta Kanal'. No other tracked CSV has the garbled bytes.

## Depends on

## Acceptance
- [ ] demo-files-upload.test.ts fails on the old file and passes on the repaired one
- [ ] SQL tests 309 and 310, which load this file, pass

## Notes


## History
- 2026-11-26T10:17 todo -> doing/active (take with ca6dk5)
