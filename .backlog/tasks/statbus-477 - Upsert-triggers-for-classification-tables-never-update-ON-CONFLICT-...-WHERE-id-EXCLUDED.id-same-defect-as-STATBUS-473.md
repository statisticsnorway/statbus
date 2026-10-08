---
id: STATBUS-477
title: >-
  Upsert triggers for classification tables never update: ON CONFLICT ... WHERE
  id = EXCLUDED.id (same defect as STATBUS-473)
status: Done
assignee: []
created_date: '2026-10-08 16:35'
updated_date: '2026-10-08 17:56'
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
- [x] #1 No function in doc/db/function contains the id = EXCLUDED.id predicate
- [x] #2 pg_regress test re-uploads a corrected custom row for each affected view and asserts the stored name changed and the statement reports the row
- [x] #3 Any stale-delete paired with these upserts is checked against the fixed upsert (no wall-clock deletion of re-uploaded rows)
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 Fast Tests (pg_regress actually run, not skipped) green on a commit containing 1aac424c5 and 054bd18fe, recorded here; blocked by STATBUS-481
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
WORKLIST (2026-10-08). Observed on statbus_seed at master in rolled-back transactions, and in my own clone statbus_477_scratch (dropped afterwards). Probe: tmp/477/probe.sql, output: tmp/477/probe_master.log.

Common to all 28: every target table has an identity id, so WHERE <t>.id = EXCLUDED.id never fires. Every conflict target DOES match a real unique index, so there is no "target matches no constraint" case. But for most families the target is the WRONG key, which makes the naive fix (just drop the predicate) a new bug: (enabled, code) treats an enabled custom override and an enabled system row as the same row. Proven in a clone: with the predicate removed from upsert_legal_form_system, a system reload rewrote the operator's custom ACO override to name 'system reload name' with custom=f. The real key, as in 473, is (code or path, custom).

Observed today: a re-upload with a corrected name keeps the old name and reports INSERT 0 0 for legal_form_custom_only (the app upload view), legal_form_custom, legal_form_system, sector_custom, tag_custom, data_source_custom, region_version_custom, unit_size_system. Control: sector_custom_only (no predicate) updates correctly.

Families (target, real key, fix):
A. legal_form, 3 fns. legal_form_custom_only conflicts on (code,enabled,custom); upsert_legal_form_custom/system on (enabled,code). App upload view, highest user impact. Fix: UNIQUE(code, custom) after a deterministic dedupe (enabled first, then lowest id; legal_unit.legal_form_id moved first); all three conflict on it; RETURN NEW so the upload reports rows.
B. code-generated with only (enabled,code): data_source, foreign_participation, unit_size, status (8 fns) plus admin.generate_code_upsert_function. Same fix as A (UNIQUE(code, custom) plus dedupe; data_source has 9 FKs, unit_size 3, status 2). Found: status_custom and status_system omit assigned_by_default and used_for_counting (NOT NULL, no default), so EVERY insert through them errors; broken loudly, not silently; needs a decision (add the columns or drop the triggers).
C. UNIQUE(code) tables: legal_rel_type, legal_reorg_type, person_role, power_group_type, region_version (10 fns). A custom row for an existing system code is impossible by schema (observed duplicate key on person_role_code_key and region_version_code_key). Fix: conflict on (code), update only when custom matches, and raise an explicit error on a system/custom collision instead of a silent 0. No new constraint, so no dedupe.
D. path-generated: sector_custom/system, tag_custom/system (4 fns) plus admin.generate_path_upsert_function. Same predicate bug, plus the generator inserts CUSTOM rows with enabled=false (observed: sector_custom and tag_custom rows land disabled and invisible). sector and tag also have UNIQUE(path), so a custom override of a system path is impossible (as in C). Found: sector_custom_only's unique_violation handler itself fails ("invalid input syntax for type json" from code::jsonb on a plain string), masking the real error.
E. country (upsert_country and delete_stale_country). The conflict target (iso_2, iso_3, iso_num, name) includes name, so a corrected name never conflicts and hits country_iso_2_key (observed). delete_stale_country is the 473 wall-clock pattern: reloading the shipped dbseed/country/country_codes.csv through country_view leaves 0 countries (observed COPY 251 then 0 rows), and with settings pointing at a country it aborts on RESTRICT. Only migrations write it today. Fix: conflict on iso_2; stale = complement of the addressed codes (473 shape).

