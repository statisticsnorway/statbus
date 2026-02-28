BEGIN;

-- =============================================================================
-- Migration: Remove invalid_codes from the derive pipeline
-- =============================================================================
-- invalid_codes on statistical_unit is a remnant from before the import system
-- had per-row feedback. Now every import _data table has its own invalid_codes
-- and errors columns. Propagating through establishment -> timeline -> statistical_unit
-- is unnecessary overhead. Keep invalid_codes on import _data tables only.
-- =============================================================================

-- Step 1: Drop dependent views and functions (top-down)
DROP VIEW IF EXISTS public.statistical_unit_def;
DROP FUNCTION IF EXISTS public.relevant_statistical_units(statistical_unit_type, integer, date);
DROP FUNCTION IF EXISTS import.get_statistical_unit_data_partial(statistical_unit_type, int4multirange);
DROP VIEW IF EXISTS public.timeline_enterprise_def;
DROP VIEW IF EXISTS public.timeline_legal_unit_def;
DROP VIEW IF EXISTS public.timeline_establishment_def;

-- Step 2: Drop sql_saga __for_portion_of_valid views (they reference all columns)
SELECT sql_saga.drop_for_portion_of_view('public.legal_unit'::regclass);
SELECT sql_saga.drop_for_portion_of_view('public.establishment'::regclass);

-- Step 3: Drop indexes and columns
DROP INDEX IF EXISTS public.idx_statistical_unit_invalid_codes;
DROP INDEX IF EXISTS public.idx_statistical_unit_invalid_codes_exists;
ALTER TABLE public.statistical_unit DROP COLUMN IF EXISTS invalid_codes;
ALTER TABLE public.statistical_unit_staging DROP COLUMN IF EXISTS invalid_codes;
ALTER TABLE public.timeline_establishment DROP COLUMN IF EXISTS invalid_codes;
ALTER TABLE public.timeline_legal_unit DROP COLUMN IF EXISTS invalid_codes;
ALTER TABLE public.timeline_enterprise DROP COLUMN IF EXISTS invalid_codes;
ALTER TABLE public.legal_unit DROP COLUMN IF EXISTS invalid_codes;
ALTER TABLE public.establishment DROP COLUMN IF EXISTS invalid_codes;

-- Step 4: Recreate sql_saga views (now without invalid_codes column)
SELECT sql_saga.add_for_portion_of_view('public.legal_unit'::regclass);
SELECT sql_saga.add_for_portion_of_view('public.establishment'::regclass);

-- Step 5: Recreate views without invalid_codes (bottom-up)

-- timeline_establishment_def
CREATE OR REPLACE VIEW public.timeline_establishment_def
WITH (security_invoker='on') AS
WITH establishment_stats AS (
SELECT t_1.unit_id,
t_1.valid_from,
jsonb_stats_agg(sd.code::text, sfu.stat) FILTER (WHERE sd.code IS NOT NULL) AS stats
FROM timesegments t_1
JOIN stat_for_unit sfu ON sfu.establishment_id = t_1.unit_id AND from_until_overlaps(t_1.valid_from, t_1.valid_until, sfu.valid_from, sfu.valid_until)
JOIN stat_definition sd ON sfu.stat_definition_id = sd.id
WHERE t_1.unit_type = 'establishment'::statistical_unit_type
GROUP BY t_1.unit_id, t_1.valid_from
)
SELECT t.unit_type,
t.unit_id,
t.valid_from,
(t.valid_until - '1 day'::interval)::date AS valid_to,
t.valid_until,
es.name,
es.birth_date,
es.death_date,
to_tsvector('simple'::regconfig, es.name::text) AS search,
pa.category_id AS primary_activity_category_id,
pac.path AS primary_activity_category_path,
pac.code AS primary_activity_category_code,
sa.category_id AS secondary_activity_category_id,
sac.path AS secondary_activity_category_path,
sac.code AS secondary_activity_category_code,
NULLIF(array_remove(ARRAY[pac.path, sac.path], NULL::ltree), '{}'::ltree[]) AS activity_category_paths,
s.id AS sector_id,
s.path AS sector_path,
s.code AS sector_code,
s.name AS sector_name,
COALESCE(ds.ids, ARRAY[]::integer[]) AS data_source_ids,
COALESCE(ds.codes, ARRAY[]::text[]) AS data_source_codes,
NULL::integer AS legal_form_id,
NULL::text AS legal_form_code,
NULL::text AS legal_form_name,
phl.address_part1 AS physical_address_part1,
phl.address_part2 AS physical_address_part2,
phl.address_part3 AS physical_address_part3,
phl.postcode AS physical_postcode,
phl.postplace AS physical_postplace,
phl.region_id AS physical_region_id,
phr.path AS physical_region_path,
phr.code AS physical_region_code,
phl.country_id AS physical_country_id,
phc.iso_2 AS physical_country_iso_2,
phl.latitude AS physical_latitude,
phl.longitude AS physical_longitude,
phl.altitude AS physical_altitude,
current_settings.country_id = phl.country_id AS domestic,
pol.address_part1 AS postal_address_part1,
pol.address_part2 AS postal_address_part2,
pol.address_part3 AS postal_address_part3,
pol.postcode AS postal_postcode,
pol.postplace AS postal_postplace,
pol.region_id AS postal_region_id,
por.path AS postal_region_path,
por.code AS postal_region_code,
pol.country_id AS postal_country_id,
poc.iso_2 AS postal_country_iso_2,
pol.latitude AS postal_latitude,
pol.longitude AS postal_longitude,
pol.altitude AS postal_altitude,
c.web_address,
c.email_address,
c.phone_number,
c.landline,
c.mobile_number,
c.fax_number,
es.unit_size_id,
us.code AS unit_size_code,
es.status_id,
st.code AS status_code,
st.used_for_counting,
last_edit.edit_comment AS last_edit_comment,
last_edit.edit_by_user_id AS last_edit_by_user_id,
last_edit.edit_at AS last_edit_at,
es.legal_unit_id IS NOT NULL AS has_legal_unit,
es.id AS establishment_id,
es.legal_unit_id,
es.enterprise_id,
es.primary_for_enterprise,
es.primary_for_legal_unit,
COALESCE(es_stats.stats, '{}'::jsonb) AS stats,
jsonb_stats_to_agg(COALESCE(es_stats.stats, '{}'::jsonb)) AS stats_summary,
ARRAY[t.unit_id] AS related_establishment_ids,
ARRAY[]::integer[] AS excluded_establishment_ids,
CASE
WHEN st.used_for_counting THEN ARRAY[t.unit_id]
ELSE '{}'::integer[]
END AS included_establishment_ids,
CASE
WHEN es.legal_unit_id IS NOT NULL THEN ARRAY[es.legal_unit_id]
ELSE ARRAY[]::integer[]
END AS related_legal_unit_ids,
ARRAY[]::integer[] AS excluded_legal_unit_ids,
ARRAY[]::integer[] AS included_legal_unit_ids,
CASE
WHEN es.enterprise_id IS NOT NULL THEN ARRAY[es.enterprise_id]
ELSE ARRAY[]::integer[]
END AS related_enterprise_ids,
ARRAY[]::integer[] AS excluded_enterprise_ids,
ARRAY[]::integer[] AS included_enterprise_ids
FROM timesegments t
JOIN LATERAL ( SELECT es_1.id,
es_1.valid_range,
es_1.valid_from,
es_1.valid_to,
es_1.valid_until,
es_1.short_name,
es_1.name,
es_1.birth_date,
es_1.death_date,
es_1.free_econ_zone,
es_1.sector_id,
es_1.status_id,
es_1.edit_comment,
es_1.edit_by_user_id,
es_1.edit_at,
es_1.unit_size_id,
es_1.data_source_id,
es_1.enterprise_id,
es_1.legal_unit_id,
es_1.primary_for_legal_unit,
es_1.primary_for_enterprise,
es_1.image_id
FROM establishment es_1
WHERE es_1.id = t.unit_id AND from_until_overlaps(t.valid_from, t.valid_until, es_1.valid_from, es_1.valid_until)
ORDER BY es_1.id DESC, es_1.valid_from DESC
LIMIT 1) es ON true
LEFT JOIN establishment_stats es_stats ON es_stats.unit_id = t.unit_id AND es_stats.valid_from = t.valid_from
LEFT JOIN LATERAL ( SELECT a.id,
a.valid_range,
a.valid_from,
a.valid_to,
a.valid_until,
a.type,
a.category_id,
a.data_source_id,
a.edit_comment,
a.edit_by_user_id,
a.edit_at,
a.establishment_id,
a.legal_unit_id
FROM activity a
WHERE a.establishment_id = es.id AND a.type = 'primary'::activity_type AND from_until_overlaps(t.valid_from, t.valid_until, a.valid_from, a.valid_until)
ORDER BY a.id DESC
LIMIT 1) pa ON true
LEFT JOIN activity_category pac ON pa.category_id = pac.id
LEFT JOIN LATERAL ( SELECT a.id,
a.valid_range,
a.valid_from,
a.valid_to,
a.valid_until,
a.type,
a.category_id,
a.data_source_id,
a.edit_comment,
a.edit_by_user_id,
a.edit_at,
a.establishment_id,
a.legal_unit_id
FROM activity a
WHERE a.establishment_id = es.id AND a.type = 'secondary'::activity_type AND from_until_overlaps(t.valid_from, t.valid_until, a.valid_from, a.valid_until)
ORDER BY a.id DESC
LIMIT 1) sa ON true
LEFT JOIN activity_category sac ON sa.category_id = sac.id
LEFT JOIN sector s ON es.sector_id = s.id
LEFT JOIN LATERAL ( SELECT l.id,
l.valid_range,
l.valid_from,
l.valid_to,
l.valid_until,
l.type,
l.address_part1,
l.address_part2,
l.address_part3,
l.postcode,
l.postplace,
l.region_id,
l.country_id,
l.latitude,
l.longitude,
l.altitude,
l.establishment_id,
l.legal_unit_id,
l.data_source_id,
l.edit_comment,
l.edit_by_user_id,
l.edit_at
FROM location l
WHERE l.establishment_id = es.id AND l.type = 'physical'::location_type AND from_until_overlaps(t.valid_from, t.valid_until, l.valid_from, l.valid_until)
ORDER BY l.id DESC
LIMIT 1) phl ON true
LEFT JOIN region phr ON phl.region_id = phr.id
LEFT JOIN country phc ON phl.country_id = phc.id
LEFT JOIN LATERAL ( SELECT l.id,
l.valid_range,
l.valid_from,
l.valid_to,
l.valid_until,
l.type,
l.address_part1,
l.address_part2,
l.address_part3,
l.postcode,
l.postplace,
l.region_id,
l.country_id,
l.latitude,
l.longitude,
l.altitude,
l.establishment_id,
l.legal_unit_id,
l.data_source_id,
l.edit_comment,
l.edit_by_user_id,
l.edit_at
FROM location l
WHERE l.establishment_id = es.id AND l.type = 'postal'::location_type AND from_until_overlaps(t.valid_from, t.valid_until, l.valid_from, l.valid_until)
ORDER BY l.id DESC
LIMIT 1) pol ON true
LEFT JOIN region por ON pol.region_id = por.id
LEFT JOIN country poc ON pol.country_id = poc.id
LEFT JOIN LATERAL ( SELECT c_1.id,
c_1.valid_range,
c_1.valid_from,
c_1.valid_to,
c_1.valid_until,
c_1.web_address,
c_1.email_address,
c_1.phone_number,
c_1.landline,
c_1.mobile_number,
c_1.fax_number,
c_1.establishment_id,
c_1.legal_unit_id,
c_1.data_source_id,
c_1.edit_comment,
c_1.edit_by_user_id,
c_1.edit_at
FROM contact c_1
WHERE c_1.establishment_id = es.id AND from_until_overlaps(t.valid_from, t.valid_until, c_1.valid_from, c_1.valid_until)
ORDER BY c_1.id DESC
LIMIT 1) c ON true
LEFT JOIN unit_size us ON es.unit_size_id = us.id
LEFT JOIN status st ON es.status_id = st.id
LEFT JOIN LATERAL ( SELECT array_agg(DISTINCT sfu.data_source_id) FILTER (WHERE sfu.data_source_id IS NOT NULL) AS data_source_ids
FROM stat_for_unit sfu
WHERE sfu.establishment_id = es.id AND from_until_overlaps(t.valid_from, t.valid_until, sfu.valid_from, sfu.valid_until)) sfu_ds ON true
LEFT JOIN LATERAL ( SELECT sfu.edit_comment,
sfu.edit_by_user_id,
sfu.edit_at
FROM stat_for_unit sfu
WHERE sfu.establishment_id = es.id AND from_until_overlaps(t.valid_from, t.valid_until, sfu.valid_from, sfu.valid_until)
ORDER BY sfu.edit_at DESC
LIMIT 1) sfu_le ON true
LEFT JOIN LATERAL ( SELECT array_agg(ds_1.id) AS ids,
array_agg(ds_1.code) AS codes
FROM data_source ds_1
WHERE COALESCE(ds_1.id = es.data_source_id, false) OR COALESCE(ds_1.id = pa.data_source_id, false) OR COALESCE(ds_1.id = sa.data_source_id, false) OR COALESCE(ds_1.id = phl.data_source_id, false) OR COALESCE(ds_1.id = pol.data_source_id, false) OR COALESCE(ds_1.id = ANY (sfu_ds.data_source_ids), false)) ds ON true
LEFT JOIN LATERAL ( SELECT all_edits.edit_comment,
all_edits.edit_by_user_id,
all_edits.edit_at
FROM ( VALUES (es.edit_comment,es.edit_by_user_id,es.edit_at), (pa.edit_comment,pa.edit_by_user_id,pa.edit_at), (sa.edit_comment,sa.edit_by_user_id,sa.edit_at), (phl.edit_comment,phl.edit_by_user_id,phl.edit_at), (pol.edit_comment,pol.edit_by_user_id,pol.edit_at), (c.edit_comment,c.edit_by_user_id,c.edit_at), (sfu_le.edit_comment,sfu_le.edit_by_user_id,sfu_le.edit_at)) all_edits(edit_comment, edit_by_user_id, edit_at)
WHERE all_edits.edit_at IS NOT NULL
ORDER BY all_edits.edit_at DESC
LIMIT 1) last_edit ON true,
settings current_settings
ORDER BY t.unit_type, t.unit_id, t.valid_from
;

