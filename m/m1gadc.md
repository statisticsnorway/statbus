---
id: m1gadc
title: "Systematic browser tests of the app's interaction"
state: todo
type: feature
priority: ""
assignee: []
labels: []
group: ""
rank: "00000000000o"
created: 2026-11-23
updated: 2026-11-23
---

## Goal
The app's main pages and interactions are covered by browser tests that run in CI against a seeded database.

## Purpose
Interaction is checked today by hand in a driven browser; a test that covers one detail of one page brings little, and the owner wants browser tests only if they cover most of the app systematically.

## Principle
One suite for the whole app, written page by page against the real app and database, run in CI; no per-feature browser tests outside it.

## Details
Owner 2026-11-23 on 5yxn4w: Playwright for a few details of /regions brings little; if browser tests, then systematic tests of almost the entire app, in their own ticket. @playwright/test is in app/pnpm-lock.yaml but the app has no suite (doc/design/units-on-map.md, 5nq78t check 2 asked for one too). Candidate first pages: dashboard, search with filters, unit pages and their edit forms, regions list and map, import upload.

## Depends on

## Acceptance
- [ ] A Playwright suite runs in CI against a seeded database and passes on master
- [ ] It covers the dashboard, search with filters, each unit type's pages and edit forms, and the regions list and map; a list in the suite's README maps each page to its tests

## Notes
