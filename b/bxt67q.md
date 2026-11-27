---
id: bxt67q
title: "Disabling a summed variable leaves its quality findings until a recalculation"
state: todo
type: feature
priority: ""
assignee: []
labels: []
group: ""
rank: "zzzzzzzzzzzs"
created: 2026-11-27
updated: 2026-11-27
---

## Goal
Disabling or enabling a summed statistical variable updates its per-variable quality findings without a unit edit.

## Purpose
A disabled variable's checks leave the dashboard (quality_check lists enabled variables only), but its findings stay in quality_finding and the search's quality filter still lists them; enabling it again shows findings that may be stale.

## Principle
The change that alters a rule's input schedules the rederive of what it affects. Found while extending test 144 (0pn35h); the same on the code before 0pn35h, so not caused by it.

## Details
stat_definition has only lifecycle callback triggers; no derive is enqueued. Test 144.7: after disabling employees with no unit edit, 1 employees finding remains. Options: enqueue worker.enqueue_derive_statistical_unit_all() on enabled change of a summed variable, or let derive_quality delete findings of disabled variables.

## Depends on

## Acceptance
- [x] Test 144.7 shows 0 employees findings after the variable is disabled with no unit edited

## Notes

Closed by the design in h9mhxe (acceptance check 6).

Design in h9mhxe (acceptance check 6) applies; this task stays todo until it lands.

check 1: Test 144.7 on master 866d8e3fc (CI Fast Tests 46036172173 green): after disabling employees with no unit edited, quality_check_count counts 0 employees checks and statistical_unit_quality lists 0 units for them (public.in_use, h9mhxe); re-enabling restores them (144.8).