-- timeline_legal_unit_def
CREATE OR REPLACE VIEW public.timeline_legal_unit_def
WITH (security_invoker='on') AS
WITH filter_ids AS (
SELECT string_to_array(NULLIF(current_setting('statbus.filter_unit_ids'::text, true), ''::text), ','::text)::integer[] AS ids
), legal_unit_stats AS (
SELECT t.unit_id,
t.valid_from,
jsonb_stats_agg(sd.code::text, sfu.stat) FILTER (WHERE sd.code IS NOT NULL) AS stats
FROM timesegments t
CROSS JOIN filter_ids f
JOIN stat_for_unit sfu ON sfu.legal_unit_id = t.unit_id AND from_until_overlaps(t.valid_from, t.valid_until, sfu.valid_from, sfu.valid_until)
JOIN stat_definition sd ON sfu.stat_definition_id = sd.id
WHERE t.unit_type = 'legal_unit'::statistical_unit_type AND (f.ids IS NULL OR (t.unit_id = ANY (f.ids)))
GROUP BY t.unit_id, t.valid_from
), establishment_aggs AS (
SELECT t.unit_id,
t.valid_from,
array_distinct_concat(tes.data_source_ids) AS data_source_ids,
array_distinct_concat(tes.data_source_codes) AS data_source_codes,
array_agg(DISTINCT tes.establishment_id) FILTER (WHERE tes.establishment_id IS NOT NULL) AS related_establishment_ids,
array_agg(DISTINCT tes.establishment_id) FILTER (WHERE tes.establishment_id IS NOT NULL AND NOT tes.used_for_counting) AS excluded_establishment_ids,
array_agg(DISTINCT tes.establishment_id) FILTER (WHERE tes.establishment_id IS NOT NULL AND tes.used_for_counting) AS included_establishment_ids,
jsonb_stats_merge_agg(tes.stats_summary) FILTER (WHERE tes.used_for_counting) AS stats_summary
FROM timesegments t
CROSS JOIN filter_ids f
JOIN timeline_establishment tes ON tes.legal_unit_id = t.unit_id AND from_until_overlaps(t.valid_from, t.valid_until, tes.valid_from, tes.valid_until)
WHERE t.unit_type = 'legal_unit'::statistical_unit_type AND (f.ids IS NULL OR (t.unit_id = ANY (f.ids)))
GROUP BY t.unit_id, t.valid_from
), basis AS (
SELECT t.unit_type,
t.unit_id,
t.valid_from,
(t.valid_until - '1 day'::interval)::date AS valid_to,
t.valid_until,
lu.name,
lu.birth_date,
lu.death_date,
to_tsvector('simple'::regconfig, lu.name::text) AS search,
pa.category_id AS primary_activity_category_id,
pac.path AS primary_activity_category_path,
pac.code AS primary_activity_category_code,
sa.category_id AS secondary_activity_category_id,
sac.path AS secondary_activity_category_path,
sac.code AS secondary_activity_category_code,
NULLIF(array_remove(ARRAY[pac.path, sac.path], NULL::ltree), '{}'::ltree[]) AS activity_category_paths,
s.id AS sector_id,
s.path AS sector_path,
s.code AS sector_code,
s.name AS sector_name,
COALESCE(ds.ids, ARRAY[]::integer[]) AS data_source_ids,
COALESCE(ds.codes, ARRAY[]::text[]) AS data_source_codes,
lf.id AS legal_form_id,
lf.code AS legal_form_code,
lf.name AS legal_form_name,
phl.address_part1 AS physical_address_part1,
phl.address_part2 AS physical_address_part2,
phl.address_part3 AS physical_address_part3,
phl.postcode AS physical_postcode,
phl.postplace AS physical_postplace,
phl.region_id AS physical_region_id,
phr.path AS physical_region_path,
phr.code AS physical_region_code,
phl.country_id AS physical_country_id,
phc.iso_2 AS physical_country_iso_2,
phl.latitude AS physical_latitude,
phl.longitude AS physical_longitude,
phl.altitude AS physical_altitude,
current_settings.country_id = phl.country_id AS domestic,
pol.address_part1 AS postal_address_part1,
pol.address_part2 AS postal_address_part2,
pol.address_part3 AS postal_address_part3,
pol.postcode AS postal_postcode,
pol.postplace AS postal_postplace,
pol.region_id AS postal_region_id,
por.path AS postal_region_path,
por.code AS postal_region_code,
pol.country_id AS postal_country_id,
poc.iso_2 AS postal_country_iso_2,
pol.latitude AS postal_latitude,
pol.longitude AS postal_longitude,
pol.altitude AS postal_altitude,
c.web_address,
c.email_address,
c.phone_number,
c.landline,
c.mobile_number,
c.fax_number,
lu.unit_size_id,
us.code AS unit_size_code,
lu.status_id,
st.code AS status_code,
st.used_for_counting,
last_edit.edit_comment AS last_edit_comment,
last_edit.edit_by_user_id AS last_edit_by_user_id,
last_edit.edit_at AS last_edit_at,
true AS has_legal_unit,
lu.id AS legal_unit_id,
lu.enterprise_id,
lu.primary_for_enterprise,
COALESCE(lu_stats.stats, '{}'::jsonb) AS stats,
jsonb_stats_to_agg(COALESCE(lu_stats.stats, '{}'::jsonb)) AS stats_summary
FROM timesegments t
CROSS JOIN filter_ids f
JOIN LATERAL ( SELECT lu_1.id,
lu_1.valid_range,
lu_1.valid_from,
lu_1.valid_to,
lu_1.valid_until,
lu_1.short_name,
lu_1.name,
lu_1.birth_date,
lu_1.death_date,
lu_1.free_econ_zone,
lu_1.sector_id,
lu_1.status_id,
lu_1.legal_form_id,
lu_1.edit_comment,
lu_1.edit_by_user_id,
lu_1.edit_at,
lu_1.unit_size_id,
lu_1.foreign_participation_id,
lu_1.data_source_id,
lu_1.enterprise_id,
lu_1.primary_for_enterprise,
lu_1.image_id
FROM legal_unit lu_1
WHERE lu_1.id = t.unit_id AND from_until_overlaps(t.valid_from, t.valid_until, lu_1.valid_from, lu_1.valid_until)
ORDER BY lu_1.id DESC, lu_1.valid_from DESC
LIMIT 1) lu ON true
LEFT JOIN legal_unit_stats lu_stats ON lu_stats.unit_id = t.unit_id AND lu_stats.valid_from = t.valid_from
LEFT JOIN LATERAL ( SELECT a.id,
a.valid_range,
a.valid_from,
a.valid_to,
a.valid_until,
a.type,
a.category_id,
a.data_source_id,
a.edit_comment,
a.edit_by_user_id,
a.edit_at,
a.establishment_id,
a.legal_unit_id
FROM activity a
WHERE a.legal_unit_id = lu.id AND a.type = 'primary'::activity_type AND from_until_overlaps(t.valid_from, t.valid_until, a.valid_from, a.valid_until)
ORDER BY a.id DESC
LIMIT 1) pa ON true
LEFT JOIN activity_category pac ON pa.category_id = pac.id
LEFT JOIN LATERAL ( SELECT a.id,
a.valid_range,
a.valid_from,
a.valid_to,
a.valid_until,
a.type,
a.category_id,
a.data_source_id,
a.edit_comment,
a.edit_by_user_id,
a.edit_at,
a.establishment_id,
a.legal_unit_id
FROM activity a
WHERE a.legal_unit_id = lu.id AND a.type = 'secondary'::activity_type AND from_until_overlaps(t.valid_from, t.valid_until, a.valid_from, a.valid_until)
ORDER BY a.id DESC
LIMIT 1) sa ON true
LEFT JOIN activity_category sac ON sa.category_id = sac.id
LEFT JOIN sector s ON lu.sector_id = s.id
LEFT JOIN legal_form lf ON lu.legal_form_id = lf.id
LEFT JOIN LATERAL ( SELECT l.id,
l.valid_range,
l.valid_from,
l.valid_to,
l.valid_until,
l.type,
l.address_part1,
l.address_part2,
l.address_part3,
l.postcode,
l.postplace,
l.region_id,
l.country_id,
l.latitude,
l.longitude,
l.altitude,
l.establishment_id,
l.legal_unit_id,
l.data_source_id,
l.edit_comment,
l.edit_by_user_id,
l.edit_at
FROM location l
WHERE l.legal_unit_id = lu.id AND l.type = 'physical'::location_type AND from_until_overlaps(t.valid_from, t.valid_until, l.valid_from, l.valid_until)
ORDER BY l.id DESC
LIMIT 1) phl ON true
LEFT JOIN region phr ON phl.region_id = phr.id
LEFT JOIN country phc ON phl.country_id = phc.id
LEFT JOIN LATERAL ( SELECT l.id,
l.valid_range,
l.valid_from,
l.valid_to,
l.valid_until,
l.type,
l.address_part1,
l.address_part2,
l.address_part3,
l.postcode,
l.postplace,
l.region_id,
l.country_id,
l.latitude,
l.longitude,
l.altitude,
l.establishment_id,
l.legal_unit_id,
l.data_source_id,
l.edit_comment,
l.edit_by_user_id,
l.edit_at
FROM location l
WHERE l.legal_unit_id = lu.id AND l.type = 'postal'::location_type AND from_until_overlaps(t.valid_from, t.valid_until, l.valid_from, l.valid_until)
ORDER BY l.id DESC
LIMIT 1) pol ON true
LEFT JOIN region por ON pol.region_id = por.id
LEFT JOIN country poc ON pol.country_id = poc.id
LEFT JOIN LATERAL ( SELECT c_1.id,
c_1.valid_range,
c_1.valid_from,
c_1.valid_to,
c_1.valid_until,
c_1.web_address,
c_1.email_address,
c_1.phone_number,
c_1.landline,
c_1.mobile_number,
c_1.fax_number,
c_1.establishment_id,
c_1.legal_unit_id,
c_1.data_source_id,
c_1.edit_comment,
c_1.edit_by_user_id,
c_1.edit_at
FROM contact c_1
WHERE c_1.legal_unit_id = lu.id AND from_until_overlaps(t.valid_from, t.valid_until, c_1.valid_from, c_1.valid_until)
ORDER BY c_1.id DESC
LIMIT 1) c ON true
LEFT JOIN unit_size us ON lu.unit_size_id = us.id
LEFT JOIN status st ON lu.status_id = st.id
LEFT JOIN LATERAL ( SELECT array_agg(DISTINCT sfu.data_source_id) FILTER (WHERE sfu.data_source_id IS NOT NULL) AS data_source_ids
FROM stat_for_unit sfu
WHERE sfu.legal_unit_id = lu.id AND from_until_overlaps(t.valid_from, t.valid_until, sfu.valid_from, sfu.valid_until)) sfu_ds ON true
LEFT JOIN LATERAL ( SELECT sfu.edit_comment,
sfu.edit_by_user_id,
sfu.edit_at
FROM stat_for_unit sfu
WHERE sfu.legal_unit_id = lu.id AND from_until_overlaps(t.valid_from, t.valid_until, sfu.valid_from, sfu.valid_until)
ORDER BY sfu.edit_at DESC
LIMIT 1) sfu_le ON true
LEFT JOIN LATERAL ( SELECT array_agg(ds_1.id) AS ids,
array_agg(ds_1.code) AS codes
FROM data_source ds_1
WHERE COALESCE(ds_1.id = lu.data_source_id, false) OR COALESCE(ds_1.id = pa.data_source_id, false) OR COALESCE(ds_1.id = sa.data_source_id, false) OR COALESCE(ds_1.id = phl.data_source_id, false) OR COALESCE(ds_1.id = pol.data_source_id, false) OR COALESCE(ds_1.id = ANY (sfu_ds.data_source_ids), false)) ds ON true
LEFT JOIN LATERAL ( SELECT all_edits.edit_comment,
all_edits.edit_by_user_id,
all_edits.edit_at
FROM ( VALUES (lu.edit_comment,lu.edit_by_user_id,lu.edit_at), (pa.edit_comment,pa.edit_by_user_id,pa.edit_at), (sa.edit_comment,sa.edit_by_user_id,sa.edit_at), (phl.edit_comment,phl.edit_by_user_id,phl.edit_at), (pol.edit_comment,pol.edit_by_user_id,pol.edit_at), (c.edit_comment,c.edit_by_user_id,c.edit_at), (sfu_le.edit_comment,sfu_le.edit_by_user_id,sfu_le.edit_at)) all_edits(edit_comment, edit_by_user_id, edit_at)
WHERE all_edits.edit_at IS NOT NULL
ORDER BY all_edits.edit_at DESC
LIMIT 1) last_edit ON true,
settings current_settings
WHERE t.unit_type = 'legal_unit'::statistical_unit_type AND (f.ids IS NULL OR (t.unit_id = ANY (f.ids)))
)
SELECT basis.unit_type,
basis.unit_id,
basis.valid_from,
basis.valid_to,
basis.valid_until,
basis.name,
basis.birth_date,
basis.death_date,
basis.search,
basis.primary_activity_category_id,
basis.primary_activity_category_path,
basis.primary_activity_category_code,
basis.secondary_activity_category_id,
basis.secondary_activity_category_path,
basis.secondary_activity_category_code,
basis.activity_category_paths,
basis.sector_id,
basis.sector_path,
basis.sector_code,
basis.sector_name,
( SELECT array_agg(DISTINCT ids.id) AS array_agg
FROM ( SELECT unnest(basis.data_source_ids) AS id
UNION ALL
SELECT unnest(esa.data_source_ids) AS id) ids) AS data_source_ids,
( SELECT array_agg(DISTINCT codes.code) AS array_agg
FROM ( SELECT unnest(basis.data_source_codes) AS code
UNION ALL
SELECT unnest(esa.data_source_codes) AS code) codes) AS data_source_codes,
basis.legal_form_id,
basis.legal_form_code,
basis.legal_form_name,
basis.physical_address_part1,
basis.physical_address_part2,
basis.physical_address_part3,
basis.physical_postcode,
basis.physical_postplace,
basis.physical_region_id,
basis.physical_region_path,
basis.physical_region_code,
basis.physical_country_id,
basis.physical_country_iso_2,
basis.physical_latitude,
basis.physical_longitude,
basis.physical_altitude,
basis.domestic,
basis.postal_address_part1,
basis.postal_address_part2,
basis.postal_address_part3,
basis.postal_postcode,
basis.postal_postplace,
basis.postal_region_id,
basis.postal_region_path,
basis.postal_region_code,
basis.postal_country_id,
basis.postal_country_iso_2,
basis.postal_latitude,
basis.postal_longitude,
basis.postal_altitude,
basis.web_address,
basis.email_address,
basis.phone_number,
basis.landline,
basis.mobile_number,
basis.fax_number,
basis.unit_size_id,
basis.unit_size_code,
basis.status_id,
basis.status_code,
basis.used_for_counting,
basis.last_edit_comment,
basis.last_edit_by_user_id,
basis.last_edit_at,
basis.has_legal_unit,
COALESCE(esa.related_establishment_ids, ARRAY[]::integer[]) AS related_establishment_ids,
COALESCE(esa.excluded_establishment_ids, ARRAY[]::integer[]) AS excluded_establishment_ids,
COALESCE(esa.included_establishment_ids, ARRAY[]::integer[]) AS included_establishment_ids,
ARRAY[basis.unit_id] AS related_legal_unit_ids,
ARRAY[]::integer[] AS excluded_legal_unit_ids,
CASE
WHEN basis.used_for_counting THEN ARRAY[basis.unit_id]
ELSE '{}'::integer[]
END AS included_legal_unit_ids,
CASE
WHEN basis.enterprise_id IS NOT NULL THEN ARRAY[basis.enterprise_id]
ELSE ARRAY[]::integer[]
END AS related_enterprise_ids,
ARRAY[]::integer[] AS excluded_enterprise_ids,
ARRAY[]::integer[] AS included_enterprise_ids,
basis.legal_unit_id,
basis.enterprise_id,
basis.primary_for_enterprise,
basis.stats,
CASE
WHEN basis.used_for_counting THEN COALESCE(jsonb_stats_merge(esa.stats_summary, basis.stats_summary), basis.stats_summary, esa.stats_summary, '{}'::jsonb)
ELSE '{}'::jsonb
END AS stats_summary
FROM basis
LEFT JOIN establishment_aggs esa ON esa.unit_id = basis.unit_id AND esa.valid_from = basis.valid_from
ORDER BY basis.unit_type, basis.unit_id, basis.valid_from
;