Fixtures and demo: the shipped writers are the 2024 install migrations (*_system from dbseed, loaded once into empty tables, so unchanged on replay), samples/demo and samples/norway getting-started (legal_form_custom_only, sector_custom_only, data_source_custom), and tests 003, 314, 403, 404. All 18 shipped CSVs have 0 duplicate keys within a file and none is loaded twice, so expected-output changes should be confined to command tags (which pg_regress suppresses) plus the new tests. The behaviour change is on second uploads only.

Proposed order, one migration plus one pg_regress test per commit, each RED then GREEN: A legal_form; E country; B code family (with generator); D path family (with generator, custom enabled); C UNIQUE(code) family. The status view columns and the sector_custom_only handler bug become separate small tickets unless review wants them folded in.

FAMILY E (country) scope note, per rabbit: kept in 477 because it is severe. It is a MIGRATION-ONLY path: nothing in app/, samples/ or test/ writes through country_view; only migrations/20240214000000_create_function_upsert_country.up.psql loads dbseed/country/country_codes.csv through it. Observed on master: reloading that shipped file through country_view leaves 0 countries (COPY 251, then count = 0), because delete_stale_country deletes every row with updated_at < statement_timestamp() and upsert_country never updates (id = EXCLUDED.id). With settings.country_id referencing a country, the reload aborts under RESTRICT (settings_country_id_fkey). A corrected name for an existing country fails on country_iso_2_key, because the conflict target (iso_2, iso_3, iso_num, name) includes name.

FAMILY A legal_form: LANDED as 27d652b03 (migration 20261008164443_statbus_477_legal_form_upserts_update_existing_rows, test 134).
Target: ON CONFLICT (code, custom), a new UNIQUE legal_form_code_custom_key, for all three of legal_form_custom_only, upsert_legal_form_custom and upsert_legal_form_system; no id predicate; RETURN NEW. The system reload corrects the system row's label only (never its enabled flag, never the custom override); a new system code starts disabled while an enabled custom override exists.

