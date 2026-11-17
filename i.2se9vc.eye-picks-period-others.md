---
id: 2se9vc
title: "The eye picks the period others are compared with, on the field's timeline too"
status: "doing"
type: feature
priority: ""
assignee: ["rabbit"]
labels: ["app", "edit"]
created: 2026-11-17
updated: 2026-11-17
model: "claude-opus-5-5"
branch: "statbus-628-all-forms"
worktree: "/Users/jhf/ssb/statbus_test"
---

## Goal
In a field's timeline, the reader sees at once what differs between periods: one period is the reference (black eye), the others mark the parts that differ from it, and clicking another period's grey eye makes it the reference.

## Purpose
Owner review 2026-11-17: in the Physical Location popover, 'Kampala Road 1' vs 'Kampala Road 2' and 'nlr' vs 'survey' are a find-the-difference game humans lose. The edit's Timeline already strikes out differences against its anchor; the read-only timeline should help the same way.

## Principle
Physical locality: the eye that chooses the reference sits on each period's own card. One reference at a time, starting at the page's selected time frame.

## Relevant details
Popover: field-timeline-view.tsx (read-only, no onToggle). Edit: the anchor's eye (a02bbb9aa) is today a marker, not a control. Differences are per column (address parts, region, country) and the data source.

## Depends on

## Acceptance
- [x] Opening a field's timeline shows a black eye on the period of the page's time frame and grey eyes on the others
- [x] Every other period marks the columns and the data source that differ from the reference, and shows nothing extra where they agree
- [x] Clicking a grey eye makes that period the reference and the marks follow it
- [x] In the edit's Timeline the same eye moves the anchor, and the form takes that period's values

## Notes

2026-11-17 13:38 built on branch (Rabbit): differencesFrom (RED tmp/2se9vc-red.log, GREEN tmp/2se9vc-green-model.log; jest 435, tsc ok, lint 0 errors tmp/2se9vc-checks.log). Headless tmp/2se9vc-check.log + tmp/2se9vc/: LU 29 Physical Location popover on Live shows black eye on Live, grey on 2024/2025, 2024 marks address_part1 (Kampala Road 1), 2025 marks data source (survey); clicking 2024's eye makes it the reference and 2025 then marks address_part1 + data_source, 2026 marks address_part1. Name edit, Tick all: black eye on Live (form 'EDIT PAGES AS'); clicking 2024's grey eye moves the eye and the form to 'EDIT PAGES ASA'. DB unchanged.
