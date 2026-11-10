BEGIN;

\i test/setup.sql

-- STATBUS-598: the used-code views list exactly the classification codes some
-- statistical unit uses, with their ancestors. They walk the btree index of each
-- statistical_unit path column one distinct path at a time, so their content
-- must equal the plain definition: every code whose path is an ancestor-or-self
-- of a path present on any statistical unit.

CALL test.set_user_from_email('test.admin@statbus.org');

\o /dev/null
\set ECHO none
\i samples/demo/getting-started.sql
\o
\set ECHO all

INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment, time_frame_ident)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_job_provided'),
    'import_393_lu',
    'Import LU Demo CSV (393)',
    'Import job for legal_units_demo.csv',
    'Test data load (393)',
    'live';
\copy public.import_393_lu_upload(tax_ident,stat_ident,name,birth_date,physical_region_code,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code) FROM 'app/public/demo/legal_units_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

CALL worker.process_tasks(p_queue => 'import');
CALL worker.process_tasks(p_queue => 'analytics');

\echo "A secondary-only activity: used through the secondary path alone"
UPDATE public.statistical_unit
   SET secondary_activity_category_path = (
         SELECT ac.path FROM public.activity_category AS ac
          WHERE ac.enabled
            AND ac.standard_id = (SELECT activity_category_standard_id FROM public.settings)
            AND NOT EXISTS (SELECT 1 FROM public.statistical_unit AS su
                             WHERE su.primary_activity_category_path @> ac.path
                                OR su.primary_activity_category_path <@ ac.path)
          ORDER BY ac.path DESC LIMIT 1)
 WHERE (unit_type, unit_id, valid_from) = (
         SELECT unit_type, unit_id, valid_from FROM public.statistical_unit
          ORDER BY unit_type, unit_id, valid_from LIMIT 1);

CREATE TEMP TABLE used_paths AS
SELECT DISTINCT primary_activity_category_path AS activity_path, NULL::ltree AS region_path, NULL::ltree AS sector_path
  FROM public.statistical_unit WHERE primary_activity_category_path IS NOT NULL
UNION SELECT DISTINCT secondary_activity_category_path, NULL::ltree, NULL::ltree
  FROM public.statistical_unit WHERE secondary_activity_category_path IS NOT NULL
UNION SELECT DISTINCT NULL::ltree, physical_region_path, NULL::ltree
  FROM public.statistical_unit WHERE physical_region_path IS NOT NULL
UNION SELECT DISTINCT NULL::ltree, NULL::ltree, sector_path
  FROM public.statistical_unit WHERE sector_path IS NOT NULL;

\echo "Distinct paths in use"
SELECT count(activity_path) AS activity_paths,
       count(region_path) AS region_paths,
       count(sector_path) AS sector_paths
FROM used_paths;

\echo "Each view lists exactly the ancestor-or-self codes of the used paths"
SELECT
    (SELECT array_agg(path ORDER BY path) FROM public.activity_category_used_def)
    = (SELECT array_agg(ac.path ORDER BY ac.path) FROM public.activity_category AS ac
        WHERE ac.enabled AND ac.standard_id = (SELECT activity_category_standard_id FROM public.settings)
          AND EXISTS (SELECT 1 FROM used_paths AS u WHERE ac.path @> u.activity_path))
      AS activity_codes_exact,
    (SELECT array_agg(path ORDER BY path) FROM public.region_used_def)
    = (SELECT array_agg(r.path ORDER BY r.path) FROM public.region AS r
        WHERE EXISTS (SELECT 1 FROM used_paths AS u WHERE r.path @> u.region_path))
      AS region_codes_exact,
    (SELECT array_agg(path ORDER BY path) FROM public.sector_used_def)
    = (SELECT array_agg(s.path ORDER BY s.path) FROM public.sector AS s
        WHERE s.enabled AND EXISTS (SELECT 1 FROM used_paths AS u WHERE s.path @> u.sector_path))
      AS sector_codes_exact;

\echo "The secondary-only activity and its ancestors are listed"
SELECT count(*) AS secondary_only_activity_with_ancestors
FROM public.activity_category_used_def AS d
WHERE d.path @> (SELECT secondary_activity_category_path FROM public.statistical_unit
                  WHERE secondary_activity_category_path IS NOT NULL
                  ORDER BY unit_type, unit_id, valid_from LIMIT 1);

\echo "Ancestor regions of used regions are listed"
SELECT count(*) FILTER (WHERE nlevel(path) = 1) > 0 AS top_level_regions_listed,
       count(*) FILTER (WHERE nlevel(path) > 1) > 0 AS nested_regions_listed
FROM public.region_used_def;

ROLLBACK;
