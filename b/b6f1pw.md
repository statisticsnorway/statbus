---
id: b6f1pw
title: "Unit edit page marks the field a quality check flags"
state: "doing"
type: feature
priority: ""
assignee: ["rabbit"]
labels: []
group: ""
rank: "zzzzzzzzzzzx"
created: 2026-11-27
updated: 2026-11-27
doing_since: "2026-11-27T01:12"
doing_with: "0pn35h"
stage: "depends"
model: "claude-opus-5-5"
branch: "master"
worktree: "/Users/jhf/ssb/statbus"
---

## Goal
A unit's edit page marks each field a switched-on quality check flags, in the reports' wording.

## Purpose
Owner 2026-11-26: the quality reports find the units, but someone opening the unit to fix it must see which field is wrong, such as the secondary activity when it equals the primary.

## Principle
One wording source (QUALITY_RULE_WORDING); the unit page reads public.quality_finding for the unit and period shown, so it agrees with the reports. Done after the current rc.02 tasks.

## Details
Rule to field: missing_region and missing_physical_location to Contact/location; missing_activity_category, secondary_activity_equals_primary and establishment_activity_differs to Classifications; the per-variable rules to Statistical variables.

## Depends on

- h9mhxe
## Acceptance
- [ ] Legal unit 146 on the Norway copy shows the secondary-equals-primary mark on its Classifications page, and the mark goes when the secondary activity changes
- [ ] Legal unit 146 on the Norway copy shows a mark on its Secondary activity field on the Classifications page, worded by QUALITY_RULE_WORDING as the dashboard card
- [ ] After the secondary activity is changed to another code, the mark is gone at the next page load

## Notes


## History
- 2026-11-27T01:12 todo -> doing/active (take with 0pn35h)
