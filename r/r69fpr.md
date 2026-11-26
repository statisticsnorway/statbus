---
id: r69fpr
title: "How a unit's counting rule changed: find when birth date stopped deciding"
state: todo
type: feature
priority: ""
assignee: []
labels: []
group: ""
rank: "zzzzzzzzzzzz"
created: 2026-11-26
updated: 2026-11-26
---

## Goal
Find when and how the rule for whether a unit is counted lost its birth/death-date condition, and state today's full rule.

## Purpose
Owner 2026-11-26: the rule used to be clear SQL where valid_from and birth_date both decide (birth/death narrow counting where set), encoded in a test. On jo, establishment 86 (valid from 2023, born 2024-11-01) is counted in 2023, so the rule was changed at some point, likely by an agent, and glossed over in review.

## Principle
Read-only investigation, evidence first: commits, tests, expected outputs and tickets, quoted with SHAs. No code changes. Report what the rule was, what it is, which commit changed it, under which ticket and by which model, and whether a test's expected output was changed to accept it.

## Details
Inputs that decide counting today, to enumerate: statistical_unit.used_for_counting and how it is derived; status (status.used_for_counting / include_unit_in_reports); valid_from/valid_until; birth_date/death_date; primary flags; legal unit and enterprise inclusion (included_*_ids, excluded_*_ids); power groups. Search: git log -S'birth_date' and -G'used_for_counting' over migrations/ and test/; doc/db for the current definitions; tests 306, 309, 310, 410 and any named for births/deaths or counting. Compare jo's release with master.

## Depends on

## Acceptance
- [ ] A note on this task names the commit(s) that changed the birth/death condition, with the before and after SQL, the ticket and model trailer, and the test whose expected output changed with it
- [ ] A note states today's complete counting rule as the code implements it, input by input, with the defining function names
- [ ] [Owner] reads the findings and decides whether to restore the old rule; recorded in Notes

## Notes
