---
id: qjy2eg
title: "Quality check: secondary activity equals primary activity"
state: todo
type: feature
priority: ""
assignee: []
labels: []
group: ""
rank: "zzzzzzzzzzzv"
created: 2026-11-26
updated: 2026-11-26
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
- [ ] Test 411 (or a new test) asserts a unit with secondary = primary is listed and one with different categories is not, for legal unit and establishment
- [ ] On the Norway copy the card equals its search list, observed in a browser

## Notes
