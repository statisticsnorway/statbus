---
id: STATBUS-478
title: >-
  status_custom and status_system views omit NOT NULL columns, so every insert
  through them errors
status: To Do
assignee: []
created_date: '2026-10-08 16:43'
labels:
  - sql
dependencies: []
priority: medium
ordinal: 404204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: an operator can upload custom statuses (and a migration can reload system statuses) through the status_custom / status_system views.

FOUND during STATBUS-477 (observed on statbus_seed at master, rolled-back transaction, 2026-10-08). public.status has assigned_by_default and used_for_counting NOT NULL with no default, but the views status_custom and status_system expose only (code, name, priority), and admin.upsert_status_custom / admin.upsert_status_system insert only (code, name, enabled, custom, updated_at). Observed: INSERT INTO public.status_custom(code, name, priority) VALUES ('q77', 'first', 99) and INSERT INTO public.status_system(code, name, priority) VALUES ('active', 'Active (renamed)', 1) both fail with: null value in column "assigned_by_default" of relation "status" violates not-null constraint. priority is accepted by the view and silently dropped by the upsert. Unlike the silent no-op of STATBUS-477, this path is broken loudly. Nothing in app/, samples/ or test/ writes through these views today.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Inserting through status_custom and status_system stores code, name, priority, assigned_by_default and used_for_counting, or the views are made honestly read-only
- [ ] #2 pg_regress test covers an insert and a corrected re-upload through each view
<!-- AC:END -->
