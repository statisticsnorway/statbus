---
id: STATBUS-473
title: >-
  Activity category upserts never update an existing row: custom re-upload
  silently ignored, standard reload wipes the standard
status: Done
assignee: []
created_date: '2026-10-08 13:43'
updated_date: '2026-10-08 16:35'
labels:
  - sql
  - import
dependencies: []
priority: high
ordinal: 399204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: uploading an activity category file twice, with corrected labels, updates the labels; reloading a standard keeps every code it still contains.

FOUND while doing STATBUS-472 (inventory of the upsert trigger functions behind the activity_category_* views), observed on statbus_seed at 20261008132050, all in rolled-back transactions.

1. admin.activity_category_enabled_custom_upsert_custom (the custom CSV upload target, activity_category_enabled_custom) and admin.upsert_activity_category (behind activity_category_isic_v4 / activity_category_nace_v2_1) end in ON CONFLICT ... DO UPDATE ... WHERE activity_category.id = EXCLUDED.id. id is GENERATED ALWAYS AS IDENTITY, so EXCLUDED.id is the freshly drawn id and never equals the existing row's id: the DO UPDATE never fires (INSERT 0 0). Observed: uploading path Q9 'first' then Q9 'second (corrected)' leaves name 'first'. An operator who re-uploads a custom file with corrected labels (exactly the STATBUS-472 situation: the field file was hand-trimmed to fit 256 and will be re-uploaded untrimmed) sees success and no change. The clause has been there since 3564061ee (2024-11-12).

2. Consequence for standards: admin.delete_stale_activity_category (AFTER INSERT FOR EACH STATEMENT) deletes every row of the standard whose updated_at < statement_timestamp(). Because the upsert never touches existing rows, a reload of a standard deletes every pre-existing code. Observed: INSERT INTO activity_category_nace_v2_1 VALUES ('A',...),('A.99','New division') took nace_v2.1 from 1047 rows to 1. activity.category_id references activity_category ON DELETE CASCADE, so on a box with data this would cascade-delete activities. Reachable only by a migration or seed that reloads a standard (users have SELECT only on those views), so no live path today, but the next standard refresh would hit it.

3. admin.activity_category_enabled_upsert_custom (INSTEAD OF INSERT on activity_category_enabled) reads SELECT standard_id FROM public.settings, a column that does not exist (it is activity_category_standard_id), and ends in ON CONFLICT (standard_id, path), which matches no unique constraint (the key is (standard_id, path, enabled)). Every insert through that view errors. Nothing in app/, cli/ or test/ inserts through it; either fix it or drop the trigger so the view is honestly read-only.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Re-uploading a custom activity category with a changed name updates the stored name, and the upload reports it.
- [x] #2 Reloading a standard through activity_category_isic_v4 / activity_category_nace_v2_1 keeps every code present in the reload and updates its name; only codes absent from the reload are removed.
- [x] #3 Inserting through activity_category_enabled either works against the real settings column and constraint, or the view no longer accepts inserts.
- [x] #4 pg_regress test covers re-upload, standard reload, and the activity_category_enabled insert path, including a box with activities referencing the categories.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
COORDINATOR TRIAGE DECISION (2026-10-08), so the fix does not have to be rediscovered. The three findings share one shape and are fixed in one migration plus one pg_regress test.

1. ON CONFLICT ... DO UPDATE ... WHERE activity_category.id = EXCLUDED.id can never fire, because activity_category.id is GENERATED ALWAYS AS IDENTITY, so EXCLUDED.id is the freshly drawn identity and never equals the stored row's id. The row is therefore always inserted and never updated (INSERT 0 0 on the update path). Fix: drop the bogus WHERE predicate and conflict on the real key of the target view (standard_id, path), which is what the custom upload target actually keys on; keep the update restricted to the columns the upload addresses (name, at least), and make the custom path report how many rows it updated so a silent no-op cannot recur.

2. admin.delete_stale_activity_category deletes every row of the standard whose updated_at is older than statement_timestamp(), which after fix 1 becomes genuinely destructive: a reload that does not touch existing codes would delete all of them, and activity.category_id references activity_category ON DELETE CASCADE. Fix: delete only rows of that standard that the current statement did NOT address, i.e. compute the stale set as the complement of the codes present in the statement, never by wall-clock comparison alone.

3. admin.activity_category_enabled_upsert_custom (INSTEAD OF INSERT on activity_category_enabled) reads settings.standard_id, which does not exist (the column is activity_category_standard_id), and conflicts on (standard_id, path), which matches no unique constraint (it is (standard_id, path, enabled)). Fix it against the real column and the real constraint (AC3 allows dropping the trigger instead, but a view that silently refuses inserts is a trap; fix it). While in the file, inventory every trigger function behind the activity_category_* views for the same id-in-the-WHERE pattern and fix any other instance in the same migration.

