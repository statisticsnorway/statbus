---
id: STATBUS-121
title: >-
  pg-foreign-import: ensure BRREG import materializes legal_unit rows for
  foreign (UTLA) power-group members
status: To Do
assignee: []
created_date: '2026-06-30 15:21'
updated_date: '2026-07-03 10:45'
labels:
  - import
  - not-install-upgrade
dependencies: []
ordinal: 107000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: a cross-border power group renders fully.
> BENEFIT: real Norwegian konsern data (Aker-class, many foreign members) stops silently truncating at the border — either we confirm the BRREG import already materializes foreign units, or we catch a data-completeness hole before Norway users query half a group and trust it.
> STAGE: Domain/import.
> COMPLEXITY: mixed — operator investigates the import pipeline with file:line evidence (AC#1); architect/engineer design + build the ingestion if members are dropped. Note: the cross-border sample CSV lives on the King's machine, not the repo.
> DEPENDS ON: nothing.

---

RISK surfaced during the power-group reporting design (DRAFT-001, whose Implementation Notes carry the grounding): a foreign member of a power group is representable ONLY as an ordinary `legal_unit` row — both `legal_relationship` endpoints (`influencing_id`, `influenced_id`) are hard temporal FKs to `legal_unit`, with no external-party escape hatch. `legal_unit` has no country flag of its own; country lives in `location.country_id` and surfaces as `statistical_unit.physical_country_iso_2`.

THE RISK: real BRREG konsern data (e.g. Aker Solutions ASA, org 913748174) contains many "Utenlandsk enhet" (UTLA = foreign) members. If the BRREG import pipeline does NOT materialize `legal_unit` rows for those foreign units, the power group truncates at the Norwegian border — the reporting function (DRAFT-001) is correct, but the group silently shows only its NO holdings and drops the foreign subs. This is an IMPORT/DATA concern, decoupled from the reporting API.

INVESTIGATE FIRST: does the BRREG import (samples/norway/brreg/) materialize `legal_unit` rows for foreign (UTLA) members, or drop them? Report the finding + a proposed ingestion design to the foreman BEFORE implementing anything (per team discipline: diagnosis → design review → build). If dropped, the likely shape is minimal `legal_unit` + a `location` carrying `country_id`, so cross-border groups render fully.

Sample data note: the real cross-border example (`konsernstruktur_913748174.csv`, Aker) lives on the King's machine, NOT in the repo — ask the foreman to obtain it if needed, or reconstruct an equivalent fixture from BRREG open data (data.brreg.no).

Reference: `doc/power-groups.md`; DRAFT-001 (reporting design).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Determine empirically whether the BRREG import materializes legal_unit rows for foreign (UTLA) members or drops them; report the finding to the foreman with file:line evidence from the import pipeline
- [ ] #2 If dropped: proposed ingestion design reviewed by the foreman BEFORE implementation; then implement (minimal legal_unit + location.country_id) so both legal_relationship endpoints resolve
- [ ] #3 A test asserts a cross-border power group renders its foreign members (physical_country_iso_2 != 'NO', domestic=false)
- [ ] #4 doc/power-groups.md notes how foreign/cross-border members are represented
<!-- AC:END -->
