---
id: STATBUS-472
title: >-
  Double the activity category name bound to 512 as the interim workaround
  (multi-language deferred)
status: In Progress
assignee: []
created_date: '2026-10-08 13:12'
updated_date: '2026-10-08 13:14'
labels:
  - sql
  - import
dependencies: []
priority: high
ordinal: 398204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: real classification labels import unedited, and the bound is a deliberate, documented number with an honest failure above it. Double activity_category.name from character varying(256) to character varying(512). That is the whole change.

WHY. Real bilingual labels reach 252 characters in the field file (ClassificationsSBVer2_ActivityCategoris_TCC.csv, 997 rows, path/name, already hand-trimmed by the operator to fit), while the longest single-language official label we hold is 136 (ISIC4, 766 rows). In PostgreSQL, character varying(n) is a length CHECK, not a storage layout, so doubling it costs nothing in row size or disk. The multi-language design is deferred; a longer text is the interim workaround, and how an operator slices several languages into it is their business. That discussion is preserved in the notes below as history.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 activity_category.name is character varying(512), and a label longer than 256 characters, for example a 300-character bilingual label, is accepted.
- [ ] #2 Dependent activity_category_* views and upsert functions are checked for varchar(256) casts, and anything found is handled or explicitly recorded.
- [ ] #3 The bound and its measurement evidence are documented where the length policy lives, creating that document if none exists.
- [ ] #4 A test covers the long-label case at the new bound.
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 The doc/db pairing rides in the SAME commit as the migration, as the pre-commit hook requires.
- [ ] #2 The field file or its fixture is imported and its longest label accepted, with the evidence recorded in the ticket.
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
HISTORIC RECORD, carried over from STATBUS-471 which is archived on the owner's instruction (keep ONE ticket for this work and hold the multi-language discussion here as history).

## Description
<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: one name per language. A user-provided (custom) activity category overrides the system-provided one for the same path and carries the LOCAL-language name; the system entry keeps the OFFICIAL English name; the interface shows the local name with a marker that reveals the official English label, taken from the replaced non-custom entry of the same path. Nobody concatenates two languages into one name, and the length bound does not move.

WHY THE BOUND RAISE WAS REJECTED (owner decision 2026-10-08). Raising varchar(256) treats only the symptom and actively invites abuse: it lets multiple languages be crammed into one field, which breaks display, sorting, matching and translation quality. The file that triggered this is exactly that abuse: ClassificationsSBVer2_ActivityCategoris_TCC.csv concatenates the Turkish label, a '---' separator, then the English label (its longest is 252 characters, mean 92, and the operator had already hand-trimmed it to fit 256). The official English label for the same code is at most 136 characters in the ISIC4 data we hold, so nothing about one-language names needs a bigger bound.

THE DESIGN.
1. Model. Activity categories belong to an activity category type, and are either SYSTEM-provided or USER-provided (custom). The data model and the interface already distinguish them: the upload table is activity_category_enabled_custom and the list has a Custom column.
2. Override. A custom row overrides the system row of the same path. The override is the local-language name for that code; the system row keeps the official English name.
3. Alternate label. The official English label for an overridden code comes from the REPLACED non-custom entry of the same path, resolved rather than copied, so no concatenation and no duplication are needed.
4. Interface. Show the local name by default, with a clear, discoverable marker or affordance that reveals the official English name when wanted. The Activity Categories list is the minimum; anywhere a name is shown should behave the same.
5. Identity and search. The official English name stays the stable identity for matching and search; a search should match either the local or the official name for an overridden code.
6. Import and template. The custom CSV carries LOCAL names only. The template and its guidance must say so, and a value that looks like two languages in one field (for example joined by '---') is detected and flagged with an actionable message rather than silently stored. This is the same family as the getting-started upload work in STATBUS-470.
7. The 256 bound stays as it is. The rejected alternative is recorded above with its reason.

OPEN QUESTIONS FOR THE OWNER BEFORE IMPLEMENTATION.
(a) Should a custom row store only the local name, with the official English resolved by path, or store both? The sketch suggests resolved-by-path.
(b) Where exactly should the marker appear beyond the Activity Categories list: search results, unit detail pages, pickers, import preview?
(c) Should a concatenated value be rejected outright or accepted with a warning?
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A custom activity category carries a single-language local name while the system entry of the same path keeps the official English name, and no name field in the documented flow holds two languages concatenated.
- [ ] #2 The interface shows the local name by default with a visible marker, and reveals the official English name on demand; the marker is discoverable and works at minimum in the Activity Categories list.
- [ ] #3 The official English label is resolved from the replaced non-custom entry of the same path rather than duplicated into the custom row, verified against the field's file.
- [ ] #4 Search and matching match both the local and the official name for an overridden code.
- [ ] #5 The import template and its guidance state that custom rows carry local-language names and that the official English name comes from the system entry, and they do not invite concatenation.
- [ ] #6 A value that looks like two languages in one field, for example joined by '---', is detected and flagged with an actionable message rather than silently stored.
- [ ] #7 The 256 bound is unchanged, and the rejected bound raise is recorded in the ticket with its reason.
<!-- AC:END -->

## Implementation Notes
 <!-- SECTION:NOTES:BEGIN -->
OWNER DECISION 2026-10-08: this multi-language design is DEFERRED and returned to To Do with all notes kept. The owner's reasoning: too many things on the plate, and the simplest workaround is to allow a longer text and let the operator slice multiple languages however they want until we support the language model properly. The immediate work, doubling the name bound as the interim workaround, is tracked separately in statbus-472. Keep everything here: the design, the schema answer (one table, self-join on standard_id and path, the original row already retained disabled by the upsert), the open questions, and the rejected-approach reasoning, for the later discussion about multi-language support.
 <!-- SECTION:NOTES:END -->
<!-- SECTION:NOTES:END -->