Test 134 on three clones of statbus_seed (master at 20261008161441), all my own:
- statbus_477a_prefix (pre-fix master), RED: every upload returns 0 rows / INSERT 0 0; the re-upload keeps 'Forening (first upload)'; 134.4's system reload inserts a SECOND enabled AUPS system row (old (enabled,code) key) instead of renaming.
- statbus_477a_naive (only the id predicate dropped, wrong target kept; rabbit's condition 2), RED for the right reason: re-uploads now land, but 134.3's system reload of ACO REWROTE the operator's custom override, so the row the legal unit points to becomes custom=f, name 'Association/club/organisation (system reload)', and legal_form_custom_only shows 0 rows for ACO.
- statbus_477a_fixed (final migration), GREEN: re-upload via INSERT and via COPY lands on the same row (same_row_as_first_upload = t); legal_form_custom re-upload lands; the system reload updates only the system row (stays disabled), the custom override and the legal unit's reference keep 'Forening (corrected via csv)'; AUPS renamed in place, still disabled; 0 duplicate (code, custom).
- pg_regress ./dev.sh test 134 on the template from statbus_seed = master + A: ok. Down/up round trip clean.

Dedupe (rabbit's condition 3), clones statbus_477a_dedupe_red/_green of pre-fix master. Duplicates produced by the PRE-FIX upserts themselves: AUPS system 2 (disabled, older) + 55 (enabled, made by a system reload after the custom-only upload disabled system rows); QDUP custom 56 (disabled, lower id) + 57 (enabled). A legal unit points at each redundant row.
- RED (migration without the dedupe): ERROR could not create unique index legal_form_code_custom_key, Key (code, custom)=(QDUP, t) is duplicated.
- GREEN: NOTICE removed 2 redundant rows; kept 55 and 57 (rule: enabled first, then lowest id, so 57 is kept over the lower id 56); both legal units moved to the kept rows; a fresh duplicate is rejected by legal_form_code_custom_key.

Related tests on master + A: 003, 108, 305, 306, 314 ok. 404 fails, but identically on the pre-fix clone (no difference between pre-fix and with-fix output beyond psql's expanded-display banner): its expected file is stale since 2026-03 (person_ident index notices, the settings region_version_id column), unrelated to 477 and outside the fast suite (4xx). Expected-output changes from A: only the new test 134. No existing expected file changed.
doc/db: generated once from statbus_seed = master + A (no other unlanded migration in migrations/): 0 added, 0 deleted, 4 modified (3 functions + public_legal_form table), 581 on disk = 581 tracked.

FAMILY A: why the key is (code, custom) and not the existing (code, enabled, custom).
enabled is not part of a row's identity; it is a visibility flag. legal_form_custom_only's prepare trigger disables every system row before an upload, and public.reset re-enables them, so the same system row flips between enabled and disabled during its life. A key that includes enabled therefore allows a code to hold two system rows (one enabled, one disabled) or two custom rows. The pre-fix upserts made exactly that: after a custom-only upload disabled AUPS, a system reload of AUPS inserted a SECOND system row instead of updating the first (observed in test 134 on the pre-fix clone, 134.4). An upsert that conflicts on a key containing enabled can likewise miss the existing row whenever the incoming enabled value differs, and insert a duplicate. Identity is (code, custom): one system row and at most one custom override per code. (code, enabled, custom) is kept, as it is implied by the new key and harmless. Because enabled is not identity, the dedupe chooses the row a user actually sees (the enabled one) over the lower id: in the proof, QDUP kept id 57 (enabled) over 56 (disabled, lower id).

FAMILY E country: LANDED as f8553dd00 (migration 20261008165621_statbus_477_country_upsert_updates_and_keeps_reloaded_countries, test 135).
Target: ON CONFLICT (iso_2), the existing country_iso_2_key. country has no custom dimension, so no new key and no dedupe. A reload corrects iso_3, iso_num and name in place. delete_stale_country = complement of the iso_2 codes the statement addressed (pg_temp.country_addressed, as 473); an empty load deletes nothing.

Test 135, all on my own clones of master:
- statbus_477a_prefix (pre-fix master), RED: with settings referencing NO, the reload of the shipped country_codes.csv aborts with "update or delete on table country violates RESTRICT ... settings_country_id_fkey" (135.1). Without settings, the same reload leaves 0 countries (COPY 251, count 0; tmp/477/E_reload_no_settings.log).
- statbus_477e_naive (only the id predicate dropped, target with name kept), RED for the wrong-key reason: 135.1 now keeps 251 (the unchanged names conflict and update), but 135.2's corrected name for NO fails with "duplicate key value violates unique constraint country_iso_2_key", because a target containing name never matches a corrected name.
- statbus_477e_fixed (final migration), GREEN: 135.1 keeps 251 of 251 with the same ids and settings intact; 135.2 corrects NO's name in place (same id), 251 rows; 135.3 removes only AQ (250); 135.4: the reload without NO fails on RESTRICT (settings_country_id_fkey) and, after the savepoint rollback, nothing changed. Down/up round trip clean.
- pg_regress on master + A + E: 135 ok; 134, 015, 108 ok.
Expected-output changes: only the new test 135. Its one expected ERROR (line 84, 135.4) is justified in the commit message per the commit-msg hook.
doc/db: generated once from statbus_seed = master + E: 0 added, 0 deleted, 2 modified (admin_upsert_country, admin_delete_stale_country), 581 on disk = 581 tracked.
Side ticket: STATBUS-480 (test 404 is red identically before and after 477; the expected file has been stale since 2026-03; no CI runs 4xx).

FAMILY B code-generated (data_source, foreign_participation, unit_size, status): LANDED as 194608712 (migration 20261008170330_statbus_477_code_generated_upserts_update_existing_rows, test 136).
Target: ON CONFLICT (code, custom), a new UNIQUE <table>_code_custom_key on all four tables, for the eight upserts; no id predicate; RETURN NEW. The system upsert corrects the label only (never enabled, never the custom row). Generators fixed: admin.generate_code_upsert_function emits that shape; admin.generate_active_code_custom_unique_constraint creates <table>_code_custom_key when absent (idempotent across drop/regenerate). The migration ends by asserting all four keys exist; it raises otherwise (status included, for STATBUS-478).

Test 136, on my own clones of statbus_seed:
- statbus_477b_prefix (pre-fix master), RED: every upload returns 0 rows / INSERT 0 0; the data_source_custom re-upload keeps 'Skatteregisteret (first upload)'; no (code, custom) keys; the generator on a fresh table emits ON CONFLICT (enabled, code) with the id predicate and no RETURN NEW.
- statbus_477b_naive (only the id predicate dropped, (enabled, code) kept), RED for the wrong-key reason: 136.2's data_source_system reload of ntr REWROTE the operator's custom override, so the row the legal unit references became custom=f, 'National Tax Registry (system reload)'.
- statbus_477b_fixed (final), GREEN: re-uploads via INSERT and COPY land on the same row; the system reload updates only the system ntr (stays disabled) while the custom override and the legal unit keep 'Skatteregisteret (corrected via csv)'; unit_size and foreign_participation reload in place; all four keys present; and the GENERATOR PROOF (rabbit's condition 1): generate_table_views_for_batch_api on a fresh table probe_477_code produces custom and system upserts with ON CONFLICT (code, custom), has_id_predicate = f, reports_rows = t, creates probe_477_code_code_custom_key, and upload/correct/re-upload plus a system reload behave correctly on it.
- pg_regress on master + A + E + B: 136, 134, 135, 015, 108, 305, 306 ok. Down/up round trip clean.

Dedupe (rabbit's conditions 2 and 3), clones statbus_477b_dedupe_red/_green of pre-fix master. Duplicates made by the PRE-FIX upserts (a custom upload disables system rows, then a system reload inserts a second, enabled system row): data_source ntr (1 disabled, 12 enabled), unit_size tny (1, 9), foreign_participation a (1, 11), plus a manufactured custom duplicate data_source qdup (13 disabled with the LOWER id, 14 enabled). Every redundant row carries references: 4 legal units (data_source_id / unit_size_id / foreign_participation_id) and 2 activities (data_source_id).
- RED (ADD CONSTRAINT without the dedupe): ERROR could not create unique index data_source_code_custom_key, Key (code, custom)=(qdup, t) is duplicated.
- GREEN: NOTICEs moved 2 activity.data_source_id + 2 legal_unit.data_source_id, 1 legal_unit.foreign_participation_id, 1 legal_unit.unit_size_id; removed 2 data_source, 1 foreign_participation, 1 unit_size, 0 status. Kept 12, 14, 9, 11 (enabled first; 14 kept over the lower id 13). All 4 legal units and 2 activities now point at the kept enabled rows. Fresh duplicates are rejected by data_source_code_custom_key and unit_size_code_custom_key.
Reference collisions: no referencing table has a unique index over its foreign key column into these four tables (checked in pg_catalog), so no colliding-row deletion is needed; the migration aborts with an explicit error if such an index ever appears, rather than guess.
Expected-output changes: only the new test 136.
doc/db: generated once from statbus_seed = master + B: 0 added, 0 deleted, 14 modified (2 generators, 8 upserts, 4 tables), 581 on disk = 581 tracked.

FAMILY D path-generated (sector, tag): LANDED as b4f129104 (migration 20261008172118_statbus_477_path_generated_upserts_update_existing_rows, test 137).

WHY NO DEDUPE (rabbit's condition 4): sector and tag both carry UNIQUE (path), as sector_path_key and tag_path_key, verified in pg_constraint. A row's identity is therefore its path alone: one row per path, owned by one kind (system or custom). A custom override of a system path is impossible by schema, so the duplicate that families A and B had to collapse ((code, custom) pairs) cannot exist here, and nothing needs adding. Every table in the family has its path key (the only public tables with both path and custom are activity_category (473), sector and tag). None was missing, so none was added silently. The generator now ensures UNIQUE (path) for any path table generated later.

Target: ON CONFLICT (path), updating only a row of the upsert's own kind. A path owned by the other kind is refused before the insert.

COLUMN AUDIT (rabbit's condition 1): sector_custom, sector_system, tag_custom, tag_system and sector_custom_only each accept exactly path, name, description (pg_attribute). Before: the four generated upserts wrote path and name only and silently DROPPED description. After: path, name and description are all written (description on insert and on update); parent_id is derived from path, enabled and custom by kind, updated_at by the clock. No accepted column is left dropped. (sector_custom_only is the hand-written app-upload function; it already wrote description and has no id predicate, and its broken error handler is STATBUS-479.)

GENERATOR enabled bug (condition 2): the template inserted enabled = NOT custom_value, so every GENERATED custom upsert inserted its row DISABLED, i.e. invisible in <t>_custom. Fixed in the template; the custom upsert inserts and keeps its row enabled. The system upsert inserts enabled and on update corrects labels only, never enabled.

ACTIONABLE ERROR (condition 3), observed verbatim:
- ERROR: sector path "zzop" already exists as a custom entry, so this system (standard) upload cannot add or change it. HINT: The standard list cannot overwrite an entry an operator uploaded. Remove or rename the custom entry first.
- ERROR: sector path "domestic" already exists as a system (standard) entry, so this custom upload cannot add or change it. HINT: A custom entry cannot replace a standard one with the same path. Use a path that is not in the standard list.
(SQLSTATE unique_violation, so callers that map that class still see the class.)

Test 137, on my own clones of statbus_seed (master + A, E, B):
- statbus_477d_prefix (pre-fix), RED: sector_custom upload returns 0 rows / INSERT 0 0; the row lands custom=t, enabled=f (invisible: sector_custom shows 0 rows); the re-upload keeps 'first'; tag_custom the same. 137.2: after the custom-only upload (36 system sectors, 0 enabled), reloading dbseed/sector.csv fails with "duplicate key value violates unique constraint sector_path_key, Key (path)=(domestic) already exists".
- statbus_477d_naive (only the id predicate dropped, (enabled, path) and the inverted enabled kept), RED: re-uploads now land, but the rows stay enabled=f and invisible, and 137.2 fails on sector_path_key exactly as pre-fix. That is the wrong-key demonstration.
- statbus_477d_fixed (final), GREEN: re-uploads land with description and enabled=t, visible in sector_custom; tag_custom via INSERT and COPY; 137.2 reloads all 36 shipped sectors (COPY 36), keeps 36 of 36 ids, keeps them disabled, renames domestic in place; 137.3 shows the two errors above, with nothing changed; 137.4 generator proof on a fresh table probe_477_path: ON CONFLICT (path) for custom and system, has_id_predicate = f, reports_rows = t, probe_477_path_path_key created, the custom upload lands enabled with description, the correction lands, and a system reload corrects 'a' without touching custom 'b'.
- pg_regress on master + A + E + B + D: 137, 136, 134, 135, 003, 015, 108, 305, 306 ok. Down/up round trip clean.
Expected-output changes: only the new test 137. Its two deliberate ERRORs (lines 107, 112) are justified in the commit message.
doc/db: generated once from statbus_seed = master + D: 0 added, 0 deleted, 6 modified (2 generators, 4 upserts), 581 on disk = 581 tracked.
CI: none claimed; Images is blocked by STATBUS-481, so Fast Tests skips pg_regress.

FAMILY C (legal_rel_type, legal_reorg_type, person_role, power_group_type, region_version) and KEY-AWARE GENERATORS: LANDED as 1aac424c5 (migration 20261008172915_statbus_477_key_aware_generators_and_code_keyed_upserts, test 138).

Identity keys verified before relying on them (pg_constraint, rabbit's condition 3): legal_rel_type_code_key, legal_reorg_type_code_key, person_role_code_key, power_group_type_code_key, region_version_code_key, all UNIQUE (code). None was missing. One row per code, owned by one kind, so no new key and no dedupe. The migration also asserts every generated table's resolved key.

KEY-AWARE GENERATORS (rabbit's design requirement): new admin.batch_api_identity_key(table_properties) derives the conflict target from the keys the table ACTUALLY has: (code)/(path) where that alone is uniquely indexed (non-partial); else (code, custom) where that key exists; else the default that admin.generate_active_code_custom_unique_constraint then creates ((code, custom) for code tables with custom, (path) for path tables). generate_code_upsert_function and generate_path_upsert_function both call it; no family is named. The path generator refuses a path table whose identity is not (path), because it derives parent_id by path, rather than mis-generate. Proven both directions in test 138 on fresh tables: probe_477_code_only (UNIQUE (code)) gets ON CONFLICT (code); probe_477_code_custom (custom, no key) gets ON CONFLICT (code, custom) and the UNIQUE (code, custom) key, so B's fix holds. 138.6 lists the resolved key of all 12 generated tables: data_source, foreign_participation, legal_form, status, unit_size {code,custom}; legal_rel_type, legal_reorg_type, person_role, power_group_type, region_version {code}; sector, tag {path}. All 24 generated upserts are regenerated by the fixed generators in the migration, so the installed functions are exactly generator output.

COLUMN AUDIT (rabbit's condition 1), accepted vs written:
- legal_rel_type_custom/_system accept code, name, description: all written. primary_influencer_only (NOT NULL DEFAULT false) is NOT accepted by the views, so the default applies on insert and an update leaves it unchanged. Its second key (id, primary_influencer_only) contains id and cannot collide on an upsert.
- legal_reorg_type_* accept code, name, description: all written. description is NOT NULL with no default, so an upload omitting it fails with a not-null error that names the column (honest, not silent). Left as is.
- person_role_* and power_group_type_* accept code, name: both written. Second key UNIQUE (name): a collision is now reported as 'person_role code "q139" cannot be stored: another entry already has a value that must be unique (Key (name)=(...) already exists.)' with HINT 'Each value in a unique column (such as name) may be used by only one entry. Change the uploaded value, or change the existing entry first.' (138.4), never a raw duplicate key.
- region_version_* accept code, name, description: all written. lasts_to is not accepted (NULL on insert, unchanged on update). Its partial key region_version_enabled_lasts_to_key (lasts_to) NULLS NOT DISTINCT WHERE enabled allows only one enabled version with an open-ended lasts_to, so a second enabled custom version in one upload collides. That collision is now reported through the same actionable message (the generic second-key handler). Deeper: a region_version_custom upload disables the system version through the prepare trigger, and with settings referencing it via settings_region_version_enabled_fk it fails on that foreign key. Region versions are not changed by upload in practice (the app uses region_upload), so that interplay is LEFT ALONE here and recorded, not silently fixed.
CROSS-KIND (condition 2), verbatim: 'person_role code "q138" already exists as a custom entry, so this system (standard) upload cannot add or change it', HINT 'The standard list cannot overwrite an entry an operator uploaded. Remove or rename the custom entry first.', and the mirror for custom over standard.

Test 138, on my own clones of statbus_seed (master + A, E, B, D):
- statbus_477c_prefix (pre-fix), RED: all ten custom uploads return 0 rows / INSERT 0 0 and the re-uploads keep 'first'; 138.2: after the custom upload disabled the system rows, the person_role_system reload of 'dir' fails with "duplicate key value violates unique constraint person_role_code_key".
- statbus_477c_naive (id predicate dropped, (enabled, code) kept), RED for the wrong-key reason: re-uploads now land, but 138.2 still fails on person_role_code_key, because (enabled, code) cannot see the disabled system row.
- statbus_477c_fixed (final), GREEN: all five families re-upload in place, enabled, description written; 138.2 renames 'dir' in place and keeps it disabled; 138.3 and 138.4 show the actionable errors; 138.5 and 138.6 show the generator results above.
- pg_regress on master + all 477 families: 138, 137, 136, 135, 134, 133, 003, 015, 108, 305, 306 ok. Down/up round trip clean on a clone of the seed.
Expected-output changes: the new test 138, and 137's two CONTEXT line numbers (the regenerated path upsert has one more line). The error texts are unchanged. All expected ERRORs are justified in the commit message.
doc/db: generated once from statbus_seed = master + C: 1 added (admin_batch_api_identity_key, created by this migration), 0 deleted, 27 modified (3 generators, 24 upserts), 582 on disk = 581 tracked + the 1 added.

STATBUS-477 INVENTORY (the record; the per-family behaviour tests 134-138 are the proof).

Family | functions | key conflicted on | key added? | landed | test
A legal_form | legal_form_custom_only (hand-written, app upload), upsert_legal_form_custom, upsert_legal_form_system | (code, custom) | yes, legal_form_code_custom_key, after dedupe | 27d652b03 | 134
E country | upsert_country, delete_stale_country | (iso_2); stale = complement of addressed codes | no (country_iso_2_key existed) | f8553dd00 | 135
B code tables with custom | upsert_{data_source,foreign_participation,unit_size,status}_{custom,system} + generate_code_upsert_function + generate_active_code_custom_unique_constraint | (code, custom) | yes, <t>_code_custom_key x4, after dedupe moving all FK references | 194608712 | 136
D path tables | upsert_{sector,tag}_{custom,system} + generate_path_upsert_function | (path) | no (sector_path_key, tag_path_key existed) | b4f129104 | 137
C code-keyed tables | upsert_{legal_rel_type,legal_reorg_type,person_role,power_group_type,region_version}_{custom,system}; generators made key-aware via admin.batch_api_identity_key; all 24 generated upserts regenerated | (code) | no (<t>_code_key existed) | 1aac424c5 | 138
(473, separately: activity_category upserts and delete_stale_activity_category, c184c9cb3, test 133.)

What was fixed across all of them: the never-firing WHERE <t>.id = EXCLUDED.id predicate; the wrong conflict target ((enabled, x), or name in country's target); RETURN NEW so INSERT/COPY report the rows written; generated custom rows inserted disabled (path template); silently dropped description (path template); raw duplicate-key errors replaced by actionable messages (cross-kind; second unique keys); wall-clock stale deletes replaced by complement-of-addressed (country here, activity_category in 473).

Deliberately left alone, with reasons:
- The two generator functions still contain the text 'id = EXCLUDED.id', in explanatory comments only. No generated function contains the predicate (tests 136-138 assert has_id_predicate = f for generated functions; no live upsert in pg_proc has it).
- sector_custom_only (hand-written): already conflicted correctly and wrote description; its unique_violation handler crashes on code::jsonb, which masks the real error. That is STATBUS-479 by owner decision, not fixed here.
- status_custom/status_system: fixed functions and key, but the views omit NOT NULL columns, so inserts still error loudly. That is STATBUS-478.
- region_version upload vs settings_region_version_enabled_fk and the one-open-ended-enabled-version key: recorded in C's audit; not an upload path in practice.
- legal_reorg_type.description NOT NULL without default: an upload must supply it; the error names the column.
- public.reset's unscoped activity_category join: STATBUS-476.
- No schema-wide 'grep for the old pattern' test, per the owner's principle against token-keyed absence tests.

AC #3 (stale deletes): the only stale-delete triggers paired with these upserts are delete_stale_country (family E, fixed to the complement of addressed codes, test 135) and delete_stale_activity_category (473). The generated families have no stale delete; their statement-level companion is the prepare trigger, which disables system rows and deletes nothing.

CI EVIDENCE WITHHELD: every 477 commit (27d652b03, f8553dd00, 194608712, b4f129104, 1aac424c5) landed while Images' seed job is broken by STATBUS-481, so Fast Tests skipped pg_regress for all of them. No CI evidence is claimed for 477. When 481 clears Images, the first Fast Tests run whose exercised SHA contains 1aac424c5 is the CI evidence to record here. All evidence above is local pg_regress on databases I created, named per family.

AC CHECK (2026-10-08). AC#1: no live function contains the predicate. pg_proc shows the text only in explanatory comments of generate_code_upsert_function and generate_path_upsert_function, and tests 136-138 assert has_id_predicate = f for generated functions. AC#2: every affected custom view has an upload/correct/re-upload test that asserts the stored name and the reported row: legal_form_custom_only and legal_form_custom (134), country_view (135), data_source_custom, foreign_participation_custom (added in 054bd18fe) and unit_size_custom (136), sector_custom, tag_custom and sector_custom_only (137), legal_rel_type_custom, legal_reorg_type_custom, person_role_custom, power_group_type_custom and region_version_custom (138). The one exception is status_custom: its view omits NOT NULL columns, so no insert can succeed through it until STATBUS-478 lands. Its functions and key are fixed and asserted here, and 478 carries the behaviour test. AC#3: see the inventory (delete_stale_country fixed and tested in 135; the generated families have no stale delete). DoD 'CI evidence' stays open: withheld until STATBUS-481 restores Images.

AC#2 EXCEPTION CLOSED (2026-10-08): the recorded gap for status_custom (its view could not accept an insert) is closed by STATBUS-478, landed as c4203d184. Test 140.1 uploads, corrects and re-uploads through status_custom and asserts that code, name, priority, assigned_by_default and used_for_counting are stored on the same row. 140.2 does the same for status_system. Every affected custom view now has a re-upload test.
<!-- SECTION:NOTES:END -->
