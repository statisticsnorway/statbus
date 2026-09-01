---
id: STATBUS-121
title: >-
  pg-foreign-import: ensure BRREG import materializes legal_unit rows for
  foreign (UTLA) power-group members
status: Done
assignee: []
created_date: '2026-06-30 15:21'
updated_date: '2026-07-13 13:16'
labels:
  - import
  - not-install-upgrade
dependencies: []
modified_files:
  - test/sql/403_cross_border_power_group.sql
  - test/expected/403_cross_border_power_group.out
  - samples/norway/legal_unit/konsern-enheter.csv
  - samples/norway/legal_relationship/konsern-roller.csv
  - samples/norway/brreg/fetch-konsern-fixture.py
  - doc/power-groups.md
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
- [x] #1 Determine empirically whether the BRREG import materializes legal_unit rows for foreign (UTLA) members or drops them; report the finding to the foreman with file:line evidence from the import pipeline
- [x] #2 If dropped: proposed ingestion design reviewed by the foreman BEFORE implementation; then implement (minimal legal_unit + location.country_id) so both legal_relationship endpoints resolve
- [x] #3 A test asserts a cross-border power group renders its foreign members (physical_country_iso_2 != 'NO', domestic=false)
- [x] #4 doc/power-groups.md notes how foreign/cross-border members are represented
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-13 13:14
---
**AC#1 answered empirically + statically. AC#2: no new ingestion code needed — the drop is legitimate tier-1 validation; the fix is data completeness in the enheter feed.**

**Static evidence (file:line):** `import.analyse_legal_relationship` (doc/db/function) resolves each endpoint tax_ident via `external_ident → legal_unit` LEFT JOIN (lines 62-71/81-90). An endpoint with no existing legal_unit is flagged `unknown_influencing`/`unknown_influenced` (lines 128-129) → `state='error'`, `action='skip'`, message "No legal unit found for influencing_tax_ident" (lines 159-173, 191/193). So the legal_relationship step does NOT materialize foreign endpoints — it only resolves them. This is correct: the relationship step cannot invent a legal_unit.

**Where foreign members DO get materialized + their country:** the ordinary hovedenhet (enheter) import maps `forretningsadresse.landkode → physical_country_iso_2` (create-import-definition-hovedenhet-2024.sql line 68). A UTLA enhet record carries its foreign country there (verified live: AKER SOLUTIONS KOREA 914636191 → forretningsadresse.landkode=KR). So a cross-border group renders fully IFF the foreign members are present in the enheter feed — which real BRREG konsern data provides. No special ingestion path required.

**Empirical proof (test/sql/403_cross_border_power_group.sql):** loads the real Aker Solutions ASA konsern (org 913748174) through the SAME pipeline as brreg-import-selection.sh — 23 members, 14 foreign across 9 countries (CA, CN×3, CY, FI, GB×4, KR, MY, TZ, US), 9 Norwegian. Result: both import jobs finished, 23/23 LUs + 22/22 edges, ZERO error rows. All 14 foreign members render as legal_units with physical_country_iso_2 ≠ 'NO' and domestic=false. Power group PG0001 spans all 23 (9 domestic + 14 foreign) — no truncation at the border.

**Fixtures (committed, hermetic):** samples/norway/legal_unit/konsern-enheter.csv (23), samples/norway/legal_relationship/konsern-roller.csv (22 HFOR edges), generated by samples/norway/brreg/fetch-konsern-fixture.py from a BRREG konsernstruktur CSV. AC#4: doc/power-groups.md gains a 'Cross-border members (foreign / UTLA)' subsection.

Stability being confirmed (deterministic-by-construction: shared setup includes are output-suppressed, only explicit assertions print). Commit + status→Done to follow.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
DONE — cross-border power group renders fully, proven end-to-end. Commit f536b38e2 on master (pushed).

FINDING (AC#1, empirical + static file:line): the legal_relationship import step (import.analyse_legal_relationship) does NOT materialize endpoints — it only resolves them via external_ident -> legal_unit (lines 62-71/81-90). An endpoint tax_ident with no existing legal_unit is flagged unknown_influencing/unknown_influenced (lines 128-129) -> state='error', action='skip' (lines 159-173). Correct tier-1 validation: the relationship step cannot invent a legal_unit.

RESOLUTION (AC#2): no new ingestion code needed. Foreign (UTLA) members are materialized FIRST by the ordinary hovedenhet (enheter) import, which maps forretningsadresse.landkode -> physical_country_iso_2 (create-import-definition-hovedenhet-2024.sql line 68). A UTLA enhet record carries its foreign country there (verified live: AKER SOLUTIONS KOREA 914636191 -> KR). Cross-border groups render fully iff the foreign members are present in the enheter feed — which real BRREG konsern data provides. The requirement is data completeness, not a special path.

PROOF (AC#3): test/sql/403_cross_border_power_group.sql loads the real Aker Solutions ASA konsern (org 913748174) through the same pipeline as brreg-import-selection.sh — 23 members, 14 foreign across 9 countries (CA, CN×3, CY, FI, GB×4, KR, MY, TZ, US), 9 Norwegian. Both jobs finish, 23/23 LUs + 22/22 edges, ZERO error rows. All 14 foreign members render as legal_units with physical_country_iso_2 != 'NO' and domestic=false. Power group PG0001 spans all 23 (9 domestic + 14 foreign) — no truncation at the border. Green + deterministic across 4 runs (shared setup includes output-suppressed so the expected asserts only this test's own queries).

DOC (AC#4): doc/power-groups.md gains a 'Cross-border members (foreign / UTLA)' subsection.

FIXTURES (hermetic, committed): samples/norway/legal_unit/konsern-enheter.csv (23 members), samples/norway/legal_relationship/konsern-roller.csv (22 HFOR edges). Generator: samples/norway/brreg/fetch-konsern-fixture.py (run-once, regenerates from a BRREG konsernstruktur CSV; tests load the committed CSVs, no network).
<!-- SECTION:FINAL_SUMMARY:END -->
