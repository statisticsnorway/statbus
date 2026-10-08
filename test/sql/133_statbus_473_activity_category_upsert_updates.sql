-- STATBUS-473: activity category upserts update existing rows.
--
-- The upsert triggers behind the activity_category_* views used
--   ON CONFLICT ... DO UPDATE ... WHERE activity_category.id = EXCLUDED.id
-- where id is GENERATED ALWAYS AS IDENTITY, so EXCLUDED.id is a freshly drawn
-- id and the update never fired. The statement-level stale delete behind the
-- standard views then removed every code of the standard that the (no-op)
-- upsert had not touched, cascading to activity.
--
-- Invariants checked, on a database where activities reference the categories:
--   1. Re-uploading a custom category with a corrected label (the getting
--      started upload view, activity_category_enabled_custom) updates the
--      stored label, keeps the row id the activities reference, and the
--      statement reports the rows it wrote.
--   2. Reloading a standard (activity_category_nace_v2_1) keeps every code
--      present in the reload with its id and updated name, removes only the
--      codes absent from the reload, never touches custom overrides, and the
--      activities referencing kept codes survive.
--   3. Inserting through activity_category_enabled works: it reads the real
--      settings column, conflicts on the real key, and re-uploads update.
--   4. Every parent link stays inside its own standard.
BEGIN;

\i test/setup.sql

\echo "Test 133: activity category upserts update existing rows (STATBUS-473)"

CALL test.set_user_from_email('test.admin@statbus.org');

INSERT INTO public.settings(activity_category_standard_id, country_id, region_version_id)
SELECT (SELECT id FROM public.activity_category_standard WHERE code = 'nace_v2.1')
     , (SELECT id FROM public.country WHERE iso_2 = 'NO')
     , (SELECT id FROM public.region_version WHERE code = 'initial');

\echo "133.0: activities reference a standard code (A.01.1.1), a custom code (A.01.3.0) and an absent-from-reload code (A.01.7)"
INSERT INTO public.activity_category_enabled_custom(path, name)
VALUES ('A.01.3.0', 'Plant propagation (first upload)');

CREATE TEMP TABLE probe(tag text PRIMARY KEY, category_id int NOT NULL);
INSERT INTO probe(tag, category_id)
SELECT 'standard_kept', ac.id
  FROM public.activity_category AS ac
  JOIN public.activity_category_standard AS acs ON acs.id = ac.standard_id
 WHERE acs.code = 'nace_v2.1' AND ac.path::text = 'A.01.1.1' AND NOT ac.custom
UNION ALL
SELECT 'custom', ac.id
  FROM public.activity_category AS ac
  JOIN public.activity_category_standard AS acs ON acs.id = ac.standard_id
 WHERE acs.code = 'nace_v2.1' AND ac.path::text = 'A.01.3.0' AND ac.custom
UNION ALL
SELECT 'standard_absent', ac.id
  FROM public.activity_category AS ac
  JOIN public.activity_category_standard AS acs ON acs.id = ac.standard_id
 WHERE acs.code = 'nace_v2.1' AND ac.path::text = 'A.01.7' AND NOT ac.custom;
SELECT tag FROM probe ORDER BY tag;

DO $$
DECLARE
    v_admin_id int;
    v_status_active int;
    v_ent int;
    v_lu int;
    v_tag text;
BEGIN
    SELECT id INTO v_admin_id FROM auth.user WHERE email = 'test.admin@statbus.org';
    SELECT id INTO v_status_active FROM public.status WHERE code = 'active';
    FOR v_tag IN SELECT tag FROM probe ORDER BY tag LOOP
        INSERT INTO public.enterprise (short_name, edit_by_user_id, edit_at)
        VALUES (left('E133 ' || v_tag, 16), v_admin_id, now()) RETURNING id INTO v_ent;
        INSERT INTO public.legal_unit (enterprise_id, name, status_id, primary_for_enterprise,
                                       edit_by_user_id, edit_at, valid_from)
        VALUES (v_ent, 'LU 133 ' || v_tag, v_status_active, true,
                v_admin_id, now(), '2023-01-01') RETURNING id INTO v_lu;
        INSERT INTO public.activity (valid_range, valid_from, valid_until, type, category_id,
                                     legal_unit_id, edit_by_user_id, edit_at, edit_comment)
        SELECT daterange('2023-01-01', 'infinity', '[)'), '2023-01-01', 'infinity', 'primary', p.category_id,
               v_lu, v_admin_id, now(), 'act-133-' || v_tag
          FROM probe AS p WHERE p.tag = v_tag;
    END LOOP;
END $$;

SELECT a.edit_comment AS activity, ac.path, ac.custom
  FROM public.activity AS a
  JOIN public.activity_category AS ac ON ac.id = a.category_id
 WHERE a.edit_comment LIKE 'act-133-%'
 ORDER BY a.edit_comment;

\echo "133.1: re-uploading a custom category with a corrected label updates it, and the statement reports the row"
INSERT INTO public.activity_category_enabled_custom(path, name)
VALUES ('A.01.3.0', 'Plant propagation (corrected)')
RETURNING path, name;

