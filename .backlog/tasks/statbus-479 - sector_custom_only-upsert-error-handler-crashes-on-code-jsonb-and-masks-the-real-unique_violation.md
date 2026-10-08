---
id: STATBUS-479
title: >-
  sector_custom_only upsert error handler crashes on code::jsonb and masks the
  real unique_violation
status: To Do
assignee: []
created_date: '2026-10-08 16:43'
labels:
  - sql
  - import
dependencies: []
priority: medium
ordinal: 405204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: when a custom sector upload violates a unique key, the operator sees which row and which key, not a JSON cast error.

FOUND during STATBUS-477 (observed on statbus_seed at master, rolled-back transaction, 2026-10-08). admin.sector_custom_only_upsert wraps its INSERT ... ON CONFLICT in BEGIN ... EXCEPTION WHEN unique_violation, and the handler builds a diagnostic with data := jsonb_set(data, '{code}', code::jsonb, true) where code is a plain varchar like '1110' or ''. Casting a non-JSON string to jsonb raises, so the handler itself fails. Observed: INSERT INTO public.sector_custom_only(path, name) VALUES ('domestic', 'Domestic (custom)') (a custom override of an existing system path, which collides with sector_path_key UNIQUE(path)) reports: invalid input syntax for type json. The real error (duplicate key on sector_path_key for path 'domestic') and the HINT the handler meant to give are lost. The getting-started upload page posts to this view, so an operator sees the JSON error.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A unique_violation in sector_custom_only reports the original constraint, the offending row and the hint
- [ ] #2 pg_regress test triggers the violation and asserts the reported message names the key and the path
<!-- AC:END -->
