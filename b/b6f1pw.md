---
id: b6f1pw
title: "Unit edit page marks the field a quality check flags"
state: "doing"
type: feature
priority: ""
assignee: ["rabbit"]
labels: []
group: ""
rank: "zzzzzzzzzzzj"
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
One wording source (QUALITY_RULE_WORDING); the unit page reads the unit's own quality_check_ids and relation-table rows for the period shown, so it agrees with the reports.

## Details
Rule to field: missing_region and missing_physical_location to Contact/location; missing_activity_category, secondary_activity_equals_primary and establishment_activity_differs to Classifications; the per-variable rules to Statistical variables.

## Depends on

- h9mhxe
## Acceptance
- [ ] ~~Legal unit 146 on the Norway copy shows the secondary-equals-primary mark on its Classifications page, and the mark goes when the secondary activity changes~~ (not relevant: split into two checks (mark appears, mark goes), rabbit, 2026-11-27)
- [x] Legal unit 146 on the Norway copy shows a mark on its Secondary activity field on the Classifications page, worded by QUALITY_RULE_WORDING as the dashboard card
- [x] After the secondary activity is changed to another code, the mark is gone at the next page load

## Notes


check 2: Norway copy, a9d45e1a2 (local, on quality 91ce3e04e): secondary set to 56.101 (= primary) through the page's edit; 14 s later the Secondary Activity field shows an amber mark whose popover reads the card's name and explanation 'Secondary activity equals primary' (tmp/b6f1pw-mark-appears.log, tmp/b6f1pw-mark.png); quality_check_count gives check 7 = 1. Also seen: LU 295204 marks Primary activity with 'Establishment has another activity'.
2026-11-27 16:13 owner review in tab 65 (LU 146 Classifications): the amber triangle is sensible; placed after the field's fixed icons (ⓘ metadata, timeline) so those keep one position on every field. Done in a30acb540 (ui/unit-page-quality-marks-wt, on quality 127070849).
2026-11-27 16:28 owner approved in tab 65 (LU 146): after the fixed icons (ⓘ, timeline) the amber triangle, then the check's name in the search Quality filter's orange chip, 13 px medium weight, no outline (an outline was tried and rejected); click opens the explanation.
check 3: Norway copy at master 8725ab27b: secondary activity of LU 146 set back to 56.102 through the page's edit (Playwright, one click); 14 s after Save the page shows no mark (tmp/b6f1pw-mark-goes.log). Merged as 78c95b358.
landed 78c95b3 on master 2026-11-27: app: a unit's pages mark the field a quality check flags (b6f1pw)
## History
- 2026-11-27T01:12 todo -> doing/active (take with 0pn35h)