-- timeline_enterprise_def
CREATE OR REPLACE VIEW public.timeline_enterprise_def
WITH (security_invoker='on') AS
WITH aggregation AS (
SELECT ten.enterprise_id,
ten.valid_from,
ten.valid_until,
array_distinct_concat(COALESCE(array_cat(tlu.data_source_ids, tes.data_source_ids), tlu.data_source_ids, tes.data_source_ids)) AS data_source_ids,
array_distinct_concat(COALESCE(array_cat(tlu.data_source_codes, tes.data_source_codes), tlu.data_source_codes, tes.data_source_codes)) AS data_source_codes,
array_distinct_concat(COALESCE(array_cat(tlu.related_establishment_ids, tes.related_establishment_ids), tlu.related_establishment_ids, tes.related_establishment_ids)) AS related_establishment_ids,
array_distinct_concat(COALESCE(array_cat(tlu.excluded_establishment_ids, tes.excluded_establishment_ids), tlu.excluded_establishment_ids, tes.excluded_establishment_ids)) AS excluded_establishment_ids,
array_distinct_concat(COALESCE(array_cat(tlu.included_establishment_ids, tes.included_establishment_ids), tlu.included_establishment_ids, tes.included_establishment_ids)) AS included_establishment_ids,
array_distinct_concat(tlu.related_legal_unit_ids) AS related_legal_unit_ids,
array_distinct_concat(tlu.excluded_legal_unit_ids) AS excluded_legal_unit_ids,
array_distinct_concat(tlu.included_legal_unit_ids) AS included_legal_unit_ids,
COALESCE(jsonb_stats_merge_agg(COALESCE(jsonb_stats_merge(tlu.stats_summary, tes.stats_summary), tlu.stats_summary, tes.stats_summary)), '{}'::jsonb) AS stats_summary
FROM ( SELECT t.unit_type,
t.unit_id,
t.valid_from,
t.valid_until,
en.id,
en.enabled,
en.short_name,
en.edit_comment,
en.edit_by_user_id,
en.edit_at,
en.id AS enterprise_id
FROM timesegments t
JOIN enterprise en ON t.unit_type = 'enterprise'::statistical_unit_type AND t.unit_id = en.id) ten
LEFT JOIN LATERAL ( SELECT timeline_legal_unit.enterprise_id,
ten.valid_from,
ten.valid_until,
array_distinct_concat(timeline_legal_unit.data_source_ids) AS data_source_ids,
array_distinct_concat(timeline_legal_unit.data_source_codes) AS data_source_codes,
array_distinct_concat(timeline_legal_unit.related_establishment_ids) AS related_establishment_ids,
array_distinct_concat(timeline_legal_unit.excluded_establishment_ids) AS excluded_establishment_ids,
array_distinct_concat(timeline_legal_unit.included_establishment_ids) AS included_establishment_ids,
array_agg(DISTINCT timeline_legal_unit.legal_unit_id) AS related_legal_unit_ids,
array_agg(DISTINCT timeline_legal_unit.legal_unit_id) FILTER (WHERE NOT timeline_legal_unit.used_for_counting) AS excluded_legal_unit_ids,
array_agg(DISTINCT timeline_legal_unit.legal_unit_id) FILTER (WHERE timeline_legal_unit.used_for_counting) AS included_legal_unit_ids,
jsonb_stats_merge_agg(timeline_legal_unit.stats_summary) FILTER (WHERE timeline_legal_unit.used_for_counting) AS stats_summary
FROM timeline_legal_unit
WHERE timeline_legal_unit.enterprise_id = ten.enterprise_id AND from_until_overlaps(ten.valid_from, ten.valid_until, timeline_legal_unit.valid_from, timeline_legal_unit.valid_until)
GROUP BY timeline_legal_unit.enterprise_id, ten.valid_from, ten.valid_until) tlu ON true
LEFT JOIN LATERAL ( SELECT timeline_establishment.enterprise_id,
ten.valid_from,
ten.valid_until,
array_distinct_concat(timeline_establishment.data_source_ids) AS data_source_ids,
array_distinct_concat(timeline_establishment.data_source_codes) AS data_source_codes,
array_agg(DISTINCT timeline_establishment.establishment_id) AS related_establishment_ids,
array_agg(DISTINCT timeline_establishment.establishment_id) FILTER (WHERE NOT timeline_establishment.used_for_counting) AS excluded_establishment_ids,
array_agg(DISTINCT timeline_establishment.establishment_id) FILTER (WHERE timeline_establishment.used_for_counting) AS included_establishment_ids,
jsonb_stats_merge_agg(timeline_establishment.stats_summary) FILTER (WHERE timeline_establishment.used_for_counting) AS stats_summary
FROM timeline_establishment
WHERE timeline_establishment.enterprise_id = ten.enterprise_id AND from_until_overlaps(ten.valid_from, ten.valid_until, timeline_establishment.valid_from, timeline_establishment.valid_until)
GROUP BY timeline_establishment.enterprise_id, ten.valid_from, ten.valid_until) tes ON true
GROUP BY ten.enterprise_id, ten.valid_from, ten.valid_until
), enterprise_with_primary_and_aggregation AS (
SELECT ( SELECT array_agg(DISTINCT ids.id) AS array_agg
FROM ( SELECT unnest(basis.data_source_ids) AS id
UNION
SELECT unnest(aggregation.data_source_ids) AS id) ids) AS data_source_ids,
( SELECT array_agg(DISTINCT codes.code) AS array_agg
FROM ( SELECT unnest(basis.data_source_codes) AS code
UNION ALL
SELECT unnest(aggregation.data_source_codes) AS code) codes) AS data_source_codes,
basis.unit_type,
basis.unit_id,
basis.valid_from,
basis.valid_until,
basis.enterprise_id,
basis.name,
basis.birth_date,
basis.death_date,
basis.primary_activity_category_id,
basis.primary_activity_category_path,
basis.primary_activity_category_code,
basis.secondary_activity_category_id,
basis.secondary_activity_category_path,
basis.secondary_activity_category_code,
basis.sector_id,
basis.sector_path,
basis.sector_code,
basis.sector_name,
basis.legal_form_id,
basis.legal_form_code,
basis.legal_form_name,
basis.physical_address_part1,
basis.physical_address_part2,
basis.physical_address_part3,
basis.physical_postcode,
basis.physical_postplace,
basis.physical_region_id,
basis.physical_region_path,
basis.physical_region_code,
basis.physical_country_id,
basis.physical_country_iso_2,
basis.physical_latitude,
basis.physical_longitude,
basis.physical_altitude,
basis.domestic,
basis.postal_address_part1,
basis.postal_address_part2,
basis.postal_address_part3,
basis.postal_postcode,
basis.postal_postplace,
basis.postal_region_id,
basis.postal_region_path,
basis.postal_region_code,
basis.postal_country_id,
basis.postal_country_iso_2,
basis.postal_latitude,
basis.postal_longitude,
basis.postal_altitude,
basis.web_address,
basis.email_address,
basis.phone_number,
basis.landline,
basis.mobile_number,
basis.fax_number,
basis.unit_size_id,
basis.unit_size_code,
basis.status_id,
basis.status_code,
basis.used_for_counting,
basis.last_edit_comment,
basis.last_edit_by_user_id,
basis.last_edit_at,
basis.has_legal_unit,
basis.primary_legal_unit_id,
basis.primary_establishment_id,
aggregation.related_establishment_ids,
aggregation.excluded_establishment_ids,
aggregation.included_establishment_ids,
aggregation.related_legal_unit_ids,
aggregation.excluded_legal_unit_ids,
aggregation.included_legal_unit_ids,
aggregation.stats_summary
FROM ( SELECT ten.unit_type,
ten.unit_id,
ten.valid_from,
ten.valid_until,
ten.enterprise_id,
COALESCE(NULLIF(ten.short_name::text, ''::text), enplu.name::text, enpes.name::text) AS name,
COALESCE(enplu.birth_date, enpes.birth_date) AS birth_date,
COALESCE(enplu.death_date, enpes.death_date) AS death_date,
COALESCE(enplu.primary_activity_category_id, enpes.primary_activity_category_id) AS primary_activity_category_id,
COALESCE(enplu.primary_activity_category_path, enpes.primary_activity_category_path) AS primary_activity_category_path,
COALESCE(enplu.primary_activity_category_code, enpes.primary_activity_category_code) AS primary_activity_category_code,
COALESCE(enplu.secondary_activity_category_id, enpes.secondary_activity_category_id) AS secondary_activity_category_id,
COALESCE(enplu.secondary_activity_category_path, enpes.secondary_activity_category_path) AS secondary_activity_category_path,
COALESCE(enplu.secondary_activity_category_code, enpes.secondary_activity_category_code) AS secondary_activity_category_code,
COALESCE(enplu.sector_id, enpes.sector_id) AS sector_id,
COALESCE(enplu.sector_path, enpes.sector_path) AS sector_path,
COALESCE(enplu.sector_code, enpes.sector_code) AS sector_code,
COALESCE(enplu.sector_name, enpes.sector_name) AS sector_name,
( SELECT array_agg(DISTINCT ids.id) AS array_agg
FROM ( SELECT unnest(enplu.data_source_ids) AS id
UNION
SELECT unnest(enpes.data_source_ids) AS id) ids) AS data_source_ids,
( SELECT array_agg(DISTINCT codes.code) AS array_agg
FROM ( SELECT unnest(enplu.data_source_codes) AS code
UNION
SELECT unnest(enpes.data_source_codes) AS code) codes) AS data_source_codes,
enplu.legal_form_id,
enplu.legal_form_code,
enplu.legal_form_name,
COALESCE(enplu.physical_address_part1, enpes.physical_address_part1) AS physical_address_part1,
COALESCE(enplu.physical_address_part2, enpes.physical_address_part2) AS physical_address_part2,
COALESCE(enplu.physical_address_part3, enpes.physical_address_part3) AS physical_address_part3,
COALESCE(enplu.physical_postcode, enpes.physical_postcode) AS physical_postcode,
COALESCE(enplu.physical_postplace, enpes.physical_postplace) AS physical_postplace,
COALESCE(enplu.physical_region_id, enpes.physical_region_id) AS physical_region_id,
COALESCE(enplu.physical_region_path, enpes.physical_region_path) AS physical_region_path,
COALESCE(enplu.physical_region_code, enpes.physical_region_code) AS physical_region_code,
COALESCE(enplu.physical_country_id, enpes.physical_country_id) AS physical_country_id,
COALESCE(enplu.physical_country_iso_2, enpes.physical_country_iso_2) AS physical_country_iso_2,
COALESCE(enplu.physical_latitude, enpes.physical_latitude) AS physical_latitude,
COALESCE(enplu.physical_longitude, enpes.physical_longitude) AS physical_longitude,
COALESCE(enplu.physical_altitude, enpes.physical_altitude) AS physical_altitude,
COALESCE(enplu.domestic, enpes.domestic) AS domestic,
COALESCE(enplu.postal_address_part1, enpes.postal_address_part1) AS postal_address_part1,
COALESCE(enplu.postal_address_part2, enpes.postal_address_part2) AS postal_address_part2,
COALESCE(enplu.postal_address_part3, enpes.postal_address_part3) AS postal_address_part3,
COALESCE(enplu.postal_postcode, enpes.postal_postcode) AS postal_postcode,
COALESCE(enplu.postal_postplace, enpes.postal_postplace) AS postal_postplace,
COALESCE(enplu.postal_region_id, enpes.postal_region_id) AS postal_region_id,
COALESCE(enplu.postal_region_path, enpes.postal_region_path) AS postal_region_path,
COALESCE(enplu.postal_region_code, enpes.postal_region_code) AS postal_region_code,
COALESCE(enplu.postal_country_id, enpes.postal_country_id) AS postal_country_id,
COALESCE(enplu.postal_country_iso_2, enpes.postal_country_iso_2) AS postal_country_iso_2,
COALESCE(enplu.postal_latitude, enpes.postal_latitude) AS postal_latitude,
COALESCE(enplu.postal_longitude, enpes.postal_longitude) AS postal_longitude,
COALESCE(enplu.postal_altitude, enpes.postal_altitude) AS postal_altitude,
COALESCE(enplu.web_address, enpes.web_address) AS web_address,
COALESCE(enplu.email_address, enpes.email_address) AS email_address,
COALESCE(enplu.phone_number, enpes.phone_number) AS phone_number,
COALESCE(enplu.landline, enpes.landline) AS landline,
COALESCE(enplu.mobile_number, enpes.mobile_number) AS mobile_number,
COALESCE(enplu.fax_number, enpes.fax_number) AS fax_number,
COALESCE(enplu.unit_size_id, enpes.unit_size_id) AS unit_size_id,
COALESCE(enplu.unit_size_code, enpes.unit_size_code) AS unit_size_code,
COALESCE(enplu.status_id, enpes.status_id) AS status_id,
COALESCE(enplu.status_code, enpes.status_code) AS status_code,
COALESCE(enplu.used_for_counting, enpes.used_for_counting) AS used_for_counting,
last_edit.edit_comment AS last_edit_comment,
last_edit.edit_by_user_id AS last_edit_by_user_id,
last_edit.edit_at AS last_edit_at,
GREATEST(enplu.has_legal_unit, enpes.has_legal_unit) AS has_legal_unit,
enplu.legal_unit_id AS primary_legal_unit_id,
enpes.establishment_id AS primary_establishment_id
FROM ( SELECT t.unit_type,
t.unit_id,
t.valid_from,
t.valid_until,
en.id,
en.enabled,
en.short_name,
en.edit_comment,
en.edit_by_user_id,
en.edit_at,
en.id AS enterprise_id
FROM timesegments t
JOIN enterprise en ON t.unit_type = 'enterprise'::statistical_unit_type AND t.unit_id = en.id) ten
LEFT JOIN LATERAL ( SELECT enplu_1.unit_type,
enplu_1.unit_id,
enplu_1.valid_from,
enplu_1.valid_to,
enplu_1.valid_until,
enplu_1.name,
enplu_1.birth_date,
enplu_1.death_date,
enplu_1.search,
enplu_1.primary_activity_category_id,
enplu_1.primary_activity_category_path,
enplu_1.primary_activity_category_code,
enplu_1.secondary_activity_category_id,
enplu_1.secondary_activity_category_path,
enplu_1.secondary_activity_category_code,
enplu_1.activity_category_paths,
enplu_1.sector_id,
enplu_1.sector_path,
enplu_1.sector_code,
enplu_1.sector_name,
enplu_1.data_source_ids,
enplu_1.data_source_codes,
enplu_1.legal_form_id,
enplu_1.legal_form_code,
enplu_1.legal_form_name,
enplu_1.physical_address_part1,
enplu_1.physical_address_part2,
enplu_1.physical_address_part3,
enplu_1.physical_postcode,
enplu_1.physical_postplace,
enplu_1.physical_region_id,
enplu_1.physical_region_path,
enplu_1.physical_region_code,
enplu_1.physical_country_id,
enplu_1.physical_country_iso_2,
enplu_1.physical_latitude,
enplu_1.physical_longitude,
enplu_1.physical_altitude,
enplu_1.domestic,
enplu_1.postal_address_part1,
enplu_1.postal_address_part2,
enplu_1.postal_address_part3,
enplu_1.postal_postcode,
enplu_1.postal_postplace,
enplu_1.postal_region_id,
enplu_1.postal_region_path,
enplu_1.postal_region_code,
enplu_1.postal_country_id,
enplu_1.postal_country_iso_2,
enplu_1.postal_latitude,
enplu_1.postal_longitude,
enplu_1.postal_altitude,
enplu_1.web_address,
enplu_1.email_address,
enplu_1.phone_number,
enplu_1.landline,
enplu_1.mobile_number,
enplu_1.fax_number,
enplu_1.unit_size_id,
enplu_1.unit_size_code,
enplu_1.status_id,
enplu_1.status_code,
enplu_1.used_for_counting,
enplu_1.last_edit_comment,
enplu_1.last_edit_by_user_id,
enplu_1.last_edit_at,
enplu_1.has_legal_unit,
enplu_1.related_establishment_ids,
enplu_1.excluded_establishment_ids,
enplu_1.included_establishment_ids,
enplu_1.related_legal_unit_ids,
enplu_1.excluded_legal_unit_ids,
enplu_1.included_legal_unit_ids,
enplu_1.related_enterprise_ids,
enplu_1.excluded_enterprise_ids,
enplu_1.included_enterprise_ids,
enplu_1.legal_unit_id,
enplu_1.enterprise_id,
enplu_1.primary_for_enterprise,
enplu_1.stats,
enplu_1.stats_summary
FROM timeline_legal_unit enplu_1
WHERE enplu_1.enterprise_id = ten.enterprise_id AND enplu_1.primary_for_enterprise = true AND from_until_overlaps(ten.valid_from, ten.valid_until, enplu_1.valid_from, enplu_1.valid_until)
ORDER BY enplu_1.valid_from DESC, enplu_1.legal_unit_id DESC
LIMIT 1) enplu ON true
LEFT JOIN LATERAL ( SELECT enpes_1.unit_type,
enpes_1.unit_id,
enpes_1.valid_from,
enpes_1.valid_to,
enpes_1.valid_until,
enpes_1.name,
enpes_1.birth_date,
enpes_1.death_date,
enpes_1.search,
enpes_1.primary_activity_category_id,
enpes_1.primary_activity_category_path,
enpes_1.primary_activity_category_code,
enpes_1.secondary_activity_category_id,
enpes_1.secondary_activity_category_path,
enpes_1.secondary_activity_category_code,
enpes_1.activity_category_paths,
enpes_1.sector_id,
enpes_1.sector_path,
enpes_1.sector_code,
enpes_1.sector_name,
enpes_1.data_source_ids,
enpes_1.data_source_codes,
enpes_1.legal_form_id,
enpes_1.legal_form_code,
enpes_1.legal_form_name,
enpes_1.physical_address_part1,
enpes_1.physical_address_part2,
enpes_1.physical_address_part3,
enpes_1.physical_postcode,
enpes_1.physical_postplace,
enpes_1.physical_region_id,
enpes_1.physical_region_path,
enpes_1.physical_region_code,
enpes_1.physical_country_id,
enpes_1.physical_country_iso_2,
enpes_1.physical_latitude,
enpes_1.physical_longitude,
enpes_1.physical_altitude,
enpes_1.domestic,
enpes_1.postal_address_part1,
enpes_1.postal_address_part2,
enpes_1.postal_address_part3,
enpes_1.postal_postcode,
enpes_1.postal_postplace,
enpes_1.postal_region_id,
enpes_1.postal_region_path,
enpes_1.postal_region_code,
enpes_1.postal_country_id,
enpes_1.postal_country_iso_2,
enpes_1.postal_latitude,
enpes_1.postal_longitude,
enpes_1.postal_altitude,
enpes_1.web_address,
enpes_1.email_address,
enpes_1.phone_number,
enpes_1.landline,
enpes_1.mobile_number,
enpes_1.fax_number,
enpes_1.unit_size_id,
enpes_1.unit_size_code,
enpes_1.status_id,
enpes_1.status_code,
enpes_1.used_for_counting,
enpes_1.last_edit_comment,
enpes_1.last_edit_by_user_id,
enpes_1.last_edit_at,
enpes_1.has_legal_unit,
enpes_1.establishment_id,
enpes_1.legal_unit_id,
enpes_1.enterprise_id,
enpes_1.primary_for_enterprise,
enpes_1.primary_for_legal_unit,
enpes_1.stats,
enpes_1.stats_summary,
enpes_1.related_establishment_ids,
enpes_1.excluded_establishment_ids,
enpes_1.included_establishment_ids,
enpes_1.related_legal_unit_ids,
enpes_1.excluded_legal_unit_ids,
enpes_1.included_legal_unit_ids,
enpes_1.related_enterprise_ids,
enpes_1.excluded_enterprise_ids,
enpes_1.included_enterprise_ids
FROM timeline_establishment enpes_1
WHERE enpes_1.enterprise_id = ten.enterprise_id AND enpes_1.primary_for_enterprise = true AND from_until_overlaps(ten.valid_from, ten.valid_until, enpes_1.valid_from, enpes_1.valid_until)
ORDER BY enpes_1.valid_from DESC, enpes_1.establishment_id DESC
LIMIT 1) enpes ON true
LEFT JOIN LATERAL ( SELECT all_edits.edit_comment,
all_edits.edit_by_user_id,
all_edits.edit_at
FROM ( VALUES (ten.edit_comment,ten.edit_by_user_id,ten.edit_at), (enplu.last_edit_comment,enplu.last_edit_by_user_id,enplu.last_edit_at), (enpes.last_edit_comment,enpes.last_edit_by_user_id,enpes.last_edit_at)) all_edits(edit_comment, edit_by_user_id, edit_at)
WHERE all_edits.edit_at IS NOT NULL
ORDER BY all_edits.edit_at DESC
LIMIT 1) last_edit ON true) basis
LEFT JOIN aggregation ON basis.enterprise_id = aggregation.enterprise_id AND basis.valid_from = aggregation.valid_from AND basis.valid_until = aggregation.valid_until
)
SELECT unit_type,
unit_id,
valid_from,
(valid_until - '1 day'::interval)::date AS valid_to,
valid_until,
name,
birth_date,
death_date,
to_tsvector('simple'::regconfig, name) AS search,
primary_activity_category_id,
primary_activity_category_path,
primary_activity_category_code,
secondary_activity_category_id,
secondary_activity_category_path,
secondary_activity_category_code,
NULLIF(array_remove(ARRAY[primary_activity_category_path, secondary_activity_category_path], NULL::ltree), '{}'::ltree[]) AS activity_category_paths,
sector_id,
sector_path,
sector_code,
sector_name,
data_source_ids,
data_source_codes,
legal_form_id,
legal_form_code,
legal_form_name,
physical_address_part1,
physical_address_part2,
physical_address_part3,
physical_postcode,
physical_postplace,
physical_region_id,
physical_region_path,
physical_region_code,
physical_country_id,
physical_country_iso_2,
physical_latitude,
physical_longitude,
physical_altitude,
domestic,
postal_address_part1,
postal_address_part2,
postal_address_part3,
postal_postcode,
postal_postplace,
postal_region_id,
postal_region_path,
postal_region_code,
postal_country_id,
postal_country_iso_2,
postal_latitude,
postal_longitude,
postal_altitude,
web_address,
email_address,
phone_number,
landline,
mobile_number,
fax_number,
unit_size_id,
unit_size_code,
status_id,
status_code,
used_for_counting,
last_edit_comment,
last_edit_by_user_id,
last_edit_at,
has_legal_unit,
related_establishment_ids,
excluded_establishment_ids,
included_establishment_ids,
related_legal_unit_ids,
excluded_legal_unit_ids,
included_legal_unit_ids,
ARRAY[unit_id] AS related_enterprise_ids,
ARRAY[]::integer[] AS excluded_enterprise_ids,
CASE
WHEN used_for_counting THEN ARRAY[unit_id]
ELSE '{}'::integer[]
END AS included_enterprise_ids,
enterprise_id,
primary_establishment_id,
primary_legal_unit_id,
stats_summary
FROM enterprise_with_primary_and_aggregation
ORDER BY unit_type, unit_id, valid_from
;

