---
id: STATBUS-479
title: >-
  sector_custom_only upsert error handler crashes on code::jsonb and masks the
  real unique_violation
status: Done
assignee: []
created_date: '2026-10-08 16:43'
updated_date: '2026-10-08 18:18'
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
- [x] #1 A unique_violation in sector_custom_only reports the original constraint, the offending row and the hint
- [x] #2 pg_regress test triggers the violation and asserts the reported message names the key and the path
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Landed locally as 4350bdab6 (migration 20261008175729 plus test 141). NOT PUSHED: held for rabbit's go-ahead, because every push triggers a seed build.
RED (statbus_seed clone with 479 down-migrated, test 141):
- path collision ('domestic'): 22P02 "invalid input syntax for type json", no constraint.
- code collision (a1110/b1110): P0001 with fabricated code 11.10 (stored code is 1110), no constraint, DETAIL "Failed during UPSERT operation".
- Both cases behave the same as the owner and as the admin user.
GREEN (same test, fixed):
- 23505 with constraint sector_path_key or sector_code_enabled_key, the message with (uploaded sector path, name) appended, and the HINT.
- DETAIL is passed through exactly as PostgreSQL emitted it: empty under RLS (admin user), and Key (path)=(domestic) / Key (code)=(1110) as the database owner.
- A valid upload still lands (codes 1110, 2220).
Test 141 captures the error fields as columns (GET STACKED DIAGNOSTICS), so its expected output does not depend on server line numbers.
003_load_errors expected output was updated: it now shows the real 23505 with Key (code)=(1).
Related tests 003 and 133-140 pass locally. doc/db was regenerated once (1 file changed, 0 deletions). The up/down/up round trip is clean.
<!-- SECTION:NOTES:END -->
