---
id: rws25b
title: "User-made reports: decide whether a report is just a saved query"
state: todo
type: spike
priority: ""
assignee: []
labels: []
created: 2026-11-18
updated: 2026-11-18
---

## Goal
StatBus knows whether, and how, people like Erik can add their own reports that link into StatBus, instead of writing separate front ends; the answer may be that a user-made report is just a saved query.

## Purpose
Erik built a standalone page (PR #328) because the comparison seemed impossible in a query. With computed fields (the existence_from pattern) many reports become a URL against the REST API, which a person or an AI can write. The owner wonders whether a user-made report is just a query (2026-11-18).

## Principle
Investigate before building: the deliverable is a recommendation for the owner, with what is possible in principle and what it would take. Safety first: whatever a user adds runs with that user's own rights (row-level security), never more.

## Relevant details
Building blocks today: PostgREST filters and computed fields on statistical_unit (existence_from/until, 16 computed fields), the search page's URL filters, the session's JSON web token. Open questions: is a saved search URL with a name enough; can a user add a computed field (no: that is a migration, so new comparisons stay built in); how a saved query appears beside the built-in checks (configurable reports task).

## Depends on

## Acceptance
- [ ] A note in this task lists what a user can already express as a URL on /rest/statistical_unit and the search page, with one worked example per kind (filter, computed field, count)
- [ ] [Owner] Decides from the recommendation: saved queries, built-in checks only, or something else; the answer is recorded in the notes and, if it is to be built, becomes its own task

## Notes