-- statistical_unit_def
CREATE OR REPLACE VIEW public.statistical_unit_def
WITH (security_invoker='on') AS
WITH external_idents_agg AS (
SELECT all_idents.unit_type,
all_idents.unit_id,
jsonb_object_agg(all_idents.type_code, all_idents.ident) AS external_idents
FROM ( SELECT 'establishment'::statistical_unit_type AS unit_type,
ei.establishment_id AS unit_id,
eit.code AS type_code,
COALESCE(ei.ident, ei.idents::text::character varying) AS ident
FROM external_ident ei
JOIN external_ident_type eit ON ei.type_id = eit.id
WHERE ei.establishment_id IS NOT NULL
UNION ALL
SELECT 'legal_unit'::statistical_unit_type AS unit_type,
ei.legal_unit_id AS unit_id,
eit.code AS type_code,
COALESCE(ei.ident, ei.idents::text::character varying) AS ident
FROM external_ident ei
JOIN external_ident_type eit ON ei.type_id = eit.id
WHERE ei.legal_unit_id IS NOT NULL
UNION ALL
SELECT 'enterprise'::statistical_unit_type AS unit_type,
ei.enterprise_id AS unit_id,
eit.code AS type_code,
COALESCE(ei.ident, ei.idents::text::character varying) AS ident
FROM external_ident ei
JOIN external_ident_type eit ON ei.type_id = eit.id
WHERE ei.enterprise_id IS NOT NULL
UNION ALL
SELECT 'power_group'::statistical_unit_type AS unit_type,
ei.power_group_id AS unit_id,
eit.code AS type_code,
COALESCE(ei.ident, ei.idents::text::character varying) AS ident
FROM external_ident ei
JOIN external_ident_type eit ON ei.type_id = eit.id
WHERE ei.power_group_id IS NOT NULL) all_idents
GROUP BY all_idents.unit_type, all_idents.unit_id
), tag_paths_agg AS (
SELECT all_tags.unit_type,
all_tags.unit_id,
array_agg(all_tags.path ORDER BY all_tags.path) AS tag_paths
FROM ( SELECT 'establishment'::statistical_unit_type AS unit_type,
tfu.establishment_id AS unit_id,
t.path
FROM tag_for_unit tfu
JOIN tag t ON tfu.tag_id = t.id
WHERE tfu.establishment_id IS NOT NULL
UNION ALL
SELECT 'legal_unit'::statistical_unit_type AS unit_type,
tfu.legal_unit_id AS unit_id,
t.path
FROM tag_for_unit tfu
JOIN tag t ON tfu.tag_id = t.id
WHERE tfu.legal_unit_id IS NOT NULL
UNION ALL
SELECT 'enterprise'::statistical_unit_type AS unit_type,
tfu.enterprise_id AS unit_id,
t.path
FROM tag_for_unit tfu
JOIN tag t ON tfu.tag_id = t.id
WHERE tfu.enterprise_id IS NOT NULL
UNION ALL
SELECT 'power_group'::statistical_unit_type AS unit_type,
tfu.power_group_id AS unit_id,
t.path
FROM tag_for_unit tfu
JOIN tag t ON tfu.tag_id = t.id
WHERE tfu.power_group_id IS NOT NULL) all_tags
GROUP BY all_tags.unit_type, all_tags.unit_id
), data AS (
SELECT timeline_establishment.unit_type,
timeline_establishment.unit_id,
timeline_establishment.valid_from,
timeline_establishment.valid_to,
timeline_establishment.valid_until,
timeline_establishment.name,
timeline_establishment.birth_date,
timeline_establishment.death_date,
timeline_establishment.search,
timeline_establishment.primary_activity_category_id,
timeline_establishment.primary_activity_category_path,
timeline_establishment.primary_activity_category_code,
timeline_establishment.secondary_activity_category_id,
timeline_establishment.secondary_activity_category_path,
timeline_establishment.secondary_activity_category_code,
timeline_establishment.activity_category_paths,
timeline_establishment.sector_id,
timeline_establishment.sector_path,
timeline_establishment.sector_code,
timeline_establishment.sector_name,
timeline_establishment.data_source_ids,
timeline_establishment.data_source_codes,
timeline_establishment.legal_form_id,
timeline_establishment.legal_form_code,
timeline_establishment.legal_form_name,
timeline_establishment.physical_address_part1,
timeline_establishment.physical_address_part2,
timeline_establishment.physical_address_part3,
timeline_establishment.physical_postcode,
timeline_establishment.physical_postplace,
timeline_establishment.physical_region_id,
timeline_establishment.physical_region_path,
timeline_establishment.physical_region_code,
timeline_establishment.physical_country_id,
timeline_establishment.physical_country_iso_2,
timeline_establishment.physical_latitude,
timeline_establishment.physical_longitude,
timeline_establishment.physical_altitude,
timeline_establishment.domestic,
timeline_establishment.postal_address_part1,
timeline_establishment.postal_address_part2,
timeline_establishment.postal_address_part3,
timeline_establishment.postal_postcode,
timeline_establishment.postal_postplace,
timeline_establishment.postal_region_id,
timeline_establishment.postal_region_path,
timeline_establishment.postal_region_code,
timeline_establishment.postal_country_id,
timeline_establishment.postal_country_iso_2,
timeline_establishment.postal_latitude,
timeline_establishment.postal_longitude,
timeline_establishment.postal_altitude,
timeline_establishment.web_address,
timeline_establishment.email_address,
timeline_establishment.phone_number,
timeline_establishment.landline,
timeline_establishment.mobile_number,
timeline_establishment.fax_number,
timeline_establishment.unit_size_id,
timeline_establishment.unit_size_code,
timeline_establishment.status_id,
timeline_establishment.status_code,
timeline_establishment.used_for_counting,
timeline_establishment.last_edit_comment,
timeline_establishment.last_edit_by_user_id,
timeline_establishment.last_edit_at,
timeline_establishment.has_legal_unit,
timeline_establishment.related_establishment_ids,
timeline_establishment.excluded_establishment_ids,
timeline_establishment.included_establishment_ids,
timeline_establishment.related_legal_unit_ids,
timeline_establishment.excluded_legal_unit_ids,
timeline_establishment.included_legal_unit_ids,
timeline_establishment.related_enterprise_ids,
timeline_establishment.excluded_enterprise_ids,
timeline_establishment.included_enterprise_ids,
timeline_establishment.stats,
timeline_establishment.stats_summary,
NULL::integer AS primary_establishment_id,
NULL::integer AS primary_legal_unit_id
FROM timeline_establishment
UNION ALL
SELECT timeline_legal_unit.unit_type,
timeline_legal_unit.unit_id,
timeline_legal_unit.valid_from,
timeline_legal_unit.valid_to,
timeline_legal_unit.valid_until,
timeline_legal_unit.name,
timeline_legal_unit.birth_date,
timeline_legal_unit.death_date,
timeline_legal_unit.search,
timeline_legal_unit.primary_activity_category_id,
timeline_legal_unit.primary_activity_category_path,
timeline_legal_unit.primary_activity_category_code,
timeline_legal_unit.secondary_activity_category_id,
timeline_legal_unit.secondary_activity_category_path,
timeline_legal_unit.secondary_activity_category_code,
timeline_legal_unit.activity_category_paths,
timeline_legal_unit.sector_id,
timeline_legal_unit.sector_path,
timeline_legal_unit.sector_code,
timeline_legal_unit.sector_name,
timeline_legal_unit.data_source_ids,
timeline_legal_unit.data_source_codes,
timeline_legal_unit.legal_form_id,
timeline_legal_unit.legal_form_code,
timeline_legal_unit.legal_form_name,
timeline_legal_unit.physical_address_part1,
timeline_legal_unit.physical_address_part2,
timeline_legal_unit.physical_address_part3,
timeline_legal_unit.physical_postcode,
timeline_legal_unit.physical_postplace,
timeline_legal_unit.physical_region_id,
timeline_legal_unit.physical_region_path,
timeline_legal_unit.physical_region_code,
timeline_legal_unit.physical_country_id,
timeline_legal_unit.physical_country_iso_2,
timeline_legal_unit.physical_latitude,
timeline_legal_unit.physical_longitude,
timeline_legal_unit.physical_altitude,
timeline_legal_unit.domestic,
timeline_legal_unit.postal_address_part1,
timeline_legal_unit.postal_address_part2,
timeline_legal_unit.postal_address_part3,
timeline_legal_unit.postal_postcode,
timeline_legal_unit.postal_postplace,
timeline_legal_unit.postal_region_id,
timeline_legal_unit.postal_region_path,
timeline_legal_unit.postal_region_code,
timeline_legal_unit.postal_country_id,
timeline_legal_unit.postal_country_iso_2,
timeline_legal_unit.postal_latitude,
timeline_legal_unit.postal_longitude,
timeline_legal_unit.postal_altitude,
timeline_legal_unit.web_address,
timeline_legal_unit.email_address,
timeline_legal_unit.phone_number,
timeline_legal_unit.landline,
timeline_legal_unit.mobile_number,
timeline_legal_unit.fax_number,
timeline_legal_unit.unit_size_id,
timeline_legal_unit.unit_size_code,
timeline_legal_unit.status_id,
timeline_legal_unit.status_code,
timeline_legal_unit.used_for_counting,
timeline_legal_unit.last_edit_comment,
timeline_legal_unit.last_edit_by_user_id,
timeline_legal_unit.last_edit_at,
timeline_legal_unit.has_legal_unit,
timeline_legal_unit.related_establishment_ids,
timeline_legal_unit.excluded_establishment_ids,
timeline_legal_unit.included_establishment_ids,
timeline_legal_unit.related_legal_unit_ids,
timeline_legal_unit.excluded_legal_unit_ids,
timeline_legal_unit.included_legal_unit_ids,
timeline_legal_unit.related_enterprise_ids,
timeline_legal_unit.excluded_enterprise_ids,
timeline_legal_unit.included_enterprise_ids,
NULL::jsonb AS stats,
timeline_legal_unit.stats_summary,
NULL::integer AS primary_establishment_id,
NULL::integer AS primary_legal_unit_id
FROM timeline_legal_unit
UNION ALL
SELECT timeline_enterprise.unit_type,
timeline_enterprise.unit_id,
timeline_enterprise.valid_from,
timeline_enterprise.valid_to,
timeline_enterprise.valid_until,
timeline_enterprise.name,
timeline_enterprise.birth_date,
timeline_enterprise.death_date,
timeline_enterprise.search,
timeline_enterprise.primary_activity_category_id,
timeline_enterprise.primary_activity_category_path,
timeline_enterprise.primary_activity_category_code,
timeline_enterprise.secondary_activity_category_id,
timeline_enterprise.secondary_activity_category_path,
timeline_enterprise.secondary_activity_category_code,
timeline_enterprise.activity_category_paths,
timeline_enterprise.sector_id,
timeline_enterprise.sector_path,
timeline_enterprise.sector_code,
timeline_enterprise.sector_name,
timeline_enterprise.data_source_ids,
timeline_enterprise.data_source_codes,
timeline_enterprise.legal_form_id,
timeline_enterprise.legal_form_code,
timeline_enterprise.legal_form_name,
timeline_enterprise.physical_address_part1,
timeline_enterprise.physical_address_part2,
timeline_enterprise.physical_address_part3,
timeline_enterprise.physical_postcode,
timeline_enterprise.physical_postplace,
timeline_enterprise.physical_region_id,
timeline_enterprise.physical_region_path,
timeline_enterprise.physical_region_code,
timeline_enterprise.physical_country_id,
timeline_enterprise.physical_country_iso_2,
timeline_enterprise.physical_latitude,
timeline_enterprise.physical_longitude,
timeline_enterprise.physical_altitude,
timeline_enterprise.domestic,
timeline_enterprise.postal_address_part1,
timeline_enterprise.postal_address_part2,
timeline_enterprise.postal_address_part3,
timeline_enterprise.postal_postcode,
timeline_enterprise.postal_postplace,
timeline_enterprise.postal_region_id,
timeline_enterprise.postal_region_path,
timeline_enterprise.postal_region_code,
timeline_enterprise.postal_country_id,
timeline_enterprise.postal_country_iso_2,
timeline_enterprise.postal_latitude,
timeline_enterprise.postal_longitude,
timeline_enterprise.postal_altitude,
timeline_enterprise.web_address,
timeline_enterprise.email_address,
timeline_enterprise.phone_number,
timeline_enterprise.landline,
timeline_enterprise.mobile_number,
timeline_enterprise.fax_number,
timeline_enterprise.unit_size_id,
timeline_enterprise.unit_size_code,
timeline_enterprise.status_id,
timeline_enterprise.status_code,
timeline_enterprise.used_for_counting,
timeline_enterprise.last_edit_comment,
timeline_enterprise.last_edit_by_user_id,
timeline_enterprise.last_edit_at,
timeline_enterprise.has_legal_unit,
timeline_enterprise.related_establishment_ids,
timeline_enterprise.excluded_establishment_ids,
timeline_enterprise.included_establishment_ids,
timeline_enterprise.related_legal_unit_ids,
timeline_enterprise.excluded_legal_unit_ids,
timeline_enterprise.included_legal_unit_ids,
timeline_enterprise.related_enterprise_ids,
timeline_enterprise.excluded_enterprise_ids,
timeline_enterprise.included_enterprise_ids,
NULL::jsonb AS stats,
timeline_enterprise.stats_summary,
timeline_enterprise.primary_establishment_id,
timeline_enterprise.primary_legal_unit_id
FROM timeline_enterprise
)
SELECT data.unit_type,
data.unit_id,
data.valid_from,
data.valid_to,
data.valid_until,
COALESCE(eia1.external_idents, eia2.external_idents, eia3.external_idents, '{}'::jsonb) AS external_idents,
data.name,
data.birth_date,
data.death_date,
data.search,
data.primary_activity_category_id,
data.primary_activity_category_path,
data.primary_activity_category_code,
data.secondary_activity_category_id,
data.secondary_activity_category_path,
data.secondary_activity_category_code,
data.activity_category_paths,
data.sector_id,
data.sector_path,
data.sector_code,
data.sector_name,
data.data_source_ids,
data.data_source_codes,
data.legal_form_id,
data.legal_form_code,
data.legal_form_name,
data.physical_address_part1,
data.physical_address_part2,
data.physical_address_part3,
data.physical_postcode,
data.physical_postplace,
data.physical_region_id,
data.physical_region_path,
data.physical_region_code,
data.physical_country_id,
data.physical_country_iso_2,
data.physical_latitude,
data.physical_longitude,
data.physical_altitude,
data.domestic,
data.postal_address_part1,
data.postal_address_part2,
data.postal_address_part3,
data.postal_postcode,
data.postal_postplace,
data.postal_region_id,
data.postal_region_path,
data.postal_region_code,
data.postal_country_id,
data.postal_country_iso_2,
data.postal_latitude,
data.postal_longitude,
data.postal_altitude,
data.web_address,
data.email_address,
data.phone_number,
data.landline,
data.mobile_number,
data.fax_number,
data.unit_size_id,
data.unit_size_code,
data.status_id,
data.status_code,
data.used_for_counting,
data.last_edit_comment,
data.last_edit_by_user_id,
data.last_edit_at,
data.has_legal_unit,
data.related_establishment_ids,
data.excluded_establishment_ids,
data.included_establishment_ids,
data.related_legal_unit_ids,
data.excluded_legal_unit_ids,
data.included_legal_unit_ids,
data.related_enterprise_ids,
data.excluded_enterprise_ids,
data.included_enterprise_ids,
data.stats,
data.stats_summary,
array_length(data.included_establishment_ids, 1) AS included_establishment_count,
array_length(data.included_legal_unit_ids, 1) AS included_legal_unit_count,
array_length(data.included_enterprise_ids, 1) AS included_enterprise_count,
COALESCE(tpa.tag_paths, ARRAY[]::ltree[]) AS tag_paths
FROM data
LEFT JOIN external_idents_agg eia1 ON eia1.unit_type = data.unit_type AND eia1.unit_id = data.unit_id
LEFT JOIN external_idents_agg eia2 ON eia2.unit_type = 'establishment'::statistical_unit_type AND eia2.unit_id = data.primary_establishment_id
LEFT JOIN external_idents_agg eia3 ON eia3.unit_type = 'legal_unit'::statistical_unit_type AND eia3.unit_id = data.primary_legal_unit_id
LEFT JOIN tag_paths_agg tpa ON tpa.unit_type = data.unit_type AND tpa.unit_id = data.unit_id
;

-- Step 6: Recreate functions without invalid_codes

-- relevant_statistical_units
CREATE OR REPLACE FUNCTION public.relevant_statistical_units(unit_type statistical_unit_type, unit_id integer, valid_on date DEFAULT CURRENT_DATE)
 RETURNS SETOF statistical_unit
 LANGUAGE sql
 STABLE
AS $function$
    WITH valid_units AS (
        SELECT * FROM public.statistical_unit
        WHERE valid_from <= $3 AND $3 < valid_until
    ), root_unit AS (
        SELECT * FROM valid_units
        WHERE unit_type = 'enterprise'
          AND unit_id = public.statistical_unit_enterprise_id($1, $2, $3)
    ), related_units AS (
        SELECT * FROM valid_units
        WHERE unit_type = 'legal_unit'
          AND unit_id IN (SELECT unnest(related_legal_unit_ids) FROM root_unit)
            UNION ALL
        SELECT * FROM valid_units
        WHERE unit_type = 'establishment'
          AND unit_id IN (SELECT unnest(related_establishment_ids) FROM root_unit)
    ), relevant_units AS (
        SELECT * FROM root_unit
            UNION ALL
        SELECT * FROM related_units
    ), ordered_units AS (
      SELECT ru.*
          , first_external.ident AS first_external_ident
        FROM relevant_units ru
      LEFT JOIN LATERAL (
          SELECT eit.code, (ru.external_idents->>eit.code)::text AS ident
          FROM public.external_ident_type eit
          ORDER BY eit.priority
          LIMIT 1
      ) first_external ON true
      ORDER BY unit_type, first_external_ident NULLS LAST, unit_id
    )
    SELECT unit_type
         , unit_id
         , valid_from
         , valid_to
         , valid_until
         , external_idents
         , name
         , birth_date
         , death_date
         , search
         , primary_activity_category_id
         , primary_activity_category_path
         , primary_activity_category_code
         , secondary_activity_category_id
         , secondary_activity_category_path
         , secondary_activity_category_code
         , activity_category_paths
         , sector_id
         , sector_path
         , sector_code
         , sector_name
         , data_source_ids
         , data_source_codes
         , legal_form_id
         , legal_form_code
         , legal_form_name
         --
         , physical_address_part1
         , physical_address_part2
         , physical_address_part3
         , physical_postcode
         , physical_postplace
         , physical_region_id
         , physical_region_path
         , physical_region_code
         , physical_country_id
         , physical_country_iso_2
         , physical_latitude
         , physical_longitude
         , physical_altitude
         --
         , domestic
         --
         , postal_address_part1
         , postal_address_part2
         , postal_address_part3
         , postal_postcode
         , postal_postplace
         , postal_region_id
         , postal_region_path
         , postal_region_code
         , postal_country_id
         , postal_country_iso_2
         , postal_latitude
         , postal_longitude
         , postal_altitude
         --
         , web_address
         , email_address
         , phone_number
         , landline
         , mobile_number
         , fax_number
         --
         , unit_size_id
         , unit_size_code
         --
         , status_id
         , status_code
         , used_for_counting
         --
         , last_edit_comment
         , last_edit_by_user_id
         , last_edit_at
         --
         , has_legal_unit
         , related_establishment_ids
         , excluded_establishment_ids
         , included_establishment_ids
         , related_legal_unit_ids
         , excluded_legal_unit_ids
         , included_legal_unit_ids
         , related_enterprise_ids
         , excluded_enterprise_ids
         , included_enterprise_ids
         , stats
         , stats_summary
         , included_establishment_count
         , included_legal_unit_count
         , included_enterprise_count
         , tag_paths
         , daterange(valid_from, valid_until) AS valid_range
         , report_partition_seq
    FROM ordered_units;
$function$
;

-- get_statistical_unit_data_partial
CREATE OR REPLACE FUNCTION import.get_statistical_unit_data_partial(p_unit_type statistical_unit_type, p_id_ranges int4multirange)
 RETURNS SETOF statistical_unit
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    -- PERF: Convert multirange to array once for efficient = ANY() filtering
    v_ids INT[] := public.int4multirange_to_array(p_id_ranges);