Test (AC4): pg_regress 133 covering a custom re-upload with a changed label, a standard reload that keeps the codes it still contains and removes only the absent ones, and an insert through activity_category_enabled, all against a database that has activities referencing the categories.

IMPLEMENTATION + EVIDENCE (2026-10-08, landed as c184c9cb3)

Migration: migrations/20261008143938_statbus_473_activity_category_upserts_update_existing_rows.{up,down}.sql. Built from \sf dumps (taken from statbus_seed at 20261008132050) of the five trigger functions; the down migration is those dumps verbatim plus DROP of the new constraint.
- (standard_id, path, custom) is now UNIQUE (activity_category_standard_id_path_custom_key). Before adding it, a deterministic dedupe: canonical row per key = enabled first, then lowest id; activity, activity_category_access and child parent_id references move to the canonical row, the redundant rows are deleted and the count is RAISE NOTICEd. Decided only by the rows themselves, no MAX/COUNT over current state.
- admin.upsert_activity_category, admin.activity_category_enabled_custom_upsert_custom, admin.activity_category_enabled_upsert_custom: ON CONFLICT (standard_id, path, custom) with no id predicate; INSTEAD OF triggers RETURN NEW, so INSERT/COPY report the written row (custom re-upload now reports INSERT 0 1 / COPY 1 instead of INSERT 0 0).
- admin.delete_stale_activity_category: deletes the system codes of the standard that the statement did NOT address (recorded per row in pg_temp.activity_category_addressed by the upsert, since view triggers cannot have transition tables); never wall clock, never custom overrides; an empty load deletes nothing.
- admin.activity_category_enabled_upsert_custom: reads settings.activity_category_standard_id; the parent column is parent_path (the view has no parent_code).
- Inventory of the triggers behind activity_category_* views: the id = EXCLUDED.id predicate was in all three upsert functions, now all fixed. Found while here: public.lookup_parent_and_derive_code looked parents up across ALL standards (654 nace_v2.1 rows pointed at isic_v4 parents on the seed, V.99 had no parent); scoped to own standard (enabled first, disabled while public.reset swaps), links repaired by re-deriving (UPDATE ... SET path = path WHERE level > 1). Same id = EXCLUDED.id pattern also exists outside this scope (admin.upsert_legal_form_custom, upsert_sector_custom, generate_path_upsert_function, ...): NOT changed here; it needs a follow-up ticket.

Test 133 (test/sql/133_statbus_473_activity_category_upsert_updates.sql), with activities referencing a standard code, a custom code and a code absent from the reload:
- RED, before the fix: database statbus_473_scratch, my own clone of statbus_seed taken at 20261008132050 (master, before 473 was applied anywhere), run 16:56 local, before any shared database had 473. Re-upload: RETURNING 0 rows, name stays 'Plant propagation (first upload)'; standard reload: INSERT 0 0, kept_with_same_id 0, removed 1047 of 1047, custom 0 kept, all 3 activities cascade-deleted; activity_category_enabled insert: ERROR column "standard_id" does not exist.
- GREEN, after: the same scratch db with the up migration applied; then pg_regress `./dev.sh test 133` on the template from statbus_seed = master + 473: ok. Re-upload updates (same id as the activity), COPY 1 updates; reload keeps 1045 codes with the same ids, removes only A.01.7 and A.01.7.0, keeps the custom override, kept activities survive, the one on A.01.7 cascades; activity_category_enabled insert + re-insert update; 0 cross-standard parent links, 0 orphans.
- Down/up/down/up round trip clean on statbus_473_scratch.

