---
id: STATBUS-477
title: >-
  Upsert triggers for classification tables never update: ON CONFLICT ... WHERE
  id = EXCLUDED.id (same defect as STATBUS-473)
status: To Do
assignee: []
created_date: '2026-10-08 16:35'
labels:
  - sql
  - import
dependencies: []
priority: high
ordinal: 403204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: re-uploading a custom legal_form/sector/status/region/... file with corrected names updates them.

FOUND during STATBUS-473. The predicate WHERE <table>.id = EXCLUDED.id makes ON CONFLICT DO UPDATE a no-op whenever id is an identity (EXCLUDED.id is a freshly drawn id). 473 fixed it only for activity_category. Still present in doc/db (28 functions): admin.generate_path_upsert_function and admin.generate_code_upsert_function (the generators), and the generated admin.upsert_{legal_form,sector,status,unit_size,data_source,tag,person_role,power_group_type,legal_rel_type,legal_reorg_type,foreign_participation,region_version}_{custom,system}, admin.upsert_country, admin.legal_form_custom_only_upsert. Each needs the same treatment: the real conflict key, no id predicate, and the row count reporting what was written; check whether any companion stale-delete relies on the no-op the way delete_stale_activity_category did.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 No function in doc/db/function contains the id = EXCLUDED.id predicate
- [ ] #2 pg_regress test re-uploads a corrected custom row for each affected view and asserts the stored name changed and the statement reports the row
- [ ] #3 Any stale-delete paired with these upserts is checked against the fixed upsert (no wall-clock deletion of re-uploaded rows)
<!-- AC:END -->