BEGIN
    IF p_unit_type = 'establishment' THEN
        RETURN QUERY
        SELECT
            t.unit_type,
            t.unit_id,
            t.valid_from,
            t.valid_to,
            t.valid_until,
            COALESCE(eia1.external_idents, '{}'::jsonb) AS external_idents,
            t.name,
            t.birth_date,
            t.death_date,
            t.search,
            t.primary_activity_category_id,
            t.primary_activity_category_path,
            t.primary_activity_category_code,
            t.secondary_activity_category_id,
            t.secondary_activity_category_path,
            t.secondary_activity_category_code,
            t.activity_category_paths,
            t.sector_id,
            t.sector_path,
            t.sector_code,
            t.sector_name,
            t.data_source_ids,
            t.data_source_codes,
            t.legal_form_id,
            t.legal_form_code,
            t.legal_form_name,
            t.physical_address_part1,
            t.physical_address_part2,
            t.physical_address_part3,
            t.physical_postcode,
            t.physical_postplace,
            t.physical_region_id,
            t.physical_region_path,
            t.physical_region_code,
            t.physical_country_id,
            t.physical_country_iso_2,
            t.physical_latitude,
            t.physical_longitude,
            t.physical_altitude,
            t.domestic,
            t.postal_address_part1,
            t.postal_address_part2,
            t.postal_address_part3,
            t.postal_postcode,
            t.postal_postplace,
            t.postal_region_id,
            t.postal_region_path,
            t.postal_region_code,
            t.postal_country_id,
            t.postal_country_iso_2,
            t.postal_latitude,
            t.postal_longitude,
            t.postal_altitude,
            t.web_address,
            t.email_address,
            t.phone_number,
            t.landline,
            t.mobile_number,
            t.fax_number,
            t.unit_size_id,
            t.unit_size_code,
            t.status_id,
            t.status_code,
            t.used_for_counting,
            t.last_edit_comment,
            t.last_edit_by_user_id,
            t.last_edit_at,
            t.has_legal_unit,
            t.related_establishment_ids,
            t.excluded_establishment_ids,
            t.included_establishment_ids,
            t.related_legal_unit_ids,
            t.excluded_legal_unit_ids,
            t.included_legal_unit_ids,
            t.related_enterprise_ids,
            t.excluded_enterprise_ids,
            t.included_enterprise_ids,
            t.stats,
            t.stats_summary,
            array_length(t.included_establishment_ids, 1) AS included_establishment_count,
            array_length(t.included_legal_unit_ids, 1) AS included_legal_unit_count,
            array_length(t.included_enterprise_ids, 1) AS included_enterprise_count,
            COALESCE(tpa.tag_paths, ARRAY[]::public.ltree[]) AS tag_paths,
            daterange(t.valid_from, t.valid_until) AS valid_range,
            public.report_partition_seq(t.unit_type, t.unit_id, (SELECT analytics_partition_count FROM public.settings)) AS report_partition_seq
        FROM public.timeline_establishment t
        LEFT JOIN LATERAL (
            SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents
            FROM public.external_ident ei
            JOIN public.external_ident_type eit ON ei.type_id = eit.id
            WHERE ei.establishment_id = t.unit_id
        ) eia1 ON true
        LEFT JOIN LATERAL (
            SELECT array_agg(tag.path ORDER BY tag.path) AS tag_paths
            FROM public.tag_for_unit tfu
            JOIN public.tag ON tfu.tag_id = tag.id
            WHERE tfu.establishment_id = t.unit_id
        ) tpa ON true
        WHERE t.unit_id = ANY(v_ids);

    ELSIF p_unit_type = 'legal_unit' THEN
        RETURN QUERY
        SELECT
            t.unit_type,
            t.unit_id,
            t.valid_from,
            t.valid_to,
            t.valid_until,
            COALESCE(eia1.external_idents, '{}'::jsonb) AS external_idents,
            t.name,
            t.birth_date,
            t.death_date,
            t.search,
            t.primary_activity_category_id,
            t.primary_activity_category_path,
            t.primary_activity_category_code,
            t.secondary_activity_category_id,
            t.secondary_activity_category_path,
            t.secondary_activity_category_code,
            t.activity_category_paths,
            t.sector_id,
            t.sector_path,
            t.sector_code,
            t.sector_name,
            t.data_source_ids,
            t.data_source_codes,
            t.legal_form_id,
            t.legal_form_code,
            t.legal_form_name,
            t.physical_address_part1,
            t.physical_address_part2,
            t.physical_address_part3,
            t.physical_postcode,
            t.physical_postplace,
            t.physical_region_id,
            t.physical_region_path,
            t.physical_region_code,
            t.physical_country_id,
            t.physical_country_iso_2,
            t.physical_latitude,
            t.physical_longitude,
            t.physical_altitude,
            t.domestic,
            t.postal_address_part1,
            t.postal_address_part2,
            t.postal_address_part3,
            t.postal_postcode,
            t.postal_postplace,
            t.postal_region_id,
            t.postal_region_path,
            t.postal_region_code,
            t.postal_country_id,
            t.postal_country_iso_2,
            t.postal_latitude,
            t.postal_longitude,
            t.postal_altitude,
            t.web_address,
            t.email_address,
            t.phone_number,
            t.landline,
            t.mobile_number,
            t.fax_number,
            t.unit_size_id,
            t.unit_size_code,
            t.status_id,
            t.status_code,
            t.used_for_counting,
            t.last_edit_comment,
            t.last_edit_by_user_id,
            t.last_edit_at,
            t.has_legal_unit,
            t.related_establishment_ids,
            t.excluded_establishment_ids,
            t.included_establishment_ids,
            t.related_legal_unit_ids,
            t.excluded_legal_unit_ids,
            t.included_legal_unit_ids,
            t.related_enterprise_ids,
            t.excluded_enterprise_ids,
            t.included_enterprise_ids,
            t.stats,
            t.stats_summary,
            array_length(t.included_establishment_ids, 1) AS included_establishment_count,
            array_length(t.included_legal_unit_ids, 1) AS included_legal_unit_count,
            array_length(t.included_enterprise_ids, 1) AS included_enterprise_count,
            COALESCE(tpa.tag_paths, ARRAY[]::public.ltree[]) AS tag_paths,
            daterange(t.valid_from, t.valid_until) AS valid_range,
            public.report_partition_seq(t.unit_type, t.unit_id, (SELECT analytics_partition_count FROM public.settings)) AS report_partition_seq
        FROM public.timeline_legal_unit t
        LEFT JOIN LATERAL (
            SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents
            FROM public.external_ident ei
            JOIN public.external_ident_type eit ON ei.type_id = eit.id
            WHERE ei.legal_unit_id = t.unit_id
        ) eia1 ON true
        LEFT JOIN LATERAL (
            SELECT array_agg(tag.path ORDER BY tag.path) AS tag_paths
            FROM public.tag_for_unit tfu
            JOIN public.tag ON tfu.tag_id = tag.id
            WHERE tfu.legal_unit_id = t.unit_id
        ) tpa ON true
        WHERE t.unit_id = ANY(v_ids);

    ELSIF p_unit_type = 'enterprise' THEN
        RETURN QUERY
        SELECT
            t.unit_type,
            t.unit_id,
            t.valid_from,
            t.valid_to,
            t.valid_until,
            COALESCE(
                eia1.external_idents,
                eia2.external_idents,
                eia3.external_idents,
                '{}'::jsonb
            ) AS external_idents,
            t.name::varchar,
            t.birth_date,
            t.death_date,
            t.search,
            t.primary_activity_category_id,
            t.primary_activity_category_path,
            t.primary_activity_category_code,
            t.secondary_activity_category_id,
            t.secondary_activity_category_path,
            t.secondary_activity_category_code,
            t.activity_category_paths,
            t.sector_id,
            t.sector_path,
            t.sector_code,
            t.sector_name,
            t.data_source_ids,
            t.data_source_codes,
            t.legal_form_id,
            t.legal_form_code,
            t.legal_form_name,
            t.physical_address_part1,
            t.physical_address_part2,
            t.physical_address_part3,
            t.physical_postcode,
            t.physical_postplace,
            t.physical_region_id,
            t.physical_region_path,
            t.physical_region_code,
            t.physical_country_id,
            t.physical_country_iso_2,
            t.physical_latitude,
            t.physical_longitude,
            t.physical_altitude,
            t.domestic,
            t.postal_address_part1,
            t.postal_address_part2,
            t.postal_address_part3,
            t.postal_postcode,
            t.postal_postplace,
            t.postal_region_id,
            t.postal_region_path,
            t.postal_region_code,
            t.postal_country_id,
            t.postal_country_iso_2,
            t.postal_latitude,
            t.postal_longitude,
            t.postal_altitude,
            t.web_address,
            t.email_address,
            t.phone_number,
            t.landline,
            t.mobile_number,
            t.fax_number,
            t.unit_size_id,
            t.unit_size_code,
            t.status_id,
            t.status_code,
            t.used_for_counting,
            t.last_edit_comment,
            t.last_edit_by_user_id,
            t.last_edit_at,
            t.has_legal_unit,
            t.related_establishment_ids,
            t.excluded_establishment_ids,
            t.included_establishment_ids,
            t.related_legal_unit_ids,
            t.excluded_legal_unit_ids,
            t.included_legal_unit_ids,
            t.related_enterprise_ids,
            t.excluded_enterprise_ids,
            t.included_enterprise_ids,
            NULL::JSONB AS stats,
            t.stats_summary,
            array_length(t.included_establishment_ids, 1) AS included_establishment_count,
            array_length(t.included_legal_unit_ids, 1) AS included_legal_unit_count,
            array_length(t.included_enterprise_ids, 1) AS included_enterprise_count,
            COALESCE(tpa.tag_paths, ARRAY[]::public.ltree[]) AS tag_paths,
            daterange(t.valid_from, t.valid_until) AS valid_range,
            public.report_partition_seq(t.unit_type, t.unit_id, (SELECT analytics_partition_count FROM public.settings)) AS report_partition_seq
        FROM public.timeline_enterprise t
        LEFT JOIN LATERAL (
            SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents
            FROM public.external_ident ei
            JOIN public.external_ident_type eit ON ei.type_id = eit.id
            WHERE ei.enterprise_id = t.unit_id
        ) eia1 ON true
        LEFT JOIN LATERAL (
            SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents
            FROM public.external_ident ei
            JOIN public.external_ident_type eit ON ei.type_id = eit.id
            WHERE ei.establishment_id = t.primary_establishment_id
        ) eia2 ON true
        LEFT JOIN LATERAL (
            SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents
            FROM public.external_ident ei
            JOIN public.external_ident_type eit ON ei.type_id = eit.id
            WHERE ei.legal_unit_id = t.primary_legal_unit_id
        ) eia3 ON true
        LEFT JOIN LATERAL (
            SELECT array_agg(tag.path ORDER BY tag.path) AS tag_paths
            FROM public.tag_for_unit tfu
            JOIN public.tag ON tfu.tag_id = tag.id
            WHERE tfu.enterprise_id = t.unit_id
        ) tpa ON true
        WHERE t.unit_id = ANY(v_ids);
    END IF;
END;
$function$
;