Migration dedupe proof (rabbit's review), clones statbus_473_dedupe_red / _green of statbus_473_scratch (pre-fix), duplicates manufactured: A.01.1 system (enabled 768 + disabled 2870) and A.01.2.9 custom (disabled 2871 lower id + enabled 2872), with activities, an access grant and a child link on the redundant rows.
- RED (migration as first written, ADD CONSTRAINT without dedupe): ERROR could not create unique index ... Key (2, A.01.2.9, t) is duplicated; the migration aborts.
- GREEN (final migration): completes, NOTICE removed 2 redundant rows; 0 duplicate keys; kept 768 and 2872 (enabled first, not lowest id); both activities, the access grant and the child A.01.1.1 now point at the canonical rows; a fresh duplicate INSERT is rejected by activity_category_standard_id_path_custom_key.

Suite: ./dev.sh test fast on master+473: everything passes except 015 and 350, both caused by 461's uncommitted work in the shared tree (test/sql/015 edit, test 350), not by 473. Expected changes accepted in 105/305: V.99 now has parent V; the reset 'getting-started' changed_children_count goes from 73 to 726 because the custom overrides' children are now in their own standard.

doc/db: regenerated once by ./dev.sh generate-doc-db, which reads statbus_seed (NOT statbus_local, which is an old February dump with 199 migrations); the seed was master + 473 only (461's migration was parked by its worker). 0 added, 0 deleted, 6 modified (the 5 functions + public_activity_category table), 572 on disk = 572 tracked. Committed with an explicit pathspec.

CLOSE-OUT EVIDENCE (2026-10-08)

CI: on c184c9cb3 itself, Images, Go Test, Harness Selftest, app build & lint, CodeQL and Notify cloud services all succeeded. Fast Tests run 37803944461 was CANCELLED twice (attempt 1 at test 38, attempt 2 at test 12), both times by the Fast Tests concurrency group as later master pushes superseded it; it was never a failure. Accepted evidence (same model as 472): Fast Tests run 37807241872, run-name "exercised-sha=8e4d11249eb0f9757d46d5fc7eefc9237ef69276", concluded SUCCESS with "All 106 tests passed", including ok 133_statbus_473_activity_category_upsert_updates, ok 105, ok 305, ok 015. 8e4d11249 is a descendant of c184c9cb3 (git merge-base --is-ancestor c184c9cb3 8e4d11249 = true), so c184c9cb3 is contained in the tree it exercised. https://github.com/statisticsnorway/statbus/actions/runs/37807241872

Local 015 failure in tmp/473/test-fast2.log explained: that run used the template cloned from statbus_seed = master + 473 only (461 parked). 015's only diff was one paragraph from 461's then-uncommitted edit to test/sql/015 (a literal in the test SQL), so it was not 473's doing and doc/data-model.md was not stale for 473. 015 is ok in the descendant CI run.

reset changed_children_count 73 -> 726, decomposed (test 305's scenario: samples/norway/getting-started.sql then public.reset 'getting-started'. Two clones of statbus_seed that I made myself: statbus_473_reset_without (473 down-migrated, parent links re-derived with the pre-473 trigger, which reproduces master: 654 nace->isic links) and statbus_473_reset_with (master + 473).
- Both: 2 standards (isic_v4 766 rows, nace_v2.1 2858 incl. overrides); 424 non-custom paths exist in both; reset deletes 1811 custom enabled nace rows.
- WITHOUT 473: non-custom children by parent: nace->isic 654, nace->nace system 298, nace->nace custom 73 (all at parent level 3). The 73 are the only nace children whose same-path lookup happened to hit nace before isic. After reset: 654 cross-standard links, 9 orphans.
- WITH 473: nace->isic 0, nace->nace system 299, nace->nace custom 726 (parent level 1: 86, level 2: 188, level 3: 452). The 726 = the 73 plus the 653 that previously pointed at isic_v4 parents (654 minus V.99, which had no parent before and now points at V). Every one of the 726 is child_std 2 -> parent_std 2. After reset: 0 cross-standard links, 0 orphans, 0 enabled children under disabled parents.
So the larger number is the fix: the nace children used to sit under ISIC rows and were invisible to the reset.

public.reset replacement join (rabbit): it is unscoped by standard. For the 1811 deleted overrides: 225 have one same-standard candidate only, 418 are AMBIGUOUS (one same-standard and one other-standard candidate), 256 have only an other-standard candidate, 912 have none. Cross-standard parent links after the reset on master+473: 0. It is correct today only because public.lookup_parent_and_derive_code (BEFORE UPDATE, scoped by 473) re-derives parent_id and overrides whatever the join wrote. Proof: UPDATE SET parent_id = <isic row 3> on nace A.01.1.1 stored nace parent 768. Scoping the join orphans nothing (0 children under a custom parent with no same-standard twin). Filed as STATBUS-476 rather than an unreviewed edit to the 450-line reset() after landing.

Remaining id = EXCLUDED.id instances outside activity_category (28 functions incl. generate_path/code_upsert_function, upsert_legal_form/sector/status/... custom+system): filed as STATBUS-477.

Databases used: statbus_473_scratch, statbus_473_dedupe_red/_green, statbus_473_reset_with/_without, all my own clones, dropped afterwards. The shared statbus_seed/template were rebuilt only through ./dev.sh recreate-seed.
EOF
)
<!-- SECTION:NOTES:END -->
