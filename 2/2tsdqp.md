---
id: 2tsdqp
title: "Analysis refuses a row that processing would fail"
state: todo
type: bug
priority: "high"
assignee: []
labels: []
group: ""
rank: "zzzzy"
created: 2026-11-21
updated: 2026-11-21
---

## Goal
A row analysis passes as 'use' is written by processing without error; a row that cannot be written is refused in analysis.

## Purpose
Jobs in Norway (Erik, 2026-11-11: 'null value in column name of relation establishment', 'Must have either legal_unit_id or enterprise_id') and in dev (Hedda, owner 2026-11-21) failed in processing after analysis passed them. A failure in processing is late: the user cannot fix it from the analysis view, and part of the job may already be applied.

## Principle
Analysis is the gate: it checks what the chosen merge mode will need from each row against the target as it is, so processing errors mean a bug in analysis, not in the file.

## Relevant details
Cause found for the Norway case (rolled-back prototype 2026-11-21, tmp/slack-todos/modes-bd.log): analyse_legal_unit and analyse_establishment require a name only when the unit is new (legal_unit_id IS NULL); analyse_valid_time checks only valid_from < valid_until. Nothing compares the row's period with the existing unit's life. With MERGE_ENTITY_PATCH (insert_or_update, the seeded default), a row whose period starts before the unit existed inserts that earlier stretch from the file's columns alone, so NOT NULL columns (name; the establishment's legal_unit_id/enterprise_id link) are missing and processing fails. The dev failures are not yet inspected: the owner looks at them (2026-11-21). Related: dbmsxy (update only given columns).

## Depends on

## Acceptance
- [ ] [Owner] Inspects the failing jobs on Norway and dev and records each job id, its error and whether it is this cause, in this task's notes
- [ ] A legal unit update row without a name whose period starts before the unit existed is refused in analysis with a message naming the unit's first date; a SQL test asserts the row's state, action and error
- [ ] The same for an establishment update row without its legal unit link; a SQL test asserts it
- [ ] Each failing dev job, re-run on this fix, either completes or stops in analysis with the reason on the row; the result is recorded here

## Notes
