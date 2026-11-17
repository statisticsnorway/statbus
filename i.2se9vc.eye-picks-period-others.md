---
id: 2se9vc
title: "The eye picks the period others are compared with, on the field's timeline too"
status: todo
type: feature
priority: ""
assignee: []
labels: ["app", "edit"]
created: 2026-11-17
updated: 2026-11-17
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
- nst6hb

## Acceptance
- [ ] Opening a field's timeline shows a black eye on the period of the page's time frame and grey eyes on the others
- [ ] Every other period marks the columns and the data source that differ from the reference, and shows nothing extra where they agree
- [ ] Clicking a grey eye makes that period the reference and the marks follow it
- [ ] In the edit's Timeline the same eye moves the anchor, and the form takes that period's values

## Notes
