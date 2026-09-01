---
id: STATBUS-038
title: >-
  branch-keep-pending: review the 11 keep-pending branches one-by-one with the
  King
status: Done
assignee: []
created_date: '2026-06-12 08:21'
updated_date: '2026-07-06 15:59'
labels:
  - git-hygiene
  - not-install-upgrade
dependencies: []
references:
  - STATBUS-035
priority: low
ordinal: 38000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Companion to STATBUS-035 (the 13 confident-safe deletes, approved + executed). These 11 branches each carry unique unmerged commits OR are a deliberate archive / load-bearing fallback — each needs ONE owner answer before any decision. The King wants to go over them together, one-by-one, later (NOT a foreman solo call).

THE 11, each with its single open question:
1. db-snapshot — legacy seed-fallback name in shipped binaries (shadowed by live db-seed). Q: confirm no shipped binary relies on the db-snapshot fallback before retiring.
2. debug/archive-partial-at-final-rootcause (3 unique commits, recent campaign debug). Q: are the root-cause findings captured in master/doc/backlog?
3. engineer/image-distribution-design (1 unique commit = a draft design doc "for user review"; the implementation shipped). Q: King — still want the draft doc?
4. engineer/layer2-recovery-flag (4 unique commits; `--recovery=auto` is NOT in master CLI). Q: feature still wanted, or superseded by what shipped?
5. test/upgrade-resume-new-scenarios (2 unique commits incl. scenario 30 `kill-mid-rsync-resumable`, NOT in master). Q: merge scenario 30 or is it superseded?
6. feat/statistical-variables-over-time-chart (hhssb's UI WIP, 2 unique commits). Q: owner (hhssb) — still active?
7. feature/pg-oauth (pg OAuth prototype, 4 unique commits, ~5mo old). Q: owner — abandon?
8. feature/pgadmin (8 unique commits, ~3mo old). Q: owner — still wanted?
9. fix-custom-scripts (Erik Søberg's Norway custom scripts, 3 unique commits). Q: owner — deployed-relevant?
10. legacy-dotnet-3-ms-sql (deliberately-named legacy archive, 0-ahead). Q: King — keep as historical marker or delete?
11. legacy-dotnet-7-postgresql (same deliberate `legacy-` archive marker). Q: King — keep or delete?

Owners to consult: hhssb (#6), Erik Søberg (#9), King (the rest + the two legacy-dotnet archives). Full per-branch evidence (ahead/behind counts, last commit) is in STATBUS-035's analysis.

PROCESS: go through one-by-one with the King; record each verdict (keep + rationale / delete / ask-owner-then-decide); foreman executes any approved deletes; owner-gated ones wait on the owner.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each of the 11 branches has a recorded verdict (keep+rationale / delete / pending-owner) after review with the King
- [ ] #2 Owner-gated branches (#6 hhssb, #9 Erik Søberg) routed to their owners; their answers recorded
- [ ] #3 Approved deletes executed by the foreman; db-seed and all deploy pointers remain untouched
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
MERGED into STATBUS-035: same activity — one branch-hygiene sitting with the King (035 = the 13 approved deletes; 038 = the 11 keep-pending walk).
<!-- SECTION:FINAL_SUMMARY:END -->