-- statistical_unit_refresh
CREATE OR REPLACE PROCEDURE public.statistical_unit_refresh(IN p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange, IN p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange, IN p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_batch_size INT := 262144;
    v_min_id int; v_max_id int; v_start_id int; v_end_id int;
    v_batch_num INT;
    v_total_units INT;
    v_batch_start_time timestamptz;
    v_batch_duration_ms numeric;
    v_batch_speed numeric;
    v_current_batch_size int;
    v_is_partial_refresh BOOLEAN;
BEGIN
    v_is_partial_refresh := (p_establishment_id_ranges IS NOT NULL
                            OR p_legal_unit_id_ranges IS NOT NULL
                            OR p_enterprise_id_ranges IS NOT NULL);

    IF NOT v_is_partial_refresh THEN
        -- Full refresh with ANALYZE
        ANALYZE public.timeline_establishment, public.timeline_legal_unit, public.timeline_enterprise;

        -- Create temp table WITHOUT valid_range (it's GENERATED in the target)
        CREATE TEMP TABLE statistical_unit_new (LIKE public.statistical_unit) ON COMMIT DROP;
        ALTER TABLE statistical_unit_new DROP COLUMN IF EXISTS valid_range;

        -- Establishments
        v_batch_num := 0;
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = 'establishment';
        RAISE DEBUG 'Refreshing statistical units for % establishments in batches of %...', v_total_units, v_batch_size;
        IF v_min_id IS NOT NULL THEN FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_start_time := clock_timestamp();
            v_batch_num := v_batch_num + 1;
            v_start_id := i; v_end_id := i + v_batch_size - 1;
            INSERT INTO statistical_unit_new (
                unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
                primary_activity_category_id, primary_activity_category_path, primary_activity_category_code,
                secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code,
                activity_category_paths, sector_id, sector_path, sector_code, sector_name,
                data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name,
                physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace,
                physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2,
                physical_latitude, physical_longitude, physical_altitude, domestic,
                postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace,
                postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2,
                postal_latitude, postal_longitude, postal_altitude,
                web_address, email_address, phone_number, landline, mobile_number, fax_number,
                unit_size_id, unit_size_code, status_id, status_code, used_for_counting,
                last_edit_comment, last_edit_by_user_id, last_edit_at, has_legal_unit,
                related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
                related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
                related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
                stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
            )
            SELECT
                unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
                primary_activity_category_id, primary_activity_category_path, primary_activity_category_code,
                secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code,
                activity_category_paths, sector_id, sector_path, sector_code, sector_name,
                data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name,
                physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace,
                physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2,
                physical_latitude, physical_longitude, physical_altitude, domestic,
                postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace,
                postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2,
                postal_latitude, postal_longitude, postal_altitude,
                web_address, email_address, phone_number, landline, mobile_number, fax_number,
                unit_size_id, unit_size_code, status_id, status_code, used_for_counting,
                last_edit_comment, last_edit_by_user_id, last_edit_at, has_legal_unit,
                related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
                related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
                related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
                stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
            FROM public.statistical_unit_def
            WHERE unit_type = 'establishment' AND unit_id BETWEEN v_start_id AND v_end_id;
            v_batch_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_batch_start_time))) * 1000;
            v_current_batch_size := v_batch_size;
            v_batch_speed := v_current_batch_size / (v_batch_duration_ms / 1000.0);
            RAISE DEBUG 'Establishment SU batch %/% done. (% units, % ms, % units/s)', v_batch_num, ceil(v_total_units::decimal / v_batch_size), v_current_batch_size, round(v_batch_duration_ms), round(v_batch_speed);
        END LOOP; END IF;

        -- Legal Units
        v_batch_num := 0;
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = 'legal_unit';
        RAISE DEBUG 'Refreshing statistical units for % legal units in batches of %...', v_total_units, v_batch_size;
        IF v_min_id IS NOT NULL THEN FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_start_time := clock_timestamp();
            v_batch_num := v_batch_num + 1;
            v_start_id := i; v_end_id := i + v_batch_size - 1;
            INSERT INTO statistical_unit_new (
                unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
                primary_activity_category_id, primary_activity_category_path, primary_activity_category_code,
                secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code,
                activity_category_paths, sector_id, sector_path, sector_code, sector_name,
                data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name,
                physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace,
                physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2,
                physical_latitude, physical_longitude, physical_altitude, domestic,
                postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace,
                postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2,
                postal_latitude, postal_longitude, postal_altitude,
                web_address, email_address, phone_number, landline, mobile_number, fax_number,
                unit_size_id, unit_size_code, status_id, status_code, used_for_counting,
                last_edit_comment, last_edit_by_user_id, last_edit_at, has_legal_unit,
                related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
                related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
                related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
                stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
            )
            SELECT
                unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
                primary_activity_category_id, primary_activity_category_path, primary_activity_category_code,
                secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code,
                activity_category_paths, sector_id, sector_path, sector_code, sector_name,
                data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name,
                physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace,
                physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2,
                physical_latitude, physical_longitude, physical_altitude, domestic,
                postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace,
                postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2,
                postal_latitude, postal_longitude, postal_altitude,
                web_address, email_address, phone_number, landline, mobile_number, fax_number,
                unit_size_id, unit_size_code, status_id, status_code, used_for_counting,
                last_edit_comment, last_edit_by_user_id, last_edit_at, has_legal_unit,
                related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
                related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
                related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
                stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
            FROM public.statistical_unit_def
            WHERE unit_type = 'legal_unit' AND unit_id BETWEEN v_start_id AND v_end_id;
            v_batch_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_batch_start_time))) * 1000;
            v_current_batch_size := v_batch_size;
            v_batch_speed := v_current_batch_size / (v_batch_duration_ms / 1000.0);
            RAISE DEBUG 'Legal unit SU batch %/% done. (% units, % ms, % units/s)', v_batch_num, ceil(v_total_units::decimal / v_batch_size), v_current_batch_size, round(v_batch_duration_ms), round(v_batch_speed);
        END LOOP; END IF;

        -- Enterprises
        v_batch_num := 0;
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = 'enterprise';
        RAISE DEBUG 'Refreshing statistical units for % enterprises in batches of %...', v_total_units, v_batch_size;
        IF v_min_id IS NOT NULL THEN FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_start_time := clock_timestamp();
            v_batch_num := v_batch_num + 1;
            v_start_id := i; v_end_id := i + v_batch_size - 1;
            INSERT INTO statistical_unit_new (
                unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
                primary_activity_category_id, primary_activity_category_path, primary_activity_category_code,
                secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code,
                activity_category_paths, sector_id, sector_path, sector_code, sector_name,
                data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name,
                physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace,
                physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2,
                physical_latitude, physical_longitude, physical_altitude, domestic,
                postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace,
                postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2,
                postal_latitude, postal_longitude, postal_altitude,
                web_address, email_address, phone_number, landline, mobile_number, fax_number,
                unit_size_id, unit_size_code, status_id, status_code, used_for_counting,
                last_edit_comment, last_edit_by_user_id, last_edit_at, has_legal_unit,
                related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
                related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
                related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
                stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
            )
            SELECT
                unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
                primary_activity_category_id, primary_activity_category_path, primary_activity_category_code,
                secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code,
                activity_category_paths, sector_id, sector_path, sector_code, sector_name,
                data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name,
                physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace,
                physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2,
                physical_latitude, physical_longitude, physical_altitude, domestic,
                postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace,
                postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2,
                postal_latitude, postal_longitude, postal_altitude,
                web_address, email_address, phone_number, landline, mobile_number, fax_number,
                unit_size_id, unit_size_code, status_id, status_code, used_for_counting,
                last_edit_comment, last_edit_by_user_id, last_edit_at, has_legal_unit,
                related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
                related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
                related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
                stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
            FROM public.statistical_unit_def
            WHERE unit_type = 'enterprise' AND unit_id BETWEEN v_start_id AND v_end_id;
            v_batch_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_batch_start_time))) * 1000;
            v_current_batch_size := v_batch_size;
            v_batch_speed := v_current_batch_size / (v_batch_duration_ms / 1000.0);
            RAISE DEBUG 'Enterprise SU batch %/% done. (% units, % ms, % units/s)', v_batch_num, ceil(v_total_units::decimal / v_batch_size), v_current_batch_size, round(v_batch_duration_ms), round(v_batch_speed);
        END LOOP; END IF;

        TRUNCATE public.statistical_unit;
        -- Use explicit column list for final insert (temp table has no valid_range)
        INSERT INTO public.statistical_unit (
            unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
            primary_activity_category_id, primary_activity_category_path, primary_activity_category_code,
            secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code,
            activity_category_paths, sector_id, sector_path, sector_code, sector_name,
            data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name,
            physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace,
            physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2,
            physical_latitude, physical_longitude, physical_altitude, domestic,
            postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace,
            postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2,
            postal_latitude, postal_longitude, postal_altitude,
            web_address, email_address, phone_number, landline, mobile_number, fax_number,
            unit_size_id, unit_size_code, status_id, status_code, used_for_counting,
            last_edit_comment, last_edit_by_user_id, last_edit_at, has_legal_unit,
            related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
            related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
            related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
            stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
        )
        SELECT
            unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
            primary_activity_category_id, primary_activity_category_path, primary_activity_category_code,
            secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code,
            activity_category_paths, sector_id, sector_path, sector_code, sector_name,
            data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name,
            physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace,
            physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2,
            physical_latitude, physical_longitude, physical_altitude, domestic,
            postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace,
            postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2,
            postal_latitude, postal_longitude, postal_altitude,
            web_address, email_address, phone_number, landline, mobile_number, fax_number,
            unit_size_id, unit_size_code, status_id, status_code, used_for_counting,
            last_edit_comment, last_edit_by_user_id, last_edit_at, has_legal_unit,
            related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
            related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
            related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
            stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
        FROM statistical_unit_new;

        ANALYZE public.statistical_unit;
    ELSE
        -- =====================================================================
        -- PARTIAL REFRESH: Write only to staging table.
        -- Main table is NOT modified here — flush_staging handles the atomic swap.
        -- This means worker crash leaves main table complete (with old data).
        -- =====================================================================

        IF p_establishment_id_ranges IS NOT NULL THEN
            -- Delete from staging to handle multiple updates to same unit within a derive cycle
            DELETE FROM public.statistical_unit_staging WHERE unit_type = 'establishment' AND unit_id <@ p_establishment_id_ranges;
            -- Insert to staging table (explicit columns - staging doesn't have valid_range)
            INSERT INTO public.statistical_unit_staging (
                unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
                primary_activity_category_id, primary_activity_category_path, primary_activity_category_code,
                secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code,
                activity_category_paths, sector_id, sector_path, sector_code, sector_name,
                data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name,
                physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace,
                physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2,
                physical_latitude, physical_longitude, physical_altitude, domestic,
                postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace,
                postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2,
                postal_latitude, postal_longitude, postal_altitude,
                web_address, email_address, phone_number, landline, mobile_number, fax_number,
                unit_size_id, unit_size_code, status_id, status_code, used_for_counting,
                last_edit_comment, last_edit_by_user_id, last_edit_at, has_legal_unit,
                related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
                related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
                related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
                stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
            )
            SELECT
                unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
                primary_activity_category_id, primary_activity_category_path, primary_activity_category_code,
                secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code,
                activity_category_paths, sector_id, sector_path, sector_code, sector_name,
                data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name,
                physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace,
                physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2,
                physical_latitude, physical_longitude, physical_altitude, domestic,
                postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace,
                postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2,
                postal_latitude, postal_longitude, postal_altitude,
                web_address, email_address, phone_number, landline, mobile_number, fax_number,
                unit_size_id, unit_size_code, status_id, status_code, used_for_counting,
                last_edit_comment, last_edit_by_user_id, last_edit_at, has_legal_unit,
                related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
                related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
                related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
                stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
            FROM import.get_statistical_unit_data_partial('establishment', p_establishment_id_ranges);
        END IF;
        IF p_legal_unit_id_ranges IS NOT NULL THEN
            -- Delete from staging to handle multiple updates to same unit within a derive cycle
            DELETE FROM public.statistical_unit_staging WHERE unit_type = 'legal_unit' AND unit_id <@ p_legal_unit_id_ranges;
            -- Insert to staging table (explicit columns - staging doesn't have valid_range)
            INSERT INTO public.statistical_unit_staging (
                unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
                primary_activity_category_id, primary_activity_category_path, primary_activity_category_code,
                secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code,
                activity_category_paths, sector_id, sector_path, sector_code, sector_name,
                data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name,
                physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace,
                physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2,
                physical_latitude, physical_longitude, physical_altitude, domestic,
                postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace,
                postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2,
                postal_latitude, postal_longitude, postal_altitude,
                web_address, email_address, phone_number, landline, mobile_number, fax_number,
                unit_size_id, unit_size_code, status_id, status_code, used_for_counting,
                last_edit_comment, last_edit_by_user_id, last_edit_at, has_legal_unit,
                related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
                related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
                related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
                stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
            )
            SELECT
                unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
                primary_activity_category_id, primary_activity_category_path, primary_activity_category_code,
                secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code,
                activity_category_paths, sector_id, sector_path, sector_code, sector_name,
                data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name,
                physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace,
                physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2,
                physical_latitude, physical_longitude, physical_altitude, domestic,
                postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace,
                postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2,
                postal_latitude, postal_longitude, postal_altitude,
                web_address, email_address, phone_number, landline, mobile_number, fax_number,
                unit_size_id, unit_size_code, status_id, status_code, used_for_counting,
                last_edit_comment, last_edit_by_user_id, last_edit_at, has_legal_unit,
                related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
                related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
                related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
                stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
            FROM import.get_statistical_unit_data_partial('legal_unit', p_legal_unit_id_ranges);
        END IF;
        IF p_enterprise_id_ranges IS NOT NULL THEN
            -- Delete from staging to handle multiple updates to same unit within a derive cycle
            DELETE FROM public.statistical_unit_staging WHERE unit_type = 'enterprise' AND unit_id <@ p_enterprise_id_ranges;
            -- Insert to staging table (explicit columns - staging doesn't have valid_range)
            INSERT INTO public.statistical_unit_staging (
                unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
                primary_activity_category_id, primary_activity_category_path, primary_activity_category_code,
                secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code,
                activity_category_paths, sector_id, sector_path, sector_code, sector_name,
                data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name,
                physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace,
                physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2,
                physical_latitude, physical_longitude, physical_altitude, domestic,
                postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace,
                postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2,
                postal_latitude, postal_longitude, postal_altitude,
                web_address, email_address, phone_number, landline, mobile_number, fax_number,
                unit_size_id, unit_size_code, status_id, status_code, used_for_counting,
                last_edit_comment, last_edit_by_user_id, last_edit_at, has_legal_unit,
                related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
                related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
                related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
                stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
            )
            SELECT
                unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
                primary_activity_category_id, primary_activity_category_path, primary_activity_category_code,
                secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code,
                activity_category_paths, sector_id, sector_path, sector_code, sector_name,
                data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name,
                physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace,
                physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2,
                physical_latitude, physical_longitude, physical_altitude, domestic,
                postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace,
                postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2,
                postal_latitude, postal_longitude, postal_altitude,
                web_address, email_address, phone_number, landline, mobile_number, fax_number,
                unit_size_id, unit_size_code, status_id, status_code, used_for_counting,
                last_edit_comment, last_edit_by_user_id, last_edit_at, has_legal_unit,
                related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
                related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
                related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
                stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
            FROM import.get_statistical_unit_data_partial('enterprise', p_enterprise_id_ranges);
        END IF;
    END IF;
END;
$procedure$
;

-- create_statistical_unit_ui_indices
CREATE OR REPLACE FUNCTION admin.create_statistical_unit_ui_indices()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Standard btree indices
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_unit_type ON public.statistical_unit (unit_type);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_establishment_id ON public.statistical_unit (unit_id);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_primary_activity_category_id ON public.statistical_unit (primary_activity_category_id);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_secondary_activity_category_id ON public.statistical_unit (secondary_activity_category_id);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_physical_region_id ON public.statistical_unit (physical_region_id);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_physical_country_id ON public.statistical_unit (physical_country_id);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_sector_id ON public.statistical_unit (sector_id);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_domestic ON public.statistical_unit (domestic);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_legal_form_id ON public.statistical_unit (legal_form_id);

    -- Path indices (btree + gist for ltree)
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_sector_path ON public.statistical_unit(sector_path);
    CREATE INDEX IF NOT EXISTS idx_gist_statistical_unit_sector_path ON public.statistical_unit USING GIST (sector_path);

    CREATE INDEX IF NOT EXISTS idx_statistical_unit_primary_activity_category_path ON public.statistical_unit(primary_activity_category_path);
    CREATE INDEX IF NOT EXISTS idx_gist_statistical_unit_primary_activity_category_path ON public.statistical_unit USING GIST (primary_activity_category_path);

    CREATE INDEX IF NOT EXISTS idx_statistical_unit_secondary_activity_category_path ON public.statistical_unit(secondary_activity_category_path);
    CREATE INDEX IF NOT EXISTS idx_gist_statistical_unit_secondary_activity_category_path ON public.statistical_unit USING GIST (secondary_activity_category_path);

    CREATE INDEX IF NOT EXISTS idx_statistical_unit_activity_category_paths ON public.statistical_unit(activity_category_paths);
    CREATE INDEX IF NOT EXISTS idx_gist_statistical_unit_activity_category_paths ON public.statistical_unit USING GIST (activity_category_paths);

    CREATE INDEX IF NOT EXISTS idx_statistical_unit_physical_region_path ON public.statistical_unit(physical_region_path);
    CREATE INDEX IF NOT EXISTS idx_gist_statistical_unit_physical_region_path ON public.statistical_unit USING GIST (physical_region_path);

    CREATE INDEX IF NOT EXISTS idx_statistical_unit_tag_paths ON public.statistical_unit(tag_paths);
    CREATE INDEX IF NOT EXISTS idx_gist_statistical_unit_tag_paths ON public.statistical_unit USING GIST (tag_paths);

    -- External idents indices
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_external_idents ON public.statistical_unit(external_idents);
    CREATE INDEX IF NOT EXISTS idx_gist_statistical_unit_external_idents ON public.statistical_unit USING GIN (external_idents jsonb_path_ops);

    -- GIN indices for arrays and jsonb
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_search ON public.statistical_unit USING GIN (search);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_data_source_ids ON public.statistical_unit USING GIN (data_source_ids);

    CREATE INDEX IF NOT EXISTS idx_statistical_unit_related_establishment_ids ON public.statistical_unit USING gin (related_establishment_ids);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_related_legal_unit_ids ON public.statistical_unit USING gin (related_legal_unit_ids);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_related_enterprise_ids ON public.statistical_unit USING gin (related_enterprise_ids);

    -- Dynamic jsonb indices (su_ei_*, su_s_*, su_ss_*)
    -- These are created by admin.generate_statistical_unit_jsonb_indices()
    CALL admin.generate_statistical_unit_jsonb_indices();

    RAISE DEBUG 'Created all statistical_unit UI indices';
END;
$function$
;

-- Step 7: Update import procedures

-- process_legal_unit
CREATE OR REPLACE PROCEDURE import.process_legal_unit(IN p_job_id integer, IN p_batch_seq integer, IN p_step_code text)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_job public.import_job;
    v_definition public.import_definition;
    v_definition_snapshot JSONB;
    v_step public.import_step;
    v_edit_by_user_id INT;
    v_data_table_name TEXT;
    v_sql TEXT;
    v_error_count INT := 0;
    v_update_count INT := 0;
    error_message TEXT;
    v_batch_result RECORD;
    rec_created_lu RECORD;
    v_start_time TIMESTAMPTZ;
    v_duration_ms NUMERIC;
    v_merge_mode sql_saga.temporal_merge_mode;
BEGIN
    v_start_time := clock_timestamp();
    RAISE DEBUG '[Job %] process_legal_unit (Batch): Starting operation for batch_seq %', p_job_id, p_batch_seq;

    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    v_definition_snapshot := v_job.definition_snapshot;

    IF v_definition_snapshot IS NULL OR jsonb_typeof(v_definition_snapshot) != 'object' THEN
        RAISE EXCEPTION '[Job %] Failed to load valid definition snapshot from import_job record', p_job_id;
    END IF;
    SELECT * INTO v_definition FROM jsonb_populate_record(NULL::public.import_definition, v_job.definition_snapshot->'import_definition');
    IF v_definition IS NULL THEN RAISE EXCEPTION '[Job %] Failed to load import_definition from snapshot', p_job_id; END IF;

    -- Find the step details from the snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'legal_unit';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] legal_unit target step not found in snapshot', p_job_id;
    END IF;

    v_edit_by_user_id := v_job.user_id;

    RAISE DEBUG '[Job %] process_legal_unit: Operation Type: %, User ID: %', p_job_id, v_definition.strategy, v_edit_by_user_id;

    -- Create an updatable view over the batch data. This avoids copying data to a temp table
    -- and allows sql_saga to write feedback and generated IDs directly back to the main data table.
    v_sql := format($$
        CREATE OR REPLACE TEMP VIEW temp_lu_source_view AS
        SELECT
            row_id AS data_row_id,
            founding_row_id,
            legal_unit_id AS id,
            name,
            birth_date,
            death_date,
            valid_from,
            valid_to,
            valid_until,
            sector_id,
            unit_size_id,
            status_id,
            legal_form_id,
            data_source_id,
            enterprise_id,
            primary_for_enterprise,
            edit_by_user_id,
            edit_at,
            edit_comment,
            errors,
            merge_status
        FROM public.%1$I
        WHERE batch_seq = %2$L AND action = 'use';
    $$, v_data_table_name /* %1$I */, p_batch_seq /* %2$L */);
    RAISE DEBUG '[Job %] process_legal_unit: Creating temp view with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Log the contents of the source view for debugging
    IF current_setting('client_min_messages') = 'debug' THEN
        DECLARE
            r RECORD;
        BEGIN
            FOR r IN SELECT * FROM temp_lu_source_view ORDER BY data_row_id LOOP
                RAISE DEBUG '[Job %][Row %] process_legal_unit source_view: lu_id=%, ent_id=%, valid_to="%", valid_until="%", death_date="%"', p_job_id, r.data_row_id, r.id, r.enterprise_id, r.valid_to, r.valid_until, r.death_date;
            END LOOP;
        END;
    END IF;

    BEGIN
        -- Demotion logic
        IF to_regclass('pg_temp.temp_lu_demotion_source') IS NOT NULL THEN DROP TABLE temp_lu_demotion_source; END IF;
        CREATE TEMP TABLE temp_lu_demotion_source (
            row_id int generated by default as identity,
            id INT NOT NULL,
            primary_for_enterprise BOOLEAN NOT NULL,
            valid_from DATE NOT NULL,
            valid_until DATE NOT NULL,
            edit_by_user_id INT,
            edit_at TIMESTAMPTZ,
            edit_comment TEXT
        ) ON COMMIT DROP;

        RAISE DEBUG '[Job %] process_legal_unit: Starting demotion of conflicting primary LUs.', p_job_id;
        v_sql := format($$
            INSERT INTO temp_lu_demotion_source (id, primary_for_enterprise, valid_from, valid_until, edit_by_user_id, edit_at, edit_comment)
            SELECT
                ex_lu.id, false, incoming_primary.new_primary_valid_from, incoming_primary.new_primary_valid_until,
                incoming_primary.demotion_edit_by_user_id, incoming_primary.demotion_edit_at,
                'Demoted from primary by import job ' || %1$L ||
                '; new primary is LU ' || COALESCE(incoming_primary.incoming_lu_id::TEXT, 'NEW') ||
                ' for enterprise ' || incoming_primary.target_enterprise_id ||
                ' during [' || incoming_primary.new_primary_valid_from || ', ' || incoming_primary.new_primary_valid_until || ')'
            FROM public.legal_unit ex_lu
            JOIN (
                SELECT dt.legal_unit_id AS incoming_lu_id, dt.enterprise_id AS target_enterprise_id,
                       dt.valid_from AS new_primary_valid_from, dt.valid_until AS new_primary_valid_until,
                       dt.edit_by_user_id AS demotion_edit_by_user_id, dt.edit_at AS demotion_edit_at
                FROM public.%2$I dt
                WHERE dt.batch_seq = $1
                  AND dt.primary_for_enterprise = true AND dt.enterprise_id IS NOT NULL
            ) AS incoming_primary
            ON ex_lu.enterprise_id = incoming_primary.target_enterprise_id
            WHERE ex_lu.id IS DISTINCT FROM incoming_primary.incoming_lu_id
              AND ex_lu.primary_for_enterprise = true
              AND public.from_until_overlaps(ex_lu.valid_from, ex_lu.valid_until, incoming_primary.new_primary_valid_from, incoming_primary.new_primary_valid_until);
        $$, p_job_id /* %1$L */, v_data_table_name /* %2$I */);
        RAISE DEBUG '[Job %] process_legal_unit: Populating demotion source with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql USING p_batch_seq;

        IF FOUND THEN
            RAISE DEBUG '[Job %] process_legal_unit: Identified % LUs for demotion.', p_job_id, (SELECT count(*) FROM temp_lu_demotion_source);
            CALL sql_saga.temporal_merge(
                target_table => 'public.legal_unit'::regclass,
                source_table => 'temp_lu_demotion_source'::regclass,
                primary_identity_columns => ARRAY['id'],
                mode => 'PATCH_FOR_PORTION_OF',
                row_id_column => 'row_id'
            );
            FOR v_batch_result IN SELECT * FROM pg_temp.temporal_merge_feedback WHERE status = 'ERROR' LOOP
                 RAISE WARNING '[Job %] process_legal_unit: Error during demotion for LU ID %: %', p_job_id, (v_batch_result.target_entity_ids->0->>'id')::INT, v_batch_result.error_message;
            END LOOP;
        ELSE
            RAISE DEBUG '[Job %] process_legal_unit: No existing primary LUs found to demote.', p_job_id;
        END IF;

        -- Main data merge operation
        -- Determine merge mode from job strategy
        v_merge_mode := CASE v_definition.strategy
            WHEN 'insert_or_replace' THEN 'MERGE_ENTITY_REPLACE'::sql_saga.temporal_merge_mode
            WHEN 'replace_only' THEN 'REPLACE_FOR_PORTION_OF'::sql_saga.temporal_merge_mode
            WHEN 'insert_or_update' THEN 'MERGE_ENTITY_PATCH'::sql_saga.temporal_merge_mode
            WHEN 'update_only' THEN 'UPDATE_FOR_PORTION_OF'::sql_saga.temporal_merge_mode
            ELSE 'MERGE_ENTITY_PATCH'::sql_saga.temporal_merge_mode -- Default to safer patch for other cases
        END;
        RAISE DEBUG '[Job %] process_legal_unit: Determined merge mode % from strategy %', p_job_id, v_merge_mode, v_definition.strategy;

        RAISE DEBUG '[Job %] process_legal_unit: Calling main sql_saga.temporal_merge operation.', p_job_id;
        CALL sql_saga.temporal_merge(
            target_table => 'public.legal_unit'::regclass,
            source_table => 'temp_lu_source_view'::regclass,
            primary_identity_columns => ARRAY['id'],
            mode => v_merge_mode,
            row_id_column => 'data_row_id',
            founding_id_column => 'founding_row_id',
            update_source_with_identity => true,
            update_source_with_feedback => true,
            feedback_status_column => 'merge_status',
            feedback_status_key => 'legal_unit',
            feedback_error_column => 'errors',
            feedback_error_key => 'legal_unit'
        );

        -- With feedback written directly to the data table, we just need to count successes and errors.
        v_sql := format($$ SELECT count(*) FROM public.%1$I dt WHERE dt.batch_seq = $1 AND dt.errors->'legal_unit' IS NOT NULL $$, v_data_table_name);
        RAISE DEBUG '[Job %] process_legal_unit: Counting merge errors with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql INTO v_error_count USING p_batch_seq;

        v_sql := format($$
            UPDATE public.%1$I dt SET
                state = CASE WHEN dt.errors ? 'legal_unit' THEN 'error'::public.import_data_state ELSE 'processing'::public.import_data_state END
            WHERE dt.batch_seq = $1 AND dt.action = 'use';
        $$, v_data_table_name);
        RAISE DEBUG '[Job %] process_legal_unit: Updating state post-merge with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql USING p_batch_seq;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        v_update_count := v_update_count - v_error_count;

        RAISE DEBUG '[Job %] process_legal_unit: temporal_merge finished. Success: %, Errors: %', p_job_id, v_update_count, v_error_count;

        -- Intra-batch propagation of newly assigned legal_unit_id
        RAISE DEBUG '[Job %] process_legal_unit: Propagating legal_unit_id for new entities within the batch.', p_job_id;
        v_sql := format($$
            WITH id_source AS (
                SELECT DISTINCT src.founding_row_id, src.legal_unit_id
                FROM public.%1$I src
                WHERE src.batch_seq = $1
                  AND src.legal_unit_id IS NOT NULL
            )
            UPDATE public.%1$I dt
            SET legal_unit_id = id_source.legal_unit_id
            FROM id_source
            WHERE dt.batch_seq = $1
              AND dt.founding_row_id = id_source.founding_row_id
              AND dt.legal_unit_id IS NULL;
        $$, v_data_table_name);
        RAISE DEBUG '[Job %] process_legal_unit: Propagating legal_unit_id with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql USING p_batch_seq;

        -- Process external identifiers now that legal_unit_id is available for new units
        CALL import.helper_process_external_idents(p_job_id, p_batch_seq, 'external_idents');

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_legal_unit: Unhandled error during batch operation: %', p_job_id, replace(error_message, '%', '%%');
        -- Attempt to mark individual data rows as error (best effort)
        BEGIN
            v_sql := format($$UPDATE public.%1$I dt SET state = %2$L, errors = errors || jsonb_build_object('unhandled_error_process_lu', %3$L) WHERE dt.batch_seq = $1 AND dt.state != 'error'$$, -- LCP not changed here
                           v_data_table_name /* %1$I */, 'error'::public.import_data_state /* %2$L */, error_message /* %3$L */);
            RAISE DEBUG '[Job %] process_legal_unit: Marking rows as error in exception handler with SQL: %', p_job_id, v_sql;
            EXECUTE v_sql USING p_batch_seq;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING '[Job %] process_legal_unit: Failed to mark individual data rows as error after unhandled exception: %', p_job_id, SQLERRM;
        END;
        -- Mark the job as failed
        UPDATE public.import_job
        SET error = jsonb_build_object('process_legal_unit_unhandled_error', error_message)::TEXT,
            state = 'failed'
        WHERE id = p_job_id;
        RAISE DEBUG '[Job %] process_legal_unit: Marked job as failed due to unhandled error: %', p_job_id, error_message;
        -- Don't re-raise - job is marked as failed
    END;

    -- The framework now handles advancing priority for all rows, including 'skip'. No update needed here.

    v_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000);
    RAISE DEBUG '[Job %] process_legal_unit (Batch): Finished in % ms. Success: %, Errors: %',
        p_job_id, round(v_duration_ms, 2), v_update_count, v_error_count;
END;
$procedure$
;

-- process_establishment
CREATE OR REPLACE PROCEDURE import.process_establishment(IN p_job_id integer, IN p_batch_seq integer, IN p_step_code text)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_job public.import_job;
    v_definition public.import_definition;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_sql TEXT;
    v_error_count INT := 0;
    v_update_count INT := 0;
    error_message TEXT;
    v_batch_result RECORD;
    rec_created_est RECORD;
    v_select_list TEXT;
    v_job_mode public.import_mode;
    v_start_time TIMESTAMPTZ;
    v_duration_ms NUMERIC;
    v_merge_mode sql_saga.temporal_merge_mode;
BEGIN
    v_start_time := clock_timestamp();
    RAISE DEBUG '[Job %] process_establishment (Batch): Starting operation for batch_seq %', p_job_id, p_batch_seq;

    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    SELECT * INTO v_definition FROM jsonb_populate_record(NULL::public.import_definition, v_job.definition_snapshot->'import_definition');

    IF v_definition IS NULL THEN
        RAISE EXCEPTION '[Job %] Failed to load valid import_definition object from definition_snapshot', p_job_id;
    END IF;

    v_job_mode := v_definition.mode;
    IF v_job_mode IS NULL OR v_job_mode NOT IN ('establishment_formal', 'establishment_informal') THEN
        RAISE EXCEPTION '[Job %] Invalid or missing mode for establishment processing: %. Expected ''establishment_formal'' or ''establishment_informal''.', p_job_id, v_job_mode;
    END IF;
    RAISE DEBUG '[Job %] process_establishment: Job mode is %', p_job_id, v_job_mode;

    -- Find the step details from the snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'establishment';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] establishment target not found in snapshot', p_job_id;
    END IF;

    -- Create an updatable view over the batch data. This view will be the source for the temporal_merge.
    -- The view's columns are conditional on the job mode. This ensures that for 'formal' establishment
    -- imports, we only affect legal_unit_id links, and for 'informal' imports, we only affect
    -- enterprise_id links. This prevents temporal_merge from overwriting existing links with NULLs,
    -- which would violate the check constraint on the 'establishment' table.
    IF v_job_mode = 'establishment_formal' THEN
        v_select_list := $$
            row_id AS data_row_id, founding_row_id,
            legal_unit_id,
            primary_for_legal_unit,
            name, birth_date, death_date,
            valid_from, valid_to, valid_until,
            sector_id, unit_size_id, status_id, data_source_id,
            establishment_id AS id,
            edit_by_user_id, edit_at, edit_comment,
            errors,
            merge_status
        $$;
    ELSIF v_job_mode = 'establishment_informal' THEN
        v_select_list := $$
            row_id AS data_row_id, founding_row_id,
            enterprise_id,
            primary_for_enterprise,
            name, birth_date, death_date,
            valid_from, valid_to, valid_until,
            sector_id, unit_size_id, status_id, data_source_id,
            establishment_id AS id,
            edit_by_user_id, edit_at, edit_comment,
            errors,
            merge_status
        $$;
    END IF;

    -- Drop the view if it exists from a previous run in the same session, to avoid column name/type conflicts with CREATE OR REPLACE VIEW.
    IF to_regclass('pg_temp.temp_es_source_view') IS NOT NULL THEN
        DROP VIEW pg_temp.temp_es_source_view;
    END IF;

    v_sql := format($$
        CREATE TEMP VIEW temp_es_source_view AS
        SELECT %1$s
        FROM public.%2$I dt
        WHERE dt.batch_seq = %3$L AND dt.action = 'use';
    $$,
        v_select_list,     /* %1$s */
        v_data_table_name, /* %2$I */
        p_batch_seq        /* %3$L */
    );
    RAISE DEBUG '[Job %] process_establishment: Creating temp source view with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql;

    BEGIN
        -- Demotion logic
        IF to_regclass('pg_temp.temp_es_demotion_source') IS NOT NULL THEN DROP TABLE temp_es_demotion_source; END IF;
        CREATE TEMP TABLE temp_es_demotion_source (
            row_id int generated by default as identity, id INT NOT NULL, valid_from DATE NOT NULL, valid_until DATE NOT NULL,
            primary_for_legal_unit BOOLEAN, primary_for_enterprise BOOLEAN,
            edit_by_user_id INT, edit_at TIMESTAMPTZ, edit_comment TEXT
        ) ON COMMIT DROP;

        IF v_job_mode = 'establishment_formal' THEN
            v_sql := format($$
                INSERT INTO temp_es_demotion_source (id, valid_from, valid_until, primary_for_legal_unit, edit_by_user_id, edit_at, edit_comment)
                SELECT ex_es.id, ipes.new_primary_valid_from, ipes.new_primary_valid_until, false, ipes.demotion_edit_by_user_id, ipes.demotion_edit_at,
                       'Demoted from primary for LU by import job ' || %1$L || '; new primary is EST ' ||
                       COALESCE(ipes.incoming_est_id::TEXT, 'NEW') || ' for LU ' || ipes.target_legal_unit_id ||
                       ' during [' || ipes.new_primary_valid_from || ', ' || ipes.new_primary_valid_until || ')'
                FROM public.establishment ex_es
                JOIN (SELECT dt.establishment_id AS incoming_est_id, dt.legal_unit_id AS target_legal_unit_id, dt.valid_from AS new_primary_valid_from, dt.valid_until AS new_primary_valid_until, dt.edit_by_user_id AS demotion_edit_by_user_id, dt.edit_at AS demotion_edit_at FROM public.%2$I dt WHERE dt.batch_seq = $1 AND dt.primary_for_legal_unit = true AND dt.legal_unit_id IS NOT NULL) AS ipes
                ON ex_es.legal_unit_id = ipes.target_legal_unit_id
                WHERE ex_es.id IS DISTINCT FROM ipes.incoming_est_id AND ex_es.primary_for_legal_unit = true AND public.from_until_overlaps(ex_es.valid_from, ex_es.valid_until, ipes.new_primary_valid_from, ipes.new_primary_valid_until);
            $$, p_job_id /* %1$L */, v_data_table_name /* %2$I */);
            RAISE DEBUG '[Job %] process_establishment: Populating demotion source (formal) with SQL: %', p_job_id, v_sql;
            EXECUTE v_sql USING p_batch_seq;

            IF FOUND THEN
                CALL sql_saga.temporal_merge(
                    target_table => 'public.establishment'::regclass,
                    source_table => 'temp_es_demotion_source'::regclass,
                    primary_identity_columns => ARRAY['id'],
                    mode => 'PATCH_FOR_PORTION_OF',
                    row_id_column => 'row_id'
                );
                FOR v_batch_result IN SELECT * FROM pg_temp.temporal_merge_feedback WHERE status = 'ERROR' LOOP RAISE WARNING '[Job %] process_establishment: Error during PFLU demotion for EST ID %: %', p_job_id, (v_batch_result.target_entity_ids->0->>'id')::INT, v_batch_result.error_message; END LOOP;
                TRUNCATE TABLE temp_es_demotion_source;
            END IF;
        ELSIF v_job_mode = 'establishment_informal' THEN
            v_sql := format($$
                INSERT INTO temp_es_demotion_source (id, valid_from, valid_until, primary_for_enterprise, edit_by_user_id, edit_at, edit_comment)
                SELECT ex_es.id, ipes.new_primary_valid_from, ipes.new_primary_valid_until, false, ipes.demotion_edit_by_user_id, ipes.demotion_edit_at,
                       'Demoted from primary for EN by import job ' || %1$L || '; new primary is EST ' ||
                       COALESCE(ipes.incoming_est_id::TEXT, 'NEW') || ' for EN ' || ipes.target_enterprise_id ||
                       ' during [' || ipes.new_primary_valid_from || ', ' || ipes.new_primary_valid_until || ')'
                FROM public.establishment ex_es
                JOIN (SELECT dt.establishment_id AS incoming_est_id, dt.enterprise_id AS target_enterprise_id, dt.valid_from AS new_primary_valid_from, dt.valid_until AS new_primary_valid_until, dt.edit_by_user_id AS demotion_edit_by_user_id, dt.edit_at AS demotion_edit_at FROM public.%2$I dt WHERE dt.batch_seq = $1 AND dt.primary_for_enterprise = true AND dt.enterprise_id IS NOT NULL) AS ipes
                ON ex_es.enterprise_id = ipes.target_enterprise_id
                WHERE ex_es.id IS DISTINCT FROM ipes.incoming_est_id AND ex_es.primary_for_enterprise = true AND public.from_until_overlaps(ex_es.valid_from, ex_es.valid_until, ipes.new_primary_valid_from, ipes.new_primary_valid_until);
            $$, p_job_id /* %1$L */, v_data_table_name /* %2$I */);
            RAISE DEBUG '[Job %] process_establishment: Populating demotion source (informal) with SQL: %', p_job_id, v_sql;
            EXECUTE v_sql USING p_batch_seq;

            IF FOUND THEN
                CALL sql_saga.temporal_merge(
                    target_table => 'public.establishment'::regclass,
                    source_table => 'temp_es_demotion_source'::regclass,
                    primary_identity_columns => ARRAY['id'],
                    mode => 'PATCH_FOR_PORTION_OF',
                    row_id_column => 'row_id'
                );
                FOR v_batch_result IN SELECT * FROM pg_temp.temporal_merge_feedback WHERE status = 'ERROR' LOOP RAISE WARNING '[Job %] process_establishment: Error during PFE demotion for EST ID %: %', p_job_id, (v_batch_result.target_entity_ids->0->>'id')::INT, v_batch_result.error_message; END LOOP;
                TRUNCATE TABLE temp_es_demotion_source;
            END IF;
        END IF;

        -- Main data merge operation
        -- Determine merge mode from job strategy
        v_merge_mode := CASE v_definition.strategy
            WHEN 'insert_or_replace' THEN 'MERGE_ENTITY_REPLACE'::sql_saga.temporal_merge_mode
            WHEN 'replace_only' THEN 'MERGE_ENTITY_REPLACE'::sql_saga.temporal_merge_mode
            WHEN 'insert_or_update' THEN 'MERGE_ENTITY_PATCH'::sql_saga.temporal_merge_mode
            WHEN 'update_only' THEN 'MERGE_ENTITY_UPSERT'::sql_saga.temporal_merge_mode
            ELSE 'MERGE_ENTITY_PATCH'::sql_saga.temporal_merge_mode -- Default to safer patch for other cases
        END;
        RAISE DEBUG '[Job %] process_establishment: Determined merge mode % from strategy %', p_job_id, v_merge_mode, v_definition.strategy;

        CALL sql_saga.temporal_merge(
            target_table => 'public.establishment'::regclass,
            source_table => 'temp_es_source_view'::regclass,
            primary_identity_columns => ARRAY['id'],
            mode => v_merge_mode,
            row_id_column => 'data_row_id',
            founding_id_column => 'founding_row_id',
            update_source_with_identity => true,
            update_source_with_feedback => true,
            feedback_status_column => 'merge_status',
            feedback_status_key => 'establishment',
            feedback_error_column => 'errors',
            feedback_error_key => 'establishment'
        );

        -- Process feedback
        v_sql := format($$ SELECT count(*) FROM public.%1$I dt WHERE dt.batch_seq = $1 AND dt.errors->'establishment' IS NOT NULL $$, v_data_table_name);
        RAISE DEBUG '[Job %] process_establishment: Counting merge errors with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql INTO v_error_count USING p_batch_seq;

        v_sql := format($$
            UPDATE public.%1$I dt SET
                state = CASE WHEN dt.errors ? 'establishment' THEN 'error'::public.import_data_state ELSE 'processing'::public.import_data_state END
            WHERE dt.batch_seq = $1 AND dt.action = 'use';
        $$, v_data_table_name);
        RAISE DEBUG '[Job %] process_establishment: Updating state post-merge with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql USING p_batch_seq;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        v_update_count := v_update_count - v_error_count;
        RAISE DEBUG '[Job %] process_establishment: temporal_merge finished. Success: %, Errors: %', p_job_id, v_update_count, v_error_count;

        -- Intra-batch propagation of newly assigned establishment_id
        RAISE DEBUG '[Job %] process_establishment: Propagating establishment_id for new entities within the batch.', p_job_id;
        v_sql := format($$
            WITH id_source AS (
                SELECT DISTINCT src.founding_row_id, src.establishment_id
                FROM public.%1$I src
                WHERE src.batch_seq = $1
                  AND src.establishment_id IS NOT NULL
            )
            UPDATE public.%1$I dt
            SET establishment_id = id_source.establishment_id
            FROM id_source
            WHERE dt.batch_seq = $1
              AND dt.founding_row_id = id_source.founding_row_id
              AND dt.establishment_id IS NULL;
        $$, v_data_table_name);
        RAISE DEBUG '[Job %] process_establishment: Propagating establishment_id with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql USING p_batch_seq;

        -- Process external identifiers now that establishment_id is available for new units
        CALL import.helper_process_external_idents(p_job_id, p_batch_seq, 'external_idents');

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_establishment: Unhandled error during batch operation: %', p_job_id, replace(error_message, '%', '%%');
        -- Attempt to mark individual data rows as error (best effort)
        BEGIN
            v_sql := format($$UPDATE public.%1$I dt SET state = 'error'::public.import_data_state, errors = errors || jsonb_build_object('unhandled_error_process_est', %2$L) WHERE dt.batch_seq = $1 AND dt.state != 'error'::public.import_data_state$$,
                           v_data_table_name, /* %1$I */
                           error_message      /* %2$L */
            );
            RAISE DEBUG '[Job %] process_establishment: Marking rows as error in exception handler with SQL: %', p_job_id, v_sql;
            EXECUTE v_sql USING p_batch_seq;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING '[Job %] process_establishment: Failed to mark batch rows as error after unhandled exception: %', p_job_id, SQLERRM;
        END;
        -- Mark the job as failed
        UPDATE public.import_job
        SET error = jsonb_build_object('process_establishment_unhandled_error', error_message)::TEXT,
            state = 'failed'
        WHERE id = p_job_id;
        RAISE DEBUG '[Job %] process_establishment: Marked job as failed due to unhandled error: %', p_job_id, error_message;
        -- Don't re-raise - job is marked as failed
    END;

    -- The framework now handles advancing priority for all rows.
    v_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000);
    RAISE DEBUG '[Job %] process_establishment (Batch): Finished in % ms. Success: %, Errors: %', p_job_id, round(v_duration_ms, 2), v_update_count, v_error_count;
