---
id: svpafa
title: "Codes are CSV column names: DB CHECK, and admin forms name fields to fix"
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
The database refuses non ^[a-z0-9_]+$ codes, and refused admin forms name the fields to fix.

## Purpose
Codes are CSV column names and import mapping targets; the form rule (Hedda) must hold in the database too. The generic message tells the user nothing.

## Principle
Check existing data before constraining; never silently rewrite codes. Keep field-level errors. Leave the code: zod lines alone for Hedda's rebase.

## Details
Owner decision 2026-11-26. Columns: stat_definition.code, external_ident_type.code.

## Depends on

## Acceptance
- [ ] SQL test RED before and GREEN after migration
- [ ] Migration with up/down and COMMENT ON each constraint; types and doc/db regenerated
- [ ] No 'Failed to parse form data' in app; browser shows useful messages on empty Add statistical variable
- [ ] tsc, lint, jest, SQL fast suite pass; pushed; CI checked

## Notes
