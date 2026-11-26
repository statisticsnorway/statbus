---
id: qjy2eg
title: "Quality check: secondary activity equals primary activity"
state: "doing"
type: feature
priority: ""
assignee: ["opus-a"]
labels: []
group: ""
rank: "zzzzzzzzzzzc"
created: 2026-11-26
updated: 2026-11-26
doing_since: "2026-11-26T21:22"
stage: "active"
model: "claude-opus-5-5"
branch: "quality/default-off-secondary-equals-primary"
worktree: "/Users/jhf/ssb/statbus_a"
---

## Goal
A quality check lists legal units and establishments whose secondary activity category is the same as their primary.

## Purpose
Owner 2026-11-26 reviewing Data quality: a secondary activity equal to the primary makes no sense; it should not be secondary.

## Principle
One new quality_rule in the catalogue (enum value, a branch in quality_finding_def, wording keyed by the rule); it covers both legal units and establishments, like missing_activity_category. No special-case code outside the catalogue.

## Details
public.activity rows of type primary and secondary for the same unit with the same category_id over overlapping valid_range. Count on the Norway copy once the local slot is idle (a first count timed out during its refresh). Lands together with the default-off decision (owner's sensible starting set).

## Depends on

## Acceptance
- [x] Test 411 (or a new test) asserts a unit with secondary = primary is listed and one with different categories is not, for legal unit and establishment
- [ ] On the Norway copy the card equals its search list, observed in a browser

## Notes


check 1: test/sql/411 §411.3c on branch quality/default-off-secondary-equals-primary (0fe3b95e1): LU-SECSAME and LU-SECSAME-es1 listed, LU-SECDIFF and -es1 not; RED tmp/test-qjy2eg-1tx1ed-RED.log (invalid enum value), GREEN tmp/test-qjy2eg-1tx1ed-GREEN.log
Norway copy (slot a, 5.23M statistical_unit rows) after migrating and a full worker run: secondary_activity_equals_primary finds 0 units. Confirmed at source: 32,642 LU/ES rows have a secondary activity, none equals the primary; public.activity has no overlapping primary/secondary pair with the same category. Card = search list (statistical_unit_quality) at current_date for every check: 2/2, 161571/161571, 22446/22446, 11010/11010, 17/17, 5/5, 0/0 (tmp/norway-quality-counts.txt). Browser check (check 2) not done.
landed 9383f1f on master 2026-11-26: quality: secondary activity equals primary is a check (qjy2eg)
landed dff701f on master 2026-11-26: quality: checks start switched off except a starting set (1tx1ed, qjy2eg)
## History
- 2026-11-26T21:22 todo -> doing/active (take)