END;
$procedure$
;

-- Step 7b: Fix timeline_enterprise_refresh (remove invalid_codes references)
-- Step 7c: Fix statistical_unit_flush_staging (remove invalid_codes references)
-- These functions reference columns that were just dropped.
-- Content inserted by shell below.

CREATE OR REPLACE PROCEDURE public.timeline_enterprise_refresh(IN p_unit_id_ranges int4multirange DEFAULT NULL::int4multirange)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    p_target_table text := 'timeline_enterprise';
    p_unit_type public.statistical_unit_type := 'enterprise';
    v_batch_size INT := 32768;
    v_def_view_name text := p_target_table || '_def';
    v_min_id int; v_max_id int; v_start_id int; v_end_id int;
    v_batch_num INT := 0;
    v_total_units INT;
    v_batch_start_time timestamptz;
    v_batch_duration_ms numeric;
    v_batch_speed numeric;
    v_current_batch_size int;
    v_unit_ids INT[];
BEGIN
    IF p_unit_id_ranges IS NULL THEN
        -- Full refresh: ANALYZE and use the generic view-based approach
        ANALYZE public.timesegments, public.enterprise, public.timeline_legal_unit, public.timeline_establishment;

        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units
        FROM public.timesegments WHERE unit_type = p_unit_type;
        IF v_min_id IS NULL THEN RETURN; END IF;

        RAISE DEBUG 'Refreshing enterprise timeline for % units in batches of %...', v_total_units, v_batch_size;
        FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_start_time := clock_timestamp();
            v_batch_num := v_batch_num + 1;
            v_start_id := i; v_end_id := i + v_batch_size - 1;
            EXECUTE format('DELETE FROM public.%I WHERE unit_type = %L AND unit_id BETWEEN %L AND %L',
                           p_target_table, p_unit_type, v_start_id, v_end_id);
            EXECUTE format('INSERT INTO public.%I SELECT * FROM public.%I WHERE unit_type = %L AND unit_id BETWEEN %L AND %L',
                           p_target_table, v_def_view_name, p_unit_type, v_start_id, v_end_id);

            v_batch_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_batch_start_time))) * 1000;
            v_current_batch_size := v_batch_size;
            v_batch_speed := v_current_batch_size / (v_batch_duration_ms / 1000.0);
            RAISE DEBUG 'Enterprise timeline batch %/% done. (% units, % ms, % units/s)',
                v_batch_num, ceil(v_total_units::decimal / v_batch_size), v_current_batch_size,
                round(v_batch_duration_ms), round(v_batch_speed);
        END LOOP;

        EXECUTE format('ANALYZE public.%I', p_target_table);
    ELSE
        -- Partial refresh: Pre-materialize filtered tables to avoid O(n²) scan
        v_unit_ids := public.int4multirange_to_array(p_unit_id_ranges);

        -- Drop staging tables if exist from previous run (silent, no NOTICE)
        PERFORM set_config('client_min_messages', 'warning', true);
        DROP TABLE IF EXISTS public.timeline_legal_unit_filtered;
        DROP TABLE IF EXISTS public.timeline_establishment_filtered;
        PERFORM set_config('client_min_messages', 'notice', true);

        -- Pre-filter timeline_legal_unit to only rows for these enterprises
        -- Use UNLOGGED for cross-session visibility (enables concurrency > 1)
        CREATE UNLOGGED TABLE public.timeline_legal_unit_filtered AS
        SELECT tlu.*
        FROM public.timeline_legal_unit tlu
        WHERE tlu.enterprise_id = ANY(v_unit_ids);

        -- Create index for the join
        CREATE INDEX ON public.timeline_legal_unit_filtered (enterprise_id, valid_from, valid_until);
        ANALYZE public.timeline_legal_unit_filtered;

        -- Pre-filter timeline_establishment to only rows for these enterprises
        CREATE UNLOGGED TABLE public.timeline_establishment_filtered AS
        SELECT tes.*
        FROM public.timeline_establishment tes
        WHERE tes.enterprise_id = ANY(v_unit_ids);

        -- Create index for the join
        CREATE INDEX ON public.timeline_establishment_filtered (enterprise_id, valid_from, valid_until);
        ANALYZE public.timeline_establishment_filtered;

        -- Delete existing rows for these units
        DELETE FROM public.timeline_enterprise
        WHERE unit_type = 'enterprise' AND unit_id = ANY(v_unit_ids);

        -- Insert using pre-filtered temp tables
        -- This is the timeline_enterprise_def query but using temp tables
        INSERT INTO public.timeline_enterprise
        WITH aggregation AS (
            SELECT ten.enterprise_id,
                ten.valid_from,
                ten.valid_until,
                public.array_distinct_concat(COALESCE(array_cat(tlu.data_source_ids, tes.data_source_ids), tlu.data_source_ids, tes.data_source_ids)) AS data_source_ids,
                public.array_distinct_concat(COALESCE(array_cat(tlu.data_source_codes, tes.data_source_codes), tlu.data_source_codes, tes.data_source_codes)) AS data_source_codes,
                public.array_distinct_concat(COALESCE(array_cat(tlu.related_establishment_ids, tes.related_establishment_ids), tlu.related_establishment_ids, tes.related_establishment_ids)) AS related_establishment_ids,
                public.array_distinct_concat(COALESCE(array_cat(tlu.excluded_establishment_ids, tes.excluded_establishment_ids), tlu.excluded_establishment_ids, tes.excluded_establishment_ids)) AS excluded_establishment_ids,
                public.array_distinct_concat(COALESCE(array_cat(tlu.included_establishment_ids, tes.included_establishment_ids), tlu.included_establishment_ids, tes.included_establishment_ids)) AS included_establishment_ids,
                public.array_distinct_concat(tlu.related_legal_unit_ids) AS related_legal_unit_ids,
                public.array_distinct_concat(tlu.excluded_legal_unit_ids) AS excluded_legal_unit_ids,
                public.array_distinct_concat(tlu.included_legal_unit_ids) AS included_legal_unit_ids,
                COALESCE(public.jsonb_stats_merge_agg(COALESCE(public.jsonb_stats_merge(tlu.stats_summary, tes.stats_summary), tlu.stats_summary, tes.stats_summary)), '{}'::jsonb) AS stats_summary
            FROM (
                SELECT t.unit_type,
                    t.unit_id,
                    t.valid_from,
                    t.valid_until,
                    en.id,
                    en.enabled,
                    en.short_name,
                    en.edit_comment,
                    en.edit_by_user_id,
                    en.edit_at,
                    en.id AS enterprise_id
                FROM public.timesegments t
                JOIN public.enterprise en ON t.unit_type = 'enterprise'::public.statistical_unit_type AND t.unit_id = en.id
                WHERE t.unit_id = ANY(v_unit_ids)
            ) ten
            -- CRITICAL FIX: Join against pre-filtered temp table instead of full timeline_legal_unit
            LEFT JOIN LATERAL (
                SELECT tlu_f.enterprise_id,
                    ten.valid_from,
                    ten.valid_until,
                    public.array_distinct_concat(tlu_f.data_source_ids) AS data_source_ids,
                    public.array_distinct_concat(tlu_f.data_source_codes) AS data_source_codes,
                    public.array_distinct_concat(tlu_f.related_establishment_ids) AS related_establishment_ids,
                    public.array_distinct_concat(tlu_f.excluded_establishment_ids) AS excluded_establishment_ids,
                    public.array_distinct_concat(tlu_f.included_establishment_ids) AS included_establishment_ids,
                    array_agg(DISTINCT tlu_f.legal_unit_id) AS related_legal_unit_ids,
                    array_agg(DISTINCT tlu_f.legal_unit_id) FILTER (WHERE NOT tlu_f.used_for_counting) AS excluded_legal_unit_ids,
                    array_agg(DISTINCT tlu_f.legal_unit_id) FILTER (WHERE tlu_f.used_for_counting) AS included_legal_unit_ids,
                    public.jsonb_stats_merge_agg(tlu_f.stats_summary) FILTER (WHERE tlu_f.used_for_counting) AS stats_summary
                FROM public.timeline_legal_unit_filtered tlu_f
                WHERE tlu_f.enterprise_id = ten.enterprise_id
                  AND public.from_until_overlaps(ten.valid_from, ten.valid_until, tlu_f.valid_from, tlu_f.valid_until)
                GROUP BY tlu_f.enterprise_id, ten.valid_from, ten.valid_until
            ) tlu ON true
            -- CRITICAL FIX: Join against pre-filtered temp table instead of full timeline_establishment
            LEFT JOIN LATERAL (
                SELECT tes_f.enterprise_id,
                    ten.valid_from,
                    ten.valid_until,
                    public.array_distinct_concat(tes_f.data_source_ids) AS data_source_ids,
                    public.array_distinct_concat(tes_f.data_source_codes) AS data_source_codes,
                    array_agg(DISTINCT tes_f.establishment_id) AS related_establishment_ids,
                    array_agg(DISTINCT tes_f.establishment_id) FILTER (WHERE NOT tes_f.used_for_counting) AS excluded_establishment_ids,
                    array_agg(DISTINCT tes_f.establishment_id) FILTER (WHERE tes_f.used_for_counting) AS included_establishment_ids,
                    public.jsonb_stats_merge_agg(tes_f.stats_summary) FILTER (WHERE tes_f.used_for_counting) AS stats_summary
                FROM public.timeline_establishment_filtered tes_f
                WHERE tes_f.enterprise_id = ten.enterprise_id
                  AND public.from_until_overlaps(ten.valid_from, ten.valid_until, tes_f.valid_from, tes_f.valid_until)
                GROUP BY tes_f.enterprise_id, ten.valid_from, ten.valid_until
            ) tes ON true
            GROUP BY ten.enterprise_id, ten.valid_from, ten.valid_until
        ), enterprise_with_primary_and_aggregation AS (
            SELECT
                (SELECT array_agg(DISTINCT ids.id) FROM (
                    SELECT unnest(basis.data_source_ids) AS id
                    UNION
                    SELECT unnest(aggregation.data_source_ids) AS id
                ) ids) AS data_source_ids,
                (SELECT array_agg(DISTINCT codes.code) FROM (
                    SELECT unnest(basis.data_source_codes) AS code
                    UNION ALL
                    SELECT unnest(aggregation.data_source_codes) AS code
                ) codes) AS data_source_codes,
                basis.unit_type,
                basis.unit_id,
                basis.valid_from,
                basis.valid_to,
                basis.valid_until,
                basis.name,
                basis.birth_date,
                basis.death_date,
                basis.search,
                basis.primary_activity_category_id,
                basis.primary_activity_category_path,
                basis.primary_activity_category_code,
                basis.secondary_activity_category_id,
                basis.secondary_activity_category_path,
                basis.secondary_activity_category_code,
                basis.activity_category_paths,
                basis.sector_id,
                basis.sector_path,
                basis.sector_code,
                basis.sector_name,
                basis.legal_form_id,
                basis.legal_form_code,
                basis.legal_form_name,
                basis.physical_address_part1,
                basis.physical_address_part2,
                basis.physical_address_part3,
                basis.physical_postcode,
                basis.physical_postplace,
                basis.physical_region_id,
                basis.physical_region_path,
                basis.physical_region_code,
                basis.physical_country_id,
                basis.physical_country_iso_2,
                basis.physical_latitude,
                basis.physical_longitude,
                basis.physical_altitude,
                basis.domestic,
                basis.postal_address_part1,
                basis.postal_address_part2,
                basis.postal_address_part3,
                basis.postal_postcode,
                basis.postal_postplace,
                basis.postal_region_id,
                basis.postal_region_path,
                basis.postal_region_code,
                basis.postal_country_id,
                basis.postal_country_iso_2,
                basis.postal_latitude,
                basis.postal_longitude,
                basis.postal_altitude,
                basis.web_address,
                basis.email_address,
                basis.phone_number,
                basis.landline,
                basis.mobile_number,
                basis.fax_number,
                basis.unit_size_id,
                basis.unit_size_code,
                basis.status_id,
                basis.status_code,
                basis.used_for_counting,
                basis.last_edit_comment,
                basis.last_edit_by_user_id,
                basis.last_edit_at,
                basis.has_legal_unit,
                aggregation.related_establishment_ids,
                aggregation.excluded_establishment_ids,
                aggregation.included_establishment_ids,
                aggregation.related_legal_unit_ids,
                aggregation.excluded_legal_unit_ids,
                aggregation.included_legal_unit_ids,
                basis.enterprise_id,
                basis.primary_establishment_id,
                basis.primary_legal_unit_id,
                CASE WHEN basis.used_for_counting THEN aggregation.stats_summary ELSE '{}'::jsonb END AS stats_summary
            FROM (
                SELECT
                    t.unit_type,
                    t.unit_id,
                    t.valid_from,
                    (t.valid_until - '1 day'::interval)::date AS valid_to,
                    t.valid_until,
                    COALESCE(NULLIF(en.short_name::text, ''::text), plu.name::text, pes.name::text) AS name,
                    COALESCE(plu.birth_date, pes.birth_date) AS birth_date,
                    COALESCE(plu.death_date, pes.death_date) AS death_date,
                    to_tsvector('simple'::regconfig, COALESCE(NULLIF(en.short_name::text, ''::text), plu.name::text, pes.name::text)) AS search,
                    COALESCE(plu.primary_activity_category_id, pes.primary_activity_category_id) AS primary_activity_category_id,
                    COALESCE(plu.primary_activity_category_path, pes.primary_activity_category_path) AS primary_activity_category_path,
                    COALESCE(plu.primary_activity_category_code, pes.primary_activity_category_code) AS primary_activity_category_code,
                    COALESCE(plu.secondary_activity_category_id, pes.secondary_activity_category_id) AS secondary_activity_category_id,
                    COALESCE(plu.secondary_activity_category_path, pes.secondary_activity_category_path) AS secondary_activity_category_path,
                    COALESCE(plu.secondary_activity_category_code, pes.secondary_activity_category_code) AS secondary_activity_category_code,
                    COALESCE(plu.activity_category_paths, pes.activity_category_paths) AS activity_category_paths,
                    COALESCE(plu.sector_id, pes.sector_id) AS sector_id,
                    COALESCE(plu.sector_path, pes.sector_path) AS sector_path,
                    COALESCE(plu.sector_code, pes.sector_code) AS sector_code,
                    COALESCE(plu.sector_name, pes.sector_name) AS sector_name,
                    COALESCE(plu.data_source_ids, pes.data_source_ids) AS data_source_ids,
                    COALESCE(plu.data_source_codes, pes.data_source_codes) AS data_source_codes,
                    COALESCE(plu.legal_form_id, pes.legal_form_id) AS legal_form_id,
                    COALESCE(plu.legal_form_code, pes.legal_form_code) AS legal_form_code,
                    COALESCE(plu.legal_form_name, pes.legal_form_name) AS legal_form_name,
                    COALESCE(plu.physical_address_part1, pes.physical_address_part1) AS physical_address_part1,
                    COALESCE(plu.physical_address_part2, pes.physical_address_part2) AS physical_address_part2,
                    COALESCE(plu.physical_address_part3, pes.physical_address_part3) AS physical_address_part3,
                    COALESCE(plu.physical_postcode, pes.physical_postcode) AS physical_postcode,
                    COALESCE(plu.physical_postplace, pes.physical_postplace) AS physical_postplace,
                    COALESCE(plu.physical_region_id, pes.physical_region_id) AS physical_region_id,
                    COALESCE(plu.physical_region_path, pes.physical_region_path) AS physical_region_path,
                    COALESCE(plu.physical_region_code, pes.physical_region_code) AS physical_region_code,
                    COALESCE(plu.physical_country_id, pes.physical_country_id) AS physical_country_id,
                    COALESCE(plu.physical_country_iso_2, pes.physical_country_iso_2) AS physical_country_iso_2,
                    COALESCE(plu.physical_latitude, pes.physical_latitude) AS physical_latitude,
                    COALESCE(plu.physical_longitude, pes.physical_longitude) AS physical_longitude,
                    COALESCE(plu.physical_altitude, pes.physical_altitude) AS physical_altitude,
                    COALESCE(plu.domestic, pes.domestic) AS domestic,
                    COALESCE(plu.postal_address_part1, pes.postal_address_part1) AS postal_address_part1,
                    COALESCE(plu.postal_address_part2, pes.postal_address_part2) AS postal_address_part2,
                    COALESCE(plu.postal_address_part3, pes.postal_address_part3) AS postal_address_part3,
                    COALESCE(plu.postal_postcode, pes.postal_postcode) AS postal_postcode,
                    COALESCE(plu.postal_postplace, pes.postal_postplace) AS postal_postplace,
                    COALESCE(plu.postal_region_id, pes.postal_region_id) AS postal_region_id,
                    COALESCE(plu.postal_region_path, pes.postal_region_path) AS postal_region_path,
                    COALESCE(plu.postal_region_code, pes.postal_region_code) AS postal_region_code,
                    COALESCE(plu.postal_country_id, pes.postal_country_id) AS postal_country_id,
                    COALESCE(plu.postal_country_iso_2, pes.postal_country_iso_2) AS postal_country_iso_2,
                    COALESCE(plu.postal_latitude, pes.postal_latitude) AS postal_latitude,
                    COALESCE(plu.postal_longitude, pes.postal_longitude) AS postal_longitude,
                    COALESCE(plu.postal_altitude, pes.postal_altitude) AS postal_altitude,
                    COALESCE(plu.web_address, pes.web_address) AS web_address,
                    COALESCE(plu.email_address, pes.email_address) AS email_address,
                    COALESCE(plu.phone_number, pes.phone_number) AS phone_number,
                    COALESCE(plu.landline, pes.landline) AS landline,
                    COALESCE(plu.mobile_number, pes.mobile_number) AS mobile_number,
                    COALESCE(plu.fax_number, pes.fax_number) AS fax_number,
                    COALESCE(plu.unit_size_id, pes.unit_size_id) AS unit_size_id,
                    COALESCE(plu.unit_size_code, pes.unit_size_code) AS unit_size_code,
                    COALESCE(plu.status_id, pes.status_id) AS status_id,
                    COALESCE(plu.status_code, pes.status_code) AS status_code,
                    COALESCE(plu.used_for_counting, pes.used_for_counting, false) AS used_for_counting,
                    last_edit.edit_comment AS last_edit_comment,
                    last_edit.edit_by_user_id AS last_edit_by_user_id,
                    last_edit.edit_at AS last_edit_at,
                    plu.legal_unit_id IS NOT NULL AS has_legal_unit,
                    en.id AS enterprise_id,
                    pes.establishment_id AS primary_establishment_id,
                    plu.legal_unit_id AS primary_legal_unit_id
                FROM public.timesegments t
                JOIN public.enterprise en ON t.unit_type = 'enterprise'::public.statistical_unit_type AND t.unit_id = en.id
                -- Use temp table for primary legal unit lookup
                LEFT JOIN LATERAL (
                    SELECT tlu_f.*
                    FROM public.timeline_legal_unit_filtered tlu_f
                    WHERE tlu_f.enterprise_id = en.id
                      AND tlu_f.primary_for_enterprise = true
                      AND public.from_until_overlaps(t.valid_from, t.valid_until, tlu_f.valid_from, tlu_f.valid_until)
                    ORDER BY tlu_f.valid_from DESC, tlu_f.legal_unit_id DESC
                    LIMIT 1
                ) plu ON true
                -- Use temp table for primary establishment lookup
                LEFT JOIN LATERAL (
                    SELECT tes_f.*
                    FROM public.timeline_establishment_filtered tes_f
                    WHERE tes_f.enterprise_id = en.id
                      AND tes_f.primary_for_enterprise = true
                      AND public.from_until_overlaps(t.valid_from, t.valid_until, tes_f.valid_from, tes_f.valid_until)
                    ORDER BY tes_f.valid_from DESC, tes_f.establishment_id DESC
                    LIMIT 1
                ) pes ON true
                -- Pick the most recent edit from enterprise, primary legal unit, or primary establishment
                LEFT JOIN LATERAL (
                    SELECT all_edits.edit_comment,
                           all_edits.edit_by_user_id,
                           all_edits.edit_at
                    FROM ( VALUES
                        (en.edit_comment, en.edit_by_user_id, en.edit_at),
                        (plu.last_edit_comment, plu.last_edit_by_user_id, plu.last_edit_at),
                        (pes.last_edit_comment, pes.last_edit_by_user_id, pes.last_edit_at)
                    ) all_edits(edit_comment, edit_by_user_id, edit_at)
                    WHERE all_edits.edit_at IS NOT NULL
                    ORDER BY all_edits.edit_at DESC
                    LIMIT 1
                ) last_edit ON true
                WHERE t.unit_id = ANY(v_unit_ids)
            ) basis
            JOIN aggregation ON basis.enterprise_id = aggregation.enterprise_id
                AND basis.valid_from = aggregation.valid_from
                AND basis.valid_until = aggregation.valid_until
        )
        SELECT
            unit_type,
            unit_id,
            valid_from,
            valid_to,
            valid_until,
            name,
            birth_date,
            death_date,
            search,
            primary_activity_category_id,
            primary_activity_category_path,
            primary_activity_category_code,
            secondary_activity_category_id,
            secondary_activity_category_path,
            secondary_activity_category_code,
            activity_category_paths,
            sector_id,
            sector_path,
            sector_code,
            sector_name,
            data_source_ids,
            data_source_codes,
            legal_form_id,
            legal_form_code,
            legal_form_name,
            physical_address_part1,
            physical_address_part2,
            physical_address_part3,
            physical_postcode,
            physical_postplace,
            physical_region_id,
            physical_region_path,
            physical_region_code,
            physical_country_id,
            physical_country_iso_2,
            physical_latitude,
            physical_longitude,
            physical_altitude,
            domestic,
            postal_address_part1,
            postal_address_part2,
            postal_address_part3,
            postal_postcode,
            postal_postplace,
            postal_region_id,
            postal_region_path,
            postal_region_code,
            postal_country_id,
            postal_country_iso_2,
            postal_latitude,
            postal_longitude,
            postal_altitude,
            web_address,
            email_address,
            phone_number,
            landline,
            mobile_number,
            fax_number,
            unit_size_id,
            unit_size_code,
            status_id,
            status_code,
            used_for_counting,
            last_edit_comment,
            last_edit_by_user_id,
            last_edit_at,
            has_legal_unit,
            related_establishment_ids,
            excluded_establishment_ids,
            included_establishment_ids,
            related_legal_unit_ids,
            excluded_legal_unit_ids,
            included_legal_unit_ids,
            ARRAY[enterprise_id] AS related_enterprise_ids,
            ARRAY[]::integer[] AS excluded_enterprise_ids,
            CASE WHEN used_for_counting THEN ARRAY[enterprise_id] ELSE ARRAY[]::integer[] END AS included_enterprise_ids,
            enterprise_id,
            primary_establishment_id,
            primary_legal_unit_id,
            stats_summary
        FROM enterprise_with_primary_and_aggregation
        ORDER BY unit_type, unit_id, valid_from;

        -- Clean up staging tables (silent, no NOTICE)
        PERFORM set_config('client_min_messages', 'warning', true);
        DROP TABLE IF EXISTS public.timeline_legal_unit_filtered;
        DROP TABLE IF EXISTS public.timeline_establishment_filtered;
        PERFORM set_config('client_min_messages', 'notice', true);
    END IF;
