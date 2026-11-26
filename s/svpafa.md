---
id: svpafa
title: "Codes are CSV column names: DB CHECK, and admin forms name fields to fix"
state: "doing"
type: feature
priority: ""
assignee: ["hamster"]
labels: []
group: ""
rank: "zzzzzzzzzzzs"
created: 2026-11-26
updated: 2026-11-26
doing_since: "2026-11-26T10:28"
stage: "active"
model: "claude-opus-5-5"
branch: "master"
worktree: "/Users/jhf/ssb/statbus"
---

## Goal
The database refuses non ^[a-z0-9_]+$ codes, and refused admin forms name the fields to fix.

## Purpose
Codes are CSV column names and import mapping targets; the form rule (Hedda) must hold in the database too. The generic message tells the user nothing.

## Principle
Check existing data before constraining; never silently rewrite codes. Keep field-level errors. Leave the code: zod lines alone for Hedda's rebase.

## Details
Owner decision 2026-11-26. Columns: stat_definition.code, external_ident_type.code.

## Depends on

## Acceptance
- [x] SQL test RED before and GREEN after migration
- [x] Migration with up/down and COMMENT ON each constraint; types and doc/db regenerated
- [x] No 'Failed to parse form data' in app; browser shows useful messages on empty Add statistical variable
- [ ] tsc, lint, jest, SQL fast suite pass; pushed; CI checked

## Notes


landed 8096787 on master 2026-11-26: db: codes are CSV column names, CHECK ^[a-z0-9_]+$ on stat_definition and…
landed ba23420 on master 2026-11-26: app: a refused admin form names the fields to fix, not 'Failed to parse form…
check 1: test 412: RED tmp/test-412-red.out accepts 'Demo Variable'; GREEN after 20261126094102 refuses it via the CHECK (809678734)
check 2: migration 20261126094102_codes_are_csv_column_names up/down with COMMENT ON each constraint; types and doc/db regenerated, no deletions (809678734)
check 3: no 'parse form data' left in app/src; browser :3019 empty Add statistical variable shows only Name/Code/Type/Priority is required, no alert, no record created (ba234201c)
## History
- 2026-11-26T10:28 todo -> doing/active (take)