SELECT ac.path, ac.custom, ac.enabled, ac.name
     , ac.id = (SELECT category_id FROM probe WHERE tag = 'custom') AS same_id_as_activity
  FROM public.activity_category AS ac
  JOIN public.activity_category_standard AS acs ON acs.id = ac.standard_id
 WHERE acs.code = 'nace_v2.1' AND ac.path::text = 'A.01.3.0'
 ORDER BY ac.custom;

\echo "133.1b: the same re-upload through COPY, the format the upload page posts"
\copy public.activity_category_enabled_custom(path, name) FROM stdin WITH (FORMAT csv)
A.01.3.0,Plant propagation (corrected via csv)
\.
SELECT ace.path, ace.name
  FROM public.activity_category_enabled_custom AS ace
 WHERE ace.path::text = 'A.01.3.0';

\echo "133.2: reloading a standard keeps the codes it contains, removes only absent ones, leaves custom overrides alone"
-- The views behind the standards are loaded by migrations as the database owner.
RESET ROLE;

CREATE TEMP TABLE nace_before AS
SELECT ac.id, ac.path, ac.name, ac.custom, ac.enabled
  FROM public.activity_category AS ac
  JOIN public.activity_category_standard AS acs ON acs.id = ac.standard_id
 WHERE acs.code = 'nace_v2.1';

-- The reload: every standard code except the A.01.7 subtree, with A.01.1.1
-- renamed, and one code the standard did not have before (A.01.8).
INSERT INTO public.activity_category_nace_v2_1(path, name, description)
SELECT nb.path
     , CASE WHEN nb.path::text = 'A.01.1.1' THEN 'Growing of cereals (renamed by reload)' ELSE nb.name END
     , NULL
  FROM nace_before AS nb
 WHERE NOT nb.custom
   AND NOT nb.path OPERATOR(public.<@) 'A.01.7'::public.ltree
UNION ALL
SELECT 'A.01.8'::public.ltree, 'New group added by the reload', NULL
 ORDER BY 1;

SELECT count(*) FILTER (WHERE NOT nb.custom) AS standard_codes_before
     , count(*) FILTER (WHERE NOT nb.custom AND NOT nb.path OPERATOR(public.<@) 'A.01.7'::public.ltree) AS standard_codes_reloaded
     , count(*) FILTER (WHERE NOT nb.custom AND ac.id IS NOT NULL) AS standard_codes_kept_with_same_id
     , count(*) FILTER (WHERE NOT nb.custom AND ac.id IS NULL) AS standard_codes_removed
     , count(*) FILTER (WHERE nb.custom AND ac.id IS NOT NULL) AS custom_codes_kept
  FROM nace_before AS nb
  LEFT JOIN public.activity_category AS ac ON ac.id = nb.id;

SELECT nb.path AS removed_path
  FROM nace_before AS nb
 WHERE NOT EXISTS (SELECT 1 FROM public.activity_category AS ac WHERE ac.id = nb.id)
 ORDER BY nb.path;

SELECT ac.path, ac.custom, ac.enabled, ac.name
  FROM public.activity_category AS ac
  JOIN public.activity_category_standard AS acs ON acs.id = ac.standard_id
 WHERE acs.code = 'nace_v2.1' AND ac.path::text IN ('A.01.1.1', 'A.01.3.0', 'A.01.8')
 ORDER BY ac.path, ac.custom;

\echo "133.2b: the activities on kept codes survive, the one on the removed code cascades away"
SELECT p.tag
     , EXISTS (SELECT 1 FROM public.activity AS a WHERE a.edit_comment = 'act-133-' || p.tag) AS activity_exists
  FROM probe AS p
 ORDER BY p.tag;

\echo "133.3: inserting through activity_category_enabled reads the real settings column and conflicts on the real key"
INSERT INTO public.activity_category_enabled(path, name)
VALUES ('A.01.2.1', 'Growing of grapes (custom via enabled)')
RETURNING path, name;
INSERT INTO public.activity_category_enabled(path, name)
VALUES ('A.01.2.1', 'Growing of grapes (custom via enabled, corrected)')
RETURNING path, name;

SELECT ac.path, ac.custom, ac.enabled, ac.name
  FROM public.activity_category AS ac
  JOIN public.activity_category_standard AS acs ON acs.id = ac.standard_id
 WHERE acs.code = 'nace_v2.1' AND ac.path::text = 'A.01.2.1'
 ORDER BY ac.custom;

SELECT ace.path, ace.parent_path, ace.custom, ace.name
  FROM public.activity_category_enabled AS ace
 WHERE ace.path::text = 'A.01.2.1';

\echo "133.4: every parent link stays inside its own standard"
SELECT count(*) AS cross_standard_parent_links
  FROM public.activity_category AS child
  JOIN public.activity_category AS parent ON parent.id = child.parent_id
 WHERE parent.standard_id <> child.standard_id;

SELECT count(*) AS orphaned_children
  FROM public.activity_category AS child
 WHERE child.level > 1 AND child.enabled AND child.parent_id IS NULL;

ROLLBACK;