END;
$procedure$
;

CREATE OR REPLACE PROCEDURE public.statistical_unit_flush_staging()
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_staging_count BIGINT;
    v_start_time timestamptz;
    v_delete_duration_ms numeric;
    v_insert_duration_ms numeric;
BEGIN
    -- Check if there's anything to flush
    SELECT count(*) INTO v_staging_count FROM public.statistical_unit_staging;

    IF v_staging_count = 0 THEN
        RAISE DEBUG 'statistical_unit_flush_staging: Nothing to flush (staging empty)';
        RETURN;
    END IF;

    RAISE DEBUG 'statistical_unit_flush_staging: Flushing % rows from staging', v_staging_count;

    -- Step 1: Delete from main the rows being replaced (targeted by staging IDs)
    -- This is the atomic swap: old rows out, new rows in, within same transaction.
    v_start_time := clock_timestamp();
    DELETE FROM public.statistical_unit AS su
    USING (SELECT DISTINCT unit_type, unit_id FROM public.statistical_unit_staging) AS s
    WHERE su.unit_type = s.unit_type AND su.unit_id = s.unit_id;
    v_delete_duration_ms := EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000;
    RAISE DEBUG 'statistical_unit_flush_staging: Deleted old rows in % ms', round(v_delete_duration_ms);

    -- Step 2: Insert new data from staging (sorted for B-tree locality)
    v_start_time := clock_timestamp();
    INSERT INTO public.statistical_unit (
        unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
        primary_activity_category_id, primary_activity_category_path, primary_activity_category_code,
        secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code,
        activity_category_paths, sector_id, sector_path, sector_code, sector_name,
        data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name,
        physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace,
        physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2,
        physical_latitude, physical_longitude, physical_altitude, domestic,
        postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace,
        postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2,
        postal_latitude, postal_longitude, postal_altitude,
        web_address, email_address, phone_number, landline, mobile_number, fax_number,
        unit_size_id, unit_size_code, status_id, status_code, used_for_counting,
        last_edit_comment, last_edit_by_user_id, last_edit_at, has_legal_unit,
        related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
        related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
        related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
        stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
    )
    SELECT
        unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
        primary_activity_category_id, primary_activity_category_path, primary_activity_category_code,
        secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code,
        activity_category_paths, sector_id, sector_path, sector_code, sector_name,
        data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name,
        physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace,
        physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2,
        physical_latitude, physical_longitude, physical_altitude, domestic,
        postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace,
        postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2,
        postal_latitude, postal_longitude, postal_altitude,
        web_address, email_address, phone_number, landline, mobile_number, fax_number,
        unit_size_id, unit_size_code, status_id, status_code, used_for_counting,
        last_edit_comment, last_edit_by_user_id, last_edit_at, has_legal_unit,
        related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
        related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
        related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
        stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
    FROM public.statistical_unit_staging
    ORDER BY unit_type, unit_id, valid_from;
    v_insert_duration_ms := EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000;
    RAISE DEBUG 'statistical_unit_flush_staging: Inserted % rows in % ms', v_staging_count, round(v_insert_duration_ms);

    -- Step 3: Clear staging table
    TRUNCATE public.statistical_unit_staging;

    -- Step 4: Update statistics
    ANALYZE public.statistical_unit;

    RAISE DEBUG 'statistical_unit_flush_staging: Complete (delete: % ms, insert: % ms)',
        round(v_delete_duration_ms), round(v_insert_duration_ms);
END;
$procedure$
;


-- Step 8: Restore grants on recreated views
-- Disable sql_saga health_checks BEFORE any GRANT: its __internal_ddl_command_affects_managed_object()
-- returns TRUE for ALL GRANTs, triggering propagation with an over-broad GROUP BY object_type
-- that grants all privileges to all roles, then validation catches the mismatch.
ALTER EVENT TRIGGER sql_saga_health_checks DISABLE;

GRANT SELECT, INSERT ON public.timeline_establishment_def TO authenticated, regular_user, admin_user;
GRANT SELECT, INSERT ON public.timeline_legal_unit_def TO authenticated, regular_user, admin_user;
GRANT SELECT, INSERT ON public.timeline_enterprise_def TO authenticated, regular_user, admin_user;
GRANT SELECT, INSERT ON public.statistical_unit_def TO authenticated, regular_user, admin_user;

GRANT SELECT ON public.legal_unit__for_portion_of_valid TO authenticated, regular_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.legal_unit__for_portion_of_valid TO admin_user;
GRANT SELECT ON public.establishment__for_portion_of_valid TO authenticated, regular_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.establishment__for_portion_of_valid TO admin_user;

ALTER EVENT TRIGGER sql_saga_health_checks ENABLE;

END;
