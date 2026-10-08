---
id: STATBUS-472
title: >-
  Double the activity category name bound to 512 as the interim workaround
  (multi-language deferred)
status: Done
assignee: []
created_date: '2026-10-08 13:12'
updated_date: '2026-10-08 15:10'
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
- [x] #1 activity_category.name is character varying(512), and a label longer than 256 characters, for example a 300-character bilingual label, is accepted.
- [x] #2 Dependent activity_category_* views and upsert functions are checked for varchar(256) casts, and anything found is handled or explicitly recorded.
- [x] #3 The bound and its measurement evidence are documented where the length policy lives, creating that document if none exists.
- [x] #4 A test covers the long-label case at the new bound.
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 The doc/db pairing rides in the SAME commit as the migration, as the pre-commit hook requires.
- [x] #2 The field file or its fixture is imported and its longest label accepted, with the evidence recorded in the ticket.
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

IMPLEMENTATION EVIDENCE (2026-10-08, commit 8e7a9cf5f on master).

CHANGE. Forward migration 20261008132050_statbus_472_activity_category_name_bound_512 sets activity_category.name to character varying(512). PostgreSQL refuses ALTER COLUMN TYPE while views depend on the column, so the migration drops the five dependent views and recreates them with their exact pg_get_viewdef definitions, security_invoker, INSTEAD OF / statement triggers and grants: activity_category_enabled, activity_category_enabled_custom, activity_category_isic_v4, activity_category_nace_v2_1, activity_category_used_def. The derived TABLE activity_category_used (MERGE target of activity_category_used_def) is widened too, because otherwise it would reject a long label at derive time.

DEPENDENTS CHECKED (AC2). Inventory taken from pg_depend on the seed at HEAD. timeline_establishment_def and timeline_legal_unit_def depend on activity_category only for id, path and code, never name, so they are untouched. No function body in the database contains a varchar(256) cast (pg_proc.prosrc scan). The trigger functions admin.upsert_activity_category, admin.activity_category_enabled_upsert_custom, admin.activity_category_enabled_custom_upsert_custom and public.activity_category_used_derive copy NEW.name / source.name uncast, so nothing changes there. Other varchar(256) columns (legal_unit/establishment/enterprise_group/power_group/tag name, web_address, relative_period) are outside this ticket and listed as undecided in the doc.

VERIFICATION. Schema snapshot before and after on statbus_seed: view definitions, options, triggers, grants and ownership are byte-identical, and only the name types moved 256->512 (7 relations). Down then up round trip on a scratch clone: down restores the pre-migration snapshot exactly, and re-up restores the post snapshot exactly. Table filenode is unchanged across the up migration for both activity_category and activity_category_used, so the widening caused no rewrite.

TEST (AC1, AC4). test/sql/132_statbus_472_activity_category_name_bound_512.sql: all 7 relations report varchar(512). A verbatim 13-row excerpt of the field file (sections T and U, including its longest 252-character label; test/data/472_bilingual_activity_categories_excerpt.csv) loads through activity_category_enabled_custom with 13/13 stored unedited. A 300-character bilingual label on S is accepted as a custom override (the system row is kept, disabled). Exactly 512 on R is accepted. 513 on Q fails with SQLSTATE 22001 inside a savepoint, and Q still holds its system name. Local ./dev.sh test 132: ok. Local fast suite: 103/104 ok, and the only failure was 002_generate_mermaid_er_diagram, whose diff is exactly the two expected varchar(256)->varchar(512) lines. That expectation was updated in the same commit and 002 is now ok.

DOC (AC3). doc/text-length-bounds.md (new, no length-policy doc existed) records the bound, the measurements (isic_v4 766 rows max 136 mean 42.1; nace_v2.1 1047 rows max 139 mean 43.6; field file 997 rows max 252 mean 92.9, hand-trimmed, untrimmed T label 158+5+122=285), why 512, the honest failure above it, and where the bound applies.

DOD1. doc/db regenerated by ./dev.sh generate-doc-db (one run, completed, 572 files on disk = 572 tracked, 0 deletions) and committed in the same commit as the migration. 7 files are the name 256->512 change. doc/db/view/public_statistical_unit_def.md also picks up a generator-only alias change ('legal_unit'::statistical_unit_type AS statistical_unit_type, x3, from the current PostgreSQL's view deparser), which is not a schema edit and not a hand edit. person_role_enabled.md showed a stray fence in an earlier interrupted run, but the completed run did not reproduce it, so it was not committed. app/src/lib/database.types.ts is unchanged (TS types carry no varchar length).

DOD2. The full field file ClassificationsSBVer2_ActivityCategoris_TCC.csv (997 rows) was imported on a scratch clone of the test template at HEAD with settings = nace_v2.1, through \copy into activity_category_enabled_custom: 997 rows copied, longest 252, 997/997 stored byte-identical, T stored at 252, and the column is character varying(512).

FOUND ALONG THE WAY, filed as STATBUS-473 (not fixed here): the activity category upserts end in ON CONFLICT ... DO UPDATE ... WHERE activity_category.id = EXCLUDED.id, which never matches, so (a) re-uploading a custom file with corrected labels is silently ignored (INSERT 0 0), and (b) a standard reload through activity_category_nace_v2_1/isic_v4 is followed by delete_stale_activity_category deleting every pre-existing code (observed 1047 -> 1 in a rolled-back transaction). activity_category_enabled's insert trigger reads a nonexistent settings.standard_id. This matters for 472's operator: re-uploading the untrimmed labels over existing custom rows will NOT update them until 473 lands.

CI for 8e7a9cf5f (read via gh run list, not run watch): Go Test, app build & lint, Images, Harness Selftest, Push on master and Notify cloud services all success. Its own Fast Tests run (37788818185) was cancelled by supersession from later pushes. Fast Tests run 37789331297 at descendant 937707b92 (contains 8e7a9cf5f) concluded success, so the suite including test 132 is green on master.

CORRECTIONS (2026-10-08, after landing). (1) doc/text-length-bounds.md listed enterprise_group.name among the remaining 256-bound columns, but that table no longer exists (it is power_group now). Fixed in 3e678f8d0, a doc-only commit. (2) Provenance of the doc/db alias change in public_statistical_unit_def.md was verified: pg_get_viewdef on statbus_seed (PostgreSQL 18.6) itself emits 'legal_unit'::statistical_unit_type AS statistical_unit_type, so it is generator output and not a hand edit. (3) Process note: the local full fast suite (13 min) was more than needed. Test 132 plus the schema-shape tests (002/015/016/101) would have found the one expectation that moved (002), and CI runs the fast suite on push. (4) The doc/db and types freshness stamps under tmp/ were withheld because the tree had uncommitted migrations when the generators ran. They are local only and get written by the next generator run on a clean tree.

RED/GREEN FOR TEST 132 (consequential-test evidence). RED: on a scratch clone of the test template with this migration reverted by its own down.sql (activity_category.name back to character varying(256), the parent-commit schema), the committed test/sql/132 diverges from its expected output (64-line diff). 132.1 reports all 7 relations as character varying(256), and 132.3 fails with 'ERROR: value too long for type character varying(256)' on the 300-character bilingual label, aborting the rest. The 13-row field excerpt (longest 252) still loads at 256, consistent with the operator having hand-trimmed it to fit. GREEN: the same test is ok locally at the 512 schema and ok in CI Fast Tests run 37789331297 (104/104 at 937707b92, a descendant of 8e7a9cf5f).
<!-- SECTION:NOTES:END -->
