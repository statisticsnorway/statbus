---
id: STATBUS-117
title: >-
  pg-foreign-import: ensure BRREG import materializes legal_unit rows for
  foreign (UTLA) power-group members
status: To Do
assignee: []
created_date: '2026-06-30 15:21'
labels:
  - power-group
  - import
  - data
dependencies: []
ordinal: 107000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
RISK surfaced during the power-group reporting design (DRAFT-001). pg-engineer confirmed: a foreign member of a power group is representable ONLY as an ordinary `legal_unit` row — both `legal_relationship` endpoints (`influencing_id`, `influenced_id`) are hard temporal FKs to `legal_unit`, with no external-party escape hatch. `legal_unit` has no country flag of its own; country lives in `location.country_id` and surfaces as `statistical_unit.physical_country_iso_2`.

THE RISK: real BRREG konsern data (e.g. Aker Solutions ASA, org 913748174) contains many "Utenlandsk enhet" (UTLA = foreign) members. If the BRREG import pipeline does NOT materialize `legal_unit` rows for those foreign units, the power group truncates at the Norwegian border — the reporting function (DRAFT-001) is correct, but the group silently shows only its NO holdings and drops the foreign subs. This is an IMPORT/DATA concern, decoupled from the reporting API.

INVESTIGATE: does the BRREG import (samples/norway/brreg/) materialize `legal_unit` rows for foreign (UTLA) members, or drop them? If dropped, design + implement foreign-member ingestion (minimal `legal_unit` + a `location` carrying `country_id`), so cross-border groups render fully.

Reference: `doc/power-groups.md`; DRAFT-001 (reporting design); real data `~/Downloads/konsernstruktur_913748174.csv` (Aker, cross-border).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Determine empirically whether the BRREG import materializes legal_unit rows for foreign (UTLA) members or drops them
- [ ] #2 If dropped: design + implement foreign-member ingestion (minimal legal_unit + location.country_id) so both legal_relationship endpoints resolve
- [ ] #3 Add a test asserting a cross-border power group renders its foreign members (physical_country_iso_2 != 'NO', domestic=false)
- [ ] #4 doc/power-groups.md notes how foreign/cross-border members are represented
<!-- AC:END -->
