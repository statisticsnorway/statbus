BEGIN;

-- =============================================================================
-- Integrate jsonb_stats Rust extension
-- Replaces PL/pgSQL jsonb_stats_to_summary / jsonb_stats_summary_merge
-- with compiled Rust extension functions (jsonb_stats_agg, jsonb_stats_merge_agg, etc.)
-- =============================================================================

-- 1. Install the jsonb_stats extension
CREATE EXTENSION jsonb_stats;

-- 2. Add generated `stat` column to stat_for_unit
-- stat() is STRICT (returns NULL for NULL input), so COALESCE picks the first non-null.
-- stat() natively accepts varchar, so no cast needed for value_string.
ALTER TABLE public.stat_for_unit ADD COLUMN stat JSONB GENERATED ALWAYS AS (
    COALESCE(stat(value_int), stat(value_float), stat(value_string), stat(value_bool))
) STORED;

-- 3. Replace timeline_establishment_def view
CREATE OR REPLACE VIEW public.timeline_establishment_def AS
 WITH establishment_stats AS (
         SELECT t_1.unit_id,
            t_1.valid_from,
            jsonb_stats_agg(sd.code, sfu.stat) FILTER (WHERE sd.code IS NOT NULL) AS stats
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
    es.invalid_codes,
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
            es_1.invalid_codes,
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

-- 4. Replace timeline_legal_unit_def view
CREATE OR REPLACE VIEW public.timeline_legal_unit_def AS
 WITH filter_ids AS (
         SELECT string_to_array(NULLIF(current_setting('statbus.filter_unit_ids'::text, true), ''::text), ','::text)::integer[] AS ids
        ), legal_unit_stats AS (
         SELECT t.unit_id,
            t.valid_from,
            jsonb_stats_agg(sd.code, sfu.stat) FILTER (WHERE sd.code IS NOT NULL) AS stats
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
            lu.invalid_codes,
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
                    lu_1.invalid_codes,
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
    basis.invalid_codes,
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

-- 5. Replace timeline_enterprise_def view
CREATE OR REPLACE VIEW public.timeline_enterprise_def AS
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
            basis.invalid_codes,
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
                    COALESCE(enplu.invalid_codes || enpes.invalid_codes, enplu.invalid_codes, enpes.invalid_codes) AS invalid_codes,
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
                            enplu_1.invalid_codes,
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
                            enpes_1.invalid_codes,
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
    invalid_codes,
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

-- 6. Replace timeline_enterprise_refresh procedure
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
                basis.invalid_codes,
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
                    COALESCE(plu.invalid_codes, pes.invalid_codes) AS invalid_codes,
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
            invalid_codes,
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
$procedure$;


-- 7. Replace statistical_history_def function
CREATE OR REPLACE FUNCTION public.statistical_history_def(p_resolution history_resolution, p_year integer, p_month integer, p_partition_seq integer DEFAULT NULL::integer)
 RETURNS SETOF statistical_history_type
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_curr_start date;
    v_curr_stop date;
    v_prev_start date;
    v_prev_stop date;
BEGIN
    -- Manually calculate the date ranges for the current and previous periods.
    IF p_resolution = 'year'::public.history_resolution THEN
        v_curr_start := make_date(p_year, 1, 1);
        v_curr_stop  := make_date(p_year, 12, 31);
        v_prev_start := make_date(p_year - 1, 1, 1);
        v_prev_stop  := make_date(p_year - 1, 12, 31);
    ELSE -- 'year-month'
        v_curr_start := make_date(p_year, p_month, 1);
        v_curr_stop  := (v_curr_start + interval '1 month') - interval '1 day';
        v_prev_stop  := v_curr_start - interval '1 day';
        v_prev_start := date_trunc('month', v_prev_stop)::date;
    END IF;

    RETURN QUERY
    WITH
    units_in_period AS (
        SELECT *
        FROM public.statistical_unit su
        WHERE from_to_overlaps(su.valid_from, su.valid_to, v_prev_start, v_curr_stop)
          -- When computing a single partition, filter by report_partition_seq
          AND (p_partition_seq IS NULL OR su.report_partition_seq = p_partition_seq)
    ),
    latest_versions_curr AS (
        SELECT DISTINCT ON (uip.unit_id, uip.unit_type) uip.*
        FROM units_in_period AS uip
        WHERE uip.valid_from <= v_curr_stop AND uip.valid_to >= v_curr_start
        ORDER BY uip.unit_id, uip.unit_type, uip.valid_from DESC, uip.valid_until DESC
    ),
    latest_versions_prev AS (
        SELECT DISTINCT ON (uip.unit_id, uip.unit_type) uip.*
        FROM units_in_period AS uip
        WHERE uip.valid_from <= v_prev_stop
        ORDER BY uip.unit_id, uip.unit_type, uip.valid_from DESC, uip.valid_until DESC
    ),
    stock_at_end_of_curr AS (
        SELECT * FROM latest_versions_curr lvc
        WHERE lvc.valid_until > v_curr_stop
          AND COALESCE(lvc.birth_date, lvc.valid_from) <= v_curr_stop
          AND (lvc.death_date IS NULL OR lvc.death_date > v_curr_stop)
    ),
    stock_at_end_of_prev AS (
        SELECT * FROM latest_versions_prev lvp
        WHERE lvp.valid_until > v_prev_stop
          AND COALESCE(lvp.birth_date, lvp.valid_from) <= v_prev_stop
          AND (lvp.death_date IS NULL OR lvp.death_date > v_prev_stop)
    ),
    changed_units AS (
        SELECT
            COALESCE(c.unit_id, p.unit_id) AS unit_id,
            COALESCE(c.unit_type, p.unit_type) AS unit_type,
            c AS curr,
            p AS prev,
            lvc AS last_version_in_curr
        FROM stock_at_end_of_curr c
        FULL JOIN stock_at_end_of_prev p ON c.unit_id = p.unit_id AND c.unit_type = p.unit_type
        LEFT JOIN latest_versions_curr lvc ON lvc.unit_id = COALESCE(p.unit_id, c.unit_id) AND lvc.unit_type = COALESCE(p.unit_type, c.unit_type)
    ),
    demographics AS (
        SELECT
            p_resolution, p_year, p_month, unit_type,
            count((curr).unit_id)::integer AS exists_count,
            (count((curr).unit_id) - count((prev).unit_id))::integer AS exists_change,
            count((curr).unit_id) FILTER (WHERE (prev).unit_id IS NULL)::integer AS exists_added_count,
            count((prev).unit_id) FILTER (WHERE (curr).unit_id IS NULL)::integer AS exists_removed_count,
            count((curr).unit_id) FILTER (WHERE (curr).used_for_counting)::integer AS countable_count,
            (count((curr).unit_id) FILTER (WHERE (curr).used_for_counting) - count((prev).unit_id) FILTER (WHERE (prev).used_for_counting))::integer AS countable_change,
            count(*) FILTER (WHERE (curr).used_for_counting AND NOT COALESCE((prev).used_for_counting, false))::integer AS countable_added_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND NOT COALESCE((curr).used_for_counting, false))::integer AS countable_removed_count,
            count(*) FILTER (WHERE (last_version_in_curr).used_for_counting AND (last_version_in_curr).birth_date BETWEEN v_curr_start AND v_curr_stop)::integer AS births,
            count(*) FILTER (WHERE (last_version_in_curr).used_for_counting AND (last_version_in_curr).death_date BETWEEN v_curr_start AND v_curr_stop)::integer AS deaths,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).name IS DISTINCT FROM (prev).name)::integer AS name_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).primary_activity_category_path IS DISTINCT FROM (prev).primary_activity_category_path)::integer AS primary_activity_category_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).secondary_activity_category_path IS DISTINCT FROM (prev).secondary_activity_category_path)::integer AS secondary_activity_category_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).sector_path IS DISTINCT FROM (prev).sector_path)::integer AS sector_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).legal_form_id IS DISTINCT FROM (prev).legal_form_id)::integer AS legal_form_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).physical_region_path IS DISTINCT FROM (prev).physical_region_path)::integer AS physical_region_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).physical_country_id IS DISTINCT FROM (prev).physical_country_id)::integer AS physical_country_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND ((curr).physical_address_part1, (curr).physical_address_part2, (curr).physical_address_part3, (curr).physical_postcode, (curr).physical_postplace) IS DISTINCT FROM ((prev).physical_address_part1, (prev).physical_address_part2, (prev).physical_address_part3, (prev).physical_postcode, (prev).physical_postplace))::integer AS physical_address_change_count
        FROM changed_units
        GROUP BY 1, 2, 3, 4
    )
    SELECT
        d.p_resolution AS resolution, d.p_year AS year, d.p_month AS month, d.unit_type,
        d.exists_count, d.exists_change, d.exists_added_count, d.exists_removed_count,
        d.countable_count, d.countable_change, d.countable_added_count, d.countable_removed_count,
        d.births, d.deaths,
        d.name_change_count, d.primary_activity_category_change_count, d.secondary_activity_category_change_count,
        d.sector_change_count, d.legal_form_change_count, d.physical_region_change_count,
        d.physical_country_change_count, d.physical_address_change_count,
        ss.stats_summary,
        p_partition_seq  -- Pass through the partition_seq
    FROM demographics d
    LEFT JOIN LATERAL (
        SELECT COALESCE(public.jsonb_stats_merge_agg(lvc.stats_summary), '{}'::jsonb) AS stats_summary
        FROM latest_versions_curr lvc
        WHERE lvc.unit_type = d.unit_type AND lvc.used_for_counting
    ) ss ON true;
END;
$function$;


-- 8. Replace statistical_history_facet_def function
CREATE OR REPLACE FUNCTION public.statistical_history_facet_def(p_resolution history_resolution, p_year integer, p_month integer, p_partition_seq integer DEFAULT NULL::integer)
 RETURNS SETOF statistical_history_facet_type
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_curr_start date;
    v_curr_stop date;
    v_prev_start date;
    v_prev_stop date;
BEGIN
    IF p_resolution = 'year'::public.history_resolution THEN
        v_curr_start := make_date(p_year, 1, 1);
        v_curr_stop  := make_date(p_year, 12, 31);
        v_prev_start := make_date(p_year - 1, 1, 1);
        v_prev_stop  := make_date(p_year - 1, 12, 31);
    ELSE
        v_curr_start := make_date(p_year, p_month, 1);
        v_curr_stop  := (v_curr_start + interval '1 month') - interval '1 day';
        v_prev_stop  := v_curr_start - interval '1 day';
        v_prev_start := date_trunc('month', v_prev_stop)::date;
    END IF;

    RETURN QUERY
    WITH
    units_in_period AS (
        SELECT *
        FROM public.statistical_unit su
        WHERE daterange(su.valid_from, su.valid_to, '[)') && daterange(v_prev_start, v_curr_stop + 1, '[)')
          AND (p_partition_seq IS NULL OR su.report_partition_seq = p_partition_seq)
    ),
    latest_versions_curr AS (
        SELECT DISTINCT ON (uip.unit_id, uip.unit_type) uip.*
        FROM units_in_period AS uip
        WHERE uip.valid_from <= v_curr_stop AND uip.valid_to >= v_curr_start
        ORDER BY uip.unit_id, uip.unit_type, uip.valid_from DESC, uip.valid_until DESC
    ),
    latest_versions_prev AS (
        SELECT DISTINCT ON (uip.unit_id, uip.unit_type) uip.*
        FROM units_in_period AS uip
        WHERE uip.valid_from <= v_prev_stop
        ORDER BY uip.unit_id, uip.unit_type, uip.valid_from DESC, uip.valid_until DESC
    ),
    stock_at_end_of_curr AS (
        SELECT * FROM latest_versions_curr lvc
        WHERE lvc.valid_until > v_curr_stop
          AND COALESCE(lvc.birth_date, lvc.valid_from) <= v_curr_stop
          AND (lvc.death_date IS NULL OR lvc.death_date > v_curr_stop)
    ),
    stock_at_end_of_prev AS (
        SELECT * FROM latest_versions_prev lvp
        WHERE lvp.valid_until > v_prev_stop
          AND COALESCE(lvp.birth_date, lvp.valid_from) <= v_prev_stop
          AND (lvp.death_date IS NULL OR lvp.death_date > v_prev_stop)
    ),
    changed_units AS (
        SELECT
            COALESCE(c.unit_id, p.unit_id) AS unit_id,
            COALESCE(c.unit_type, p.unit_type) AS unit_type,
            c AS curr, p AS prev,
            lvc AS last_version_in_curr
        FROM stock_at_end_of_curr c
        FULL JOIN stock_at_end_of_prev p ON c.unit_id = p.unit_id AND c.unit_type = p.unit_type
        LEFT JOIN latest_versions_curr lvc ON lvc.unit_id = COALESCE(p.unit_id, c.unit_id) AND lvc.unit_type = COALESCE(p.unit_type, c.unit_type)
    ),
    demographics AS (
        SELECT
            p_resolution, p_year, p_month, unit_type,
            COALESCE((curr).primary_activity_category_path, (prev).primary_activity_category_path) AS primary_activity_category_path,
            COALESCE((curr).secondary_activity_category_path, (prev).secondary_activity_category_path) AS secondary_activity_category_path,
            COALESCE((curr).sector_path, (prev).sector_path) AS sector_path,
            COALESCE((curr).legal_form_id, (prev).legal_form_id) AS legal_form_id,
            COALESCE((curr).physical_region_path, (prev).physical_region_path) AS physical_region_path,
            COALESCE((curr).physical_country_id, (prev).physical_country_id) AS physical_country_id,
            COALESCE((curr).unit_size_id, (prev).unit_size_id) AS unit_size_id,
            COALESCE((curr).status_id, (prev).status_id) AS status_id,
            count((curr).unit_id)::integer AS exists_count,
            (count((curr).unit_id) - count((prev).unit_id))::integer AS exists_change,
            count((curr).unit_id) FILTER (WHERE (prev).unit_id IS NULL)::integer AS exists_added_count,
            count((prev).unit_id) FILTER (WHERE (curr).unit_id IS NULL)::integer AS exists_removed_count,
            count((curr).unit_id) FILTER (WHERE (curr).used_for_counting)::integer AS countable_count,
            (count((curr).unit_id) FILTER (WHERE (curr).used_for_counting) - count((prev).unit_id) FILTER (WHERE (prev).used_for_counting))::integer AS countable_change,
            count(*) FILTER (WHERE (curr).used_for_counting AND NOT COALESCE((prev).used_for_counting, false))::integer AS countable_added_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND NOT COALESCE((curr).used_for_counting, false))::integer AS countable_removed_count,
            count(*) FILTER (WHERE (last_version_in_curr).used_for_counting AND (last_version_in_curr).birth_date BETWEEN v_curr_start AND v_curr_stop)::integer AS births,
            count(*) FILTER (WHERE (last_version_in_curr).used_for_counting AND (last_version_in_curr).death_date BETWEEN v_curr_start AND v_curr_stop)::integer AS deaths,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).name IS DISTINCT FROM (prev).name)::integer AS name_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).primary_activity_category_path IS DISTINCT FROM (prev).primary_activity_category_path)::integer AS primary_activity_category_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).secondary_activity_category_path IS DISTINCT FROM (prev).secondary_activity_category_path)::integer AS secondary_activity_category_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).sector_path IS DISTINCT FROM (prev).sector_path)::integer AS sector_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).legal_form_id IS DISTINCT FROM (prev).legal_form_id)::integer AS legal_form_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).physical_region_path IS DISTINCT FROM (prev).physical_region_path)::integer AS physical_region_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).physical_country_id IS DISTINCT FROM (prev).physical_country_id)::integer AS physical_country_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND ((curr).physical_address_part1, (curr).physical_address_part2, (curr).physical_address_part3, (curr).physical_postcode, (curr).physical_postplace) IS DISTINCT FROM ((prev).physical_address_part1, (prev).physical_address_part2, (prev).physical_address_part3, (prev).physical_postcode, (prev).physical_postplace))::integer AS physical_address_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).unit_size_id IS DISTINCT FROM (prev).unit_size_id)::integer AS unit_size_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).status_id IS DISTINCT FROM (prev).status_id)::integer AS status_change_count
        FROM changed_units
        GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12
    )
    SELECT
        d.p_resolution, d.p_year, d.p_month, d.unit_type,
        d.primary_activity_category_path, d.secondary_activity_category_path,
        d.sector_path, d.legal_form_id, d.physical_region_path,
        d.physical_country_id, d.unit_size_id, d.status_id,
        d.exists_count, d.exists_change, d.exists_added_count, d.exists_removed_count,
        d.countable_count, d.countable_change, d.countable_added_count, d.countable_removed_count,
        d.births, d.deaths,
        d.name_change_count, d.primary_activity_category_change_count,
        d.secondary_activity_category_change_count, d.sector_change_count,
        d.legal_form_change_count, d.physical_region_change_count,
        d.physical_country_change_count, d.physical_address_change_count,
        d.unit_size_change_count, d.status_change_count,
        ss.stats_summary
    FROM demographics d
    LEFT JOIN LATERAL (
        SELECT COALESCE(public.jsonb_stats_merge_agg(lvc.stats_summary), '{}'::jsonb) AS stats_summary
         FROM latest_versions_curr lvc
         WHERE lvc.unit_type = d.unit_type
           AND lvc.used_for_counting
           AND lvc.primary_activity_category_path IS NOT DISTINCT FROM d.primary_activity_category_path
           AND lvc.secondary_activity_category_path IS NOT DISTINCT FROM d.secondary_activity_category_path
           AND lvc.sector_path IS NOT DISTINCT FROM d.sector_path
           AND lvc.legal_form_id IS NOT DISTINCT FROM d.legal_form_id
           AND lvc.physical_region_path IS NOT DISTINCT FROM d.physical_region_path
           AND lvc.physical_country_id IS NOT DISTINCT FROM d.physical_country_id
           AND lvc.unit_size_id IS NOT DISTINCT FROM d.unit_size_id
           AND lvc.status_id IS NOT DISTINCT FROM d.status_id
    ) ss ON true;
END;
$function$;


-- 9. Replace statistical_unit_facet_drilldown function
CREATE OR REPLACE FUNCTION public.statistical_unit_facet_drilldown(unit_type statistical_unit_type DEFAULT 'enterprise'::statistical_unit_type, region_path ltree DEFAULT NULL::ltree, activity_category_path ltree DEFAULT NULL::ltree, sector_path ltree DEFAULT NULL::ltree, status_id integer DEFAULT NULL::integer, legal_form_id integer DEFAULT NULL::integer, country_id integer DEFAULT NULL::integer, valid_on date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
AS $function$
    -- Use a params intermediary to avoid conflicts
    -- between columns and parameters, leading to tautologies. i.e. 'sh.unit_type = unit_type' is always true.
    WITH params AS (
        SELECT unit_type AS param_unit_type
             , region_path AS param_region_path
             , activity_category_path AS param_activity_category_path
             , sector_path AS param_sector_path
             , status_id AS param_status_id
             , legal_form_id AS param_legal_form_id
             , country_id AS param_country_id
             , valid_on AS param_valid_on
    ), settings_activity_category_standard AS (
        SELECT activity_category_standard_id AS id FROM public.settings
    ),
    -- FINESSE: This function queries the pre-aggregated `statistical_unit_facet` table for a
    -- specific point in time (`valid_on`) to build a snapshot for UI drilldowns.
    -- The core temporal logic `suf.valid_from <= param_valid_on AND param_valid_on < suf.valid_until`
    -- correctly selects the single valid timeslice for the requested date, using the
    -- standard `[start, end)` interval convention.
    available_facet AS (
        SELECT suf.physical_region_path
             , suf.primary_activity_category_path
             , suf.sector_path
             , suf.legal_form_id
             , suf.physical_country_id
             , suf.status_id
             , count
             , stats_summary
        FROM public.statistical_unit_facet AS suf
           , params
        WHERE
            suf.valid_from <= param_valid_on AND param_valid_on < suf.valid_until
            AND (param_unit_type IS NULL OR suf.unit_type = param_unit_type)
            AND (
                param_region_path IS NULL
                OR suf.physical_region_path IS NOT NULL AND suf.physical_region_path OPERATOR(public.<@) param_region_path
            )
            AND (
                param_activity_category_path IS NULL
                OR suf.primary_activity_category_path IS NOT NULL AND suf.primary_activity_category_path OPERATOR(public.<@) param_activity_category_path
            )
            AND (
                param_sector_path IS NULL
                OR suf.sector_path IS NOT NULL AND suf.sector_path OPERATOR(public.<@) param_sector_path
            )
            AND (
                param_status_id IS NULL
                OR suf.status_id IS NOT NULL AND suf.status_id = param_status_id
            )
            AND (
                param_legal_form_id IS NULL
                OR suf.legal_form_id IS NOT NULL AND suf.legal_form_id = param_legal_form_id
            )
            AND (
                param_country_id IS NULL
                OR suf.physical_country_id IS NOT NULL AND suf.physical_country_id = param_country_id
            )
    ), available_facet_stats AS (
        SELECT COALESCE(SUM(af.count), 0) AS count
             , public.jsonb_stats_merge_agg(af.stats_summary) AS stats_summary
        FROM available_facet AS af
    ),
    breadcrumb_region AS (
        SELECT r.path
             , r.label
             , r.code
             , r.name
        FROM public.region AS r
        WHERE
            (   region_path IS NOT NULL
            AND r.path OPERATOR(public.@>) (region_path)
            )
        ORDER BY path
    ),
    available_region AS (
        SELECT r.path
             , r.label
             , r.code
             , r.name
        FROM public.region AS r
        WHERE
            (
                (region_path IS NULL AND r.path OPERATOR(public.~) '*{1}'::public.lquery)
            OR
                (region_path IS NOT NULL AND r.path OPERATOR(public.~) (region_path::text || '.*{1}')::public.lquery)
            )
        ORDER BY r.path
    ), aggregated_region_counts AS (
        SELECT ar.path
             , ar.label
             , ar.code
             , ar.name
             , COALESCE(SUM(suf.count), 0) AS count
             , public.jsonb_stats_merge_agg(suf.stats_summary) AS stats_summary
             , COALESCE(bool_or(true) FILTER (WHERE suf.physical_region_path OPERATOR(public.<>) ar.path), false) AS has_children
        FROM available_region AS ar
        LEFT JOIN available_facet AS suf ON suf.physical_region_path OPERATOR(public.<@) ar.path
        GROUP BY ar.path
               , ar.label
               , ar.code
               , ar.name
        ORDER BY ar.path
    ),
    breadcrumb_activity_category AS (
        SELECT ac.path
             , ac.label
             , ac.code
             , ac.name
        FROM
            public.activity_category AS ac
        WHERE ac.enabled
           AND ac.standard_id = (SELECT id FROM settings_activity_category_standard)
           AND
            (     activity_category_path IS NOT NULL
              AND ac.path OPERATOR(public.@>) activity_category_path
            )
        ORDER BY path
    ),
    available_activity_category AS (
        SELECT ac.path
             , ac.label
             , ac.code
             , ac.name
        FROM
            public.activity_category AS ac
        WHERE ac.enabled
           AND ac.standard_id = (SELECT id FROM settings_activity_category_standard)
           AND
            (
                (activity_category_path IS NULL AND ac.path OPERATOR(public.~) '*{1}'::public.lquery)
            OR
                (activity_category_path IS NOT NULL AND ac.path OPERATOR(public.~) (activity_category_path::text || '.*{1}')::public.lquery)
            )
        ORDER BY ac.path
    ),
    aggregated_activity_counts AS (
        SELECT aac.path
             , aac.label
             , aac.code
             , aac.name
             , COALESCE(SUM(suf.count), 0) AS count
             , public.jsonb_stats_merge_agg(suf.stats_summary) AS stats_summary
             , COALESCE(bool_or(true) FILTER (WHERE suf.primary_activity_category_path OPERATOR(public.<>) aac.path), false) AS has_children
        FROM
            available_activity_category AS aac
        LEFT JOIN available_facet AS suf ON suf.primary_activity_category_path OPERATOR(public.<@) aac.path
        GROUP BY aac.path
               , aac.label
               , aac.code
               , aac.name
        ORDER BY aac.path
    ),
    breadcrumb_sector AS (
        SELECT s.path
             , s.label
             , s.code
             , s.name
        FROM public.sector AS s
        WHERE
            (   sector_path IS NOT NULL
            AND s.path OPERATOR(public.@>) (sector_path)
            )
        ORDER BY s.path
    ),
    available_sector AS (
        SELECT "as".path
             , "as".label
             , "as".code
             , "as".name
        FROM public.sector AS "as"
        WHERE
            (
                (sector_path IS NULL AND "as".path OPERATOR(public.~) '*{1}'::public.lquery)
            OR
                (sector_path IS NOT NULL AND "as".path OPERATOR(public.~) (sector_path::text || '.*{1}')::public.lquery)
            )
        ORDER BY "as".path
    ), aggregated_sector_counts AS (
        SELECT "as".path
             , "as".label
             , "as".code
             , "as".name
             , COALESCE(SUM(suf.count), 0) AS count
             , public.jsonb_stats_merge_agg(suf.stats_summary) AS stats_summary
             , COALESCE(bool_or(true) FILTER (WHERE suf.sector_path OPERATOR(public.<>) "as".path), false) AS has_children
        FROM available_sector AS "as"
        LEFT JOIN available_facet AS suf ON suf.sector_path OPERATOR(public.<@) "as".path
        GROUP BY "as".path
               , "as".label
               , "as".code
               , "as".name
        ORDER BY "as".path
    ),
    breadcrumb_status AS (
        SELECT s.id
             , s.code
             , s.name
        FROM public.status AS s
        WHERE
            (   status_id IS NOT NULL
            AND s.id = status_id
            )
        ORDER BY s.id
    ),
    available_status AS (
        SELECT s.id
             , s.code
             , s.name
             , s.priority
        FROM public.status AS s
        -- Every status is available, unless one is selected.
        WHERE status_id IS NULL
        ORDER BY s.priority
    ),
    aggregated_status_counts AS (
        SELECT s.id
             , s.code
             , s.name
             , COALESCE(SUM(suf.count), 0) AS count
             , public.jsonb_stats_merge_agg(suf.stats_summary) AS stats_summary
             , false AS has_children
        FROM available_status AS s
        LEFT JOIN available_facet AS suf ON suf.status_id = s.id
        GROUP BY s.id
               , s.code
               , s.name
               , s.priority
        ORDER BY s.priority
    ),
    breadcrumb_legal_form AS (
        SELECT lf.id
             , lf.code
             , lf.name
        FROM public.legal_form AS lf
        WHERE
            (   legal_form_id IS NOT NULL
            AND lf.id = legal_form_id
            )
        ORDER BY lf.id
    ),
    available_legal_form AS (
        SELECT lf.id
             , lf.code
             , lf.name
        FROM public.legal_form AS lf
        -- Every sector is available, unless one is selected.
        WHERE legal_form_id IS NULL
        ORDER BY lf.name
    ), aggregated_legal_form_counts AS (
        SELECT lf.id
             , lf.code
             , lf.name
             , COALESCE(SUM(suf.count), 0) AS count
             , public.jsonb_stats_merge_agg(suf.stats_summary) AS stats_summary
             , false AS has_children
        FROM available_legal_form AS lf
        LEFT JOIN available_facet AS suf ON suf.legal_form_id = lf.id
        GROUP BY lf.id
               , lf.code
               , lf.name
        ORDER BY lf.name
    ),
    breadcrumb_physical_country AS (
        SELECT pc.id
             , pc.iso_2
             , pc.name
        FROM public.country AS pc
        WHERE
            (   country_id IS NOT NULL
            AND pc.id = country_id
            )
        ORDER BY pc.iso_2
    ),
    available_physical_country AS (
        SELECT pc.id
             , pc.iso_2
             , pc.name
        FROM public.country AS pc
        -- Every country is available, unless one is selected.
        WHERE country_id IS NULL
        ORDER BY pc.name
    ), aggregated_physical_country_counts AS (
        SELECT pc.id
             , pc.iso_2
             , pc.name
             , COALESCE(SUM(suf.count), 0) AS count
             , public.jsonb_stats_merge_agg(suf.stats_summary) AS stats_summary
             , false AS has_children
        FROM available_physical_country AS pc
        LEFT JOIN available_facet AS suf ON suf.physical_country_id = pc.id
        GROUP BY pc.id
               , pc.iso_2
               , pc.name
        ORDER BY pc.name
    )
    SELECT
        jsonb_build_object(
          'unit_type', unit_type,
          'stats', (SELECT to_jsonb(source.*) FROM available_facet_stats AS source),
          'breadcrumb',jsonb_build_object(
            'region', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_region AS source),
            'activity_category', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_activity_category AS source),
            'sector', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_sector AS source),
            'status', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_status AS source),
            'legal_form', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_legal_form AS source),
            'country', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_physical_country AS source)
          ),
          'available',jsonb_build_object(
            'region', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_region_counts AS source WHERE count > 0),
            'activity_category', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_activity_counts AS source WHERE count > 0),
            'sector', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_sector_counts AS source WHERE count > 0),
            'status', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_status_counts AS source WHERE count > 0),
            'legal_form', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_legal_form_counts AS source WHERE count > 0),
            'country', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_physical_country_counts AS source WHERE count > 0)
          ),
          'filter',jsonb_build_object(
            'unit_type',param_unit_type,
            'region_path',param_region_path,
            'activity_category_path',param_activity_category_path,
            'sector_path',param_sector_path,
            'status_id',param_status_id,
            'legal_form_id',param_legal_form_id,
            'country_id',param_country_id,
            'valid_on',param_valid_on
          )
        )
    FROM params;
$function$;


-- 10. Replace statistical_history_drilldown function
CREATE OR REPLACE FUNCTION public.statistical_history_drilldown(unit_type statistical_unit_type DEFAULT 'enterprise'::statistical_unit_type, resolution history_resolution DEFAULT 'year'::history_resolution, year integer DEFAULT NULL::integer, region_path ltree DEFAULT NULL::ltree, activity_category_path ltree DEFAULT NULL::ltree, sector_path ltree DEFAULT NULL::ltree, status_id integer DEFAULT NULL::integer, legal_form_id integer DEFAULT NULL::integer, country_id integer DEFAULT NULL::integer, year_min integer DEFAULT NULL::integer, year_max integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
AS $function$
    -- Use a params intermediary to avoid conflicts
    -- between columns and parameters, leading to tautologies. i.e. 'sh.resolution = resolution' is always true.
    WITH params AS (
        SELECT
            unit_type AS param_unit_type,
            resolution AS param_resolution,
            year AS param_year,
            region_path AS param_region_path,
            activity_category_path AS param_activity_category_path,
            sector_path AS param_sector_path,
            legal_form_id AS param_legal_form_id,
            status_id AS param_status_id,
            country_id AS param_country_id
    ), settings_activity_category_standard AS (
        SELECT activity_category_standard_id AS id FROM public.settings
    ),
    available_history AS (
        SELECT sh.*
        FROM public.statistical_history_facet AS sh
           , params
        WHERE (param_unit_type IS NULL OR sh.unit_type = param_unit_type)
          AND (param_resolution IS NULL OR sh.resolution = param_resolution)
          AND (param_year IS NULL OR sh.year = param_year)
          AND (
              param_region_path IS NULL
              OR sh.physical_region_path IS NOT NULL AND sh.physical_region_path OPERATOR(public.<@) param_region_path
              )
          AND (
              param_activity_category_path IS NULL
              OR sh.primary_activity_category_path IS NOT NULL AND sh.primary_activity_category_path OPERATOR(public.<@) param_activity_category_path
              )
          AND (
              param_sector_path IS NULL
              OR sh.sector_path IS NOT NULL AND sh.sector_path OPERATOR(public.<@) param_sector_path
              )
          AND (
              param_legal_form_id IS NULL
              OR sh.legal_form_id IS NOT NULL AND sh.legal_form_id = param_legal_form_id
              )
          AND (
              param_status_id IS NULL
              OR sh.status_id IS NOT NULL AND sh.status_id = param_status_id
              )
          AND (
              param_country_id IS NULL
              OR sh.physical_country_id IS NOT NULL AND sh.physical_country_id = param_country_id
              )
          AND (
              statistical_history_drilldown.year_min IS NULL
              OR sh.year IS NOT NULL AND sh.year >= statistical_history_drilldown.year_min
              )
          AND (
              statistical_history_drilldown.year_max IS NULL
              OR sh.year IS NOT NULL AND sh.year <= statistical_history_drilldown.year_max
              )
    ), available_history_stats AS (
        SELECT
            ah.year, ah.month
            -- Sum up all the demographic and change counts across the filtered facets
            , COALESCE(SUM(ah.exists_count), 0)::integer AS exists_count
            , COALESCE(SUM(ah.exists_change), 0)::integer AS exists_change
            , COALESCE(SUM(ah.exists_added_count), 0)::integer AS exists_added_count
            , COALESCE(SUM(ah.exists_removed_count), 0)::integer AS exists_removed_count
            , COALESCE(SUM(ah.countable_count), 0)::integer AS countable_count
            , COALESCE(SUM(ah.countable_change), 0)::integer AS countable_change
            , COALESCE(SUM(ah.countable_added_count), 0)::integer AS countable_added_count
            , COALESCE(SUM(ah.countable_removed_count), 0)::integer AS countable_removed_count
            , COALESCE(SUM(ah.births), 0)::integer AS births
            , COALESCE(SUM(ah.deaths), 0)::integer AS deaths
            , COALESCE(SUM(ah.name_change_count), 0)::integer AS name_change_count
            , COALESCE(SUM(ah.primary_activity_category_change_count), 0)::integer AS primary_activity_category_change_count
            , COALESCE(SUM(ah.secondary_activity_category_change_count), 0)::integer AS secondary_activity_category_change_count
            , COALESCE(SUM(ah.sector_change_count), 0)::integer AS sector_change_count
            , COALESCE(SUM(ah.legal_form_change_count), 0)::integer AS legal_form_change_count
            , COALESCE(SUM(ah.physical_region_change_count), 0)::integer AS physical_region_change_count
            , COALESCE(SUM(ah.physical_country_change_count), 0)::integer AS physical_country_change_count
            , COALESCE(SUM(ah.physical_address_change_count), 0)::integer AS physical_address_change_count
            , COALESCE(SUM(ah.unit_size_change_count), 0)::integer AS unit_size_change_count
            , COALESCE(SUM(ah.status_change_count), 0)::integer AS status_change_count
            , COALESCE(public.jsonb_stats_merge_agg(ah.stats_summary), '{}'::jsonb) AS stats_summary
        FROM available_history AS ah
        GROUP BY ah.year, ah.month
        ORDER BY year ASC, month ASC NULLS FIRST
    ),
    breadcrumb_region AS (
        SELECT r.path
             , r.label
             , r.code
             , r.name
        FROM public.region AS r
        WHERE
            (   region_path IS NOT NULL
            AND r.path OPERATOR(public.@>) (region_path)
            )
        ORDER BY path
    ),
    available_region AS (
        SELECT r.path
             , r.label
             , r.code
             , r.name
        FROM public.region AS r
        WHERE
            (
                (region_path IS NULL AND r.path OPERATOR(public.~) '*{1}'::public.lquery)
            OR
                (region_path IS NOT NULL AND r.path OPERATOR(public.~) (region_path::text || '.*{1}')::public.lquery)
            )
        ORDER BY r.path
    ), aggregated_region_counts AS (
        SELECT ar.path
             , ar.label
             , ar.code
             , ar.name
             , COALESCE(SUM(sh.countable_count), 0) AS count
             , COALESCE(bool_or(true) FILTER (WHERE sh.physical_region_path OPERATOR(public.<>) ar.path), false) AS has_children
        FROM available_region AS ar
        LEFT JOIN available_history AS sh ON sh.physical_region_path OPERATOR(public.<@) ar.path
        GROUP BY ar.path
               , ar.label
               , ar.code
               , ar.name
    ),
    breadcrumb_activity_category AS (
        SELECT ac.path
             , ac.label
             , ac.code
             , ac.name
        FROM
            public.activity_category AS ac
        WHERE ac.enabled
           AND ac.standard_id = (SELECT id FROM settings_activity_category_standard)
           AND
            (     activity_category_path IS NOT NULL
              AND ac.path OPERATOR(public.@>) activity_category_path
            )
        ORDER BY path
    ),
    available_activity_category AS (
        SELECT ac.path
             , ac.label
             , ac.code
             , ac.name
        FROM
            public.activity_category AS ac
        WHERE ac.enabled
           AND ac.standard_id = (SELECT id FROM settings_activity_category_standard)
           AND
            (
                (activity_category_path IS NULL AND ac.path OPERATOR(public.~) '*{1}'::public.lquery)
            OR
                (activity_category_path IS NOT NULL AND ac.path OPERATOR(public.~) (activity_category_path::text || '.*{1}')::public.lquery)
            )
        ORDER BY ac.path
    ),
    aggregated_activity_counts AS (
        SELECT aac.path
             , aac.label
             , aac.code
             , aac.name
             , COALESCE(SUM(sh.countable_count), 0) AS count
             , COALESCE(bool_or(true) FILTER (WHERE sh.primary_activity_category_path OPERATOR(public.<>) aac.path), false) AS has_children
        FROM
            available_activity_category AS aac
        LEFT JOIN available_history AS sh ON sh.primary_activity_category_path OPERATOR(public.<@) aac.path
        GROUP BY aac.path
               , aac.label
               , aac.code
               , aac.name
        ORDER BY aac.path
    ),
    breadcrumb_sector AS (
        SELECT s.path
             , s.label
             , s.code
             , s.name
        FROM public.sector AS s
        WHERE
            (   sector_path IS NOT NULL
            AND s.path OPERATOR(public.@>) (sector_path)
            )
        ORDER BY s.path
    ),
    available_sector AS (
        SELECT "as".path
             , "as".label
             , "as".code
             , "as".name
        FROM public.sector AS "as"
        WHERE
            (
                (sector_path IS NULL AND "as".path OPERATOR(public.~) '*{1}'::public.lquery)
            OR
                (sector_path IS NOT NULL AND "as".path OPERATOR(public.~) (sector_path::text || '.*{1}')::public.lquery)
            )
        ORDER BY "as".path
    ), aggregated_sector_counts AS (
        SELECT "as".path
             , "as".label
             , "as".code
             , "as".name
             , COALESCE(SUM(sh.countable_count), 0) AS count
             , COALESCE(bool_or(true) FILTER (WHERE sh.sector_path OPERATOR(public.<>) "as".path), false) AS has_children
        FROM available_sector AS "as"
        LEFT JOIN available_history AS sh ON sh.sector_path OPERATOR(public.<@) "as".path
        GROUP BY "as".path
               , "as".label
               , "as".code
               , "as".name
       ORDER BY "as".path
    ),
    breadcrumb_legal_form AS (
        SELECT lf.id
             , lf.code
             , lf.name
        FROM public.legal_form AS lf
        WHERE
            (   legal_form_id IS NOT NULL
            AND lf.id = legal_form_id
            )
        ORDER BY lf.code
    ),
    available_legal_form AS (
        SELECT lf.id
             , lf.code
             , lf.name
        FROM public.legal_form AS lf
        -- Every sector is available, unless one is selected.
        WHERE legal_form_id IS NULL
        ORDER BY lf.code
    ), aggregated_legal_form_counts AS (
        SELECT lf.id
             , lf.code
             , lf.name
             , COALESCE(SUM(sh.countable_count), 0) AS count
             , false AS has_children
        FROM available_legal_form AS lf
        LEFT JOIN available_history AS sh ON sh.legal_form_id = lf.id
        GROUP BY lf.id
               , lf.code
               , lf.name
        ORDER BY lf.code
    ),
    breadcrumb_status AS (
        SELECT s.id
             , s.code
             , s.name
        FROM public.status AS s
        WHERE
            (   status_id IS NOT NULL
            AND s.id = status_id
            )
        ORDER BY s.code
    ),
    available_status AS (
        SELECT s.id
             , s.code
             , s.name
        FROM public.status AS s
        -- Every status is available, unless one is selected.
        WHERE status_id IS NULL
        ORDER BY s.code
    ), aggregated_status_counts AS (
        SELECT s.id
             , s.code
             , s.name
             , COALESCE(SUM(sh.countable_count), 0) AS count
             , false AS has_children
        FROM available_status AS s
        LEFT JOIN available_history AS sh ON sh.status_id = s.id
        GROUP BY s.id
               , s.code
               , s.name
        ORDER BY s.code
    ),
    breadcrumb_physical_country AS (
        SELECT pc.id
             , pc.iso_2
             , pc.name
        FROM public.country AS pc
        WHERE
            (   country_id IS NOT NULL
            AND pc.id = country_id
            )
        ORDER BY pc.iso_2
    ),
    available_physical_country AS (
        SELECT pc.id
             , pc.iso_2
             , pc.name
        FROM public.country AS pc
        -- Every country is available, unless one is selected.
        WHERE country_id IS NULL
        ORDER BY pc.iso_2
    ), aggregated_physical_country_counts AS (
        SELECT pc.id
             , pc.iso_2
             , pc.name
             , COALESCE(SUM(sh.countable_count), 0) AS count
             , false AS has_children
        FROM available_physical_country AS pc
        LEFT JOIN available_history AS sh ON sh.physical_country_id = pc.id
        GROUP BY pc.id
               , pc.iso_2
               , pc.name
        ORDER BY pc.iso_2
    )
    SELECT
        jsonb_build_object(
          'unit_type', unit_type,
          'stats', (SELECT jsonb_agg(to_jsonb(source.*)) FROM available_history_stats AS source),
          'breadcrumb',jsonb_build_object(
            'region', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_region AS source),
            'activity_category', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_activity_category AS source),
            'sector', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_sector AS source),
            'legal_form', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_legal_form AS source),
            'status', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_status AS source),
            'country', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_physical_country AS source)
          ),
          'available',jsonb_build_object(
            'region', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_region_counts AS source WHERE count > 0),
            'activity_category', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_activity_counts AS source WHERE count > 0),
            'sector', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_sector_counts AS source WHERE count > 0),
            'legal_form', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_legal_form_counts AS source WHERE count > 0),
            'status', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_status_counts AS source WHERE count > 0),
            'country', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_physical_country_counts AS source WHERE count > 0)
          ),
          'filter',jsonb_build_object(
            'type',param_resolution,
            'year',param_year,
            'unit_type',param_unit_type,
            'region_path',param_region_path,
            'activity_category_path',param_activity_category_path,
            'sector_path',param_sector_path,
            'legal_form_id',param_legal_form_id,
            'status_id',param_status_id,
            'country_id',param_country_id
          )
        )
    FROM params;
$function$;


-- 11. Replace statistical_unit_facet_def view
CREATE OR REPLACE VIEW public.statistical_unit_facet_def
 WITH (security_invoker='on') AS
 SELECT valid_from,
    valid_to,
    valid_until,
    unit_type,
    physical_region_path,
    primary_activity_category_path,
    sector_path,
    legal_form_id,
    physical_country_id,
    status_id,
    count(*) AS count,
    jsonb_stats_merge_agg(stats_summary) AS stats_summary
   FROM statistical_unit
  WHERE used_for_counting
  GROUP BY valid_from, valid_to, valid_until, unit_type, physical_region_path, primary_activity_category_path, sector_path, legal_form_id, physical_country_id, status_id;

-- 12. Replace worker.statistical_history_reduce (references jsonb_stats_summary_merge_agg)
CREATE OR REPLACE PROCEDURE worker.statistical_history_reduce(IN payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
BEGIN
    RAISE DEBUG 'statistical_history_reduce: valid_from=%, valid_until=%', v_valid_from, v_valid_until;

    -- Delete existing root entries
    DELETE FROM public.statistical_history WHERE partition_seq IS NULL;

    -- Recalculate root entries by summing across all partition entries
    INSERT INTO public.statistical_history (
        resolution, year, month, unit_type,
        exists_count, exists_change, exists_added_count, exists_removed_count,
        countable_count, countable_change, countable_added_count, countable_removed_count,
        births, deaths,
        name_change_count, primary_activity_category_change_count,
        secondary_activity_category_change_count, sector_change_count,
        legal_form_change_count, physical_region_change_count,
        physical_country_change_count, physical_address_change_count,
        stats_summary,
        partition_seq
    )
    SELECT
        resolution, year, month, unit_type,
        SUM(exists_count)::integer,
        SUM(exists_change)::integer,
        SUM(exists_added_count)::integer,
        SUM(exists_removed_count)::integer,
        SUM(countable_count)::integer,
        SUM(countable_change)::integer,
        SUM(countable_added_count)::integer,
        SUM(countable_removed_count)::integer,
        SUM(births)::integer,
        SUM(deaths)::integer,
        SUM(name_change_count)::integer,
        SUM(primary_activity_category_change_count)::integer,
        SUM(secondary_activity_category_change_count)::integer,
        SUM(sector_change_count)::integer,
        SUM(legal_form_change_count)::integer,
        SUM(physical_region_change_count)::integer,
        SUM(physical_country_change_count)::integer,
        SUM(physical_address_change_count)::integer,
        jsonb_stats_merge_agg(stats_summary),
        NULL  -- partition_seq = NULL = root entry
    FROM public.statistical_history
    WHERE partition_seq IS NOT NULL
    GROUP BY resolution, year, month, unit_type;

    -- Enqueue next phase: derive_statistical_unit_facet
    PERFORM worker.enqueue_derive_statistical_unit_facet(
        p_valid_from => v_valid_from,
        p_valid_until => v_valid_until
    );

    RAISE DEBUG 'statistical_history_reduce: done, enqueued derive_statistical_unit_facet';
END;
$procedure$;

-- 12b. Replace worker.derive_statistical_unit_facet_partition
CREATE OR REPLACE PROCEDURE worker.derive_statistical_unit_facet_partition(IN payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_partition_seq INT := (payload->>'partition_seq')::int;
BEGIN
    RAISE DEBUG 'derive_statistical_unit_facet_partition: partition_seq=%', v_partition_seq;

    -- Delete existing rows for this logical partition (indexed by partition_seq)
    DELETE FROM public.statistical_unit_facet_staging
    WHERE partition_seq = v_partition_seq;

    -- Recompute facets for this partition's units
    INSERT INTO public.statistical_unit_facet_staging
    SELECT v_partition_seq,
           su.valid_from, su.valid_to, su.valid_until, su.unit_type,
           su.physical_region_path, su.primary_activity_category_path,
           su.sector_path, su.legal_form_id, su.physical_country_id, su.status_id,
           COUNT(*)::INT,
           jsonb_stats_merge_agg(su.stats_summary)
    FROM public.statistical_unit AS su
    WHERE su.used_for_counting
      AND su.report_partition_seq = v_partition_seq
    GROUP BY su.valid_from, su.valid_to, su.valid_until, su.unit_type,
             su.physical_region_path, su.primary_activity_category_path,
             su.sector_path, su.legal_form_id, su.physical_country_id, su.status_id;

    RAISE DEBUG 'derive_statistical_unit_facet_partition: partition_seq=% done', v_partition_seq;
END;
$procedure$;

-- 12c. Replace worker.statistical_unit_facet_reduce
CREATE OR REPLACE PROCEDURE worker.statistical_unit_facet_reduce(IN payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
    v_dirty_partitions INT[];
BEGIN
    RAISE DEBUG 'statistical_unit_facet_reduce: valid_from=%, valid_until=%', v_valid_from, v_valid_until;

    -- Extract dirty partitions from payload (NULL = full refresh)
    IF payload->'dirty_partitions' IS NOT NULL AND payload->'dirty_partitions' != 'null'::jsonb THEN
        SELECT array_agg(val::int)
        INTO v_dirty_partitions
        FROM jsonb_array_elements_text(payload->'dirty_partitions') AS val;
    END IF;

    -- TRUNCATE is instant (no dead tuples, no per-row WAL), unlike DELETE which
    -- accumulates dead tuples per cycle causing progressive slowdown.
    TRUNCATE public.statistical_unit_facet;

    -- Aggregate from UNLOGGED staging table into main table
    INSERT INTO public.statistical_unit_facet
    SELECT sufp.valid_from, sufp.valid_to, sufp.valid_until, sufp.unit_type,
           sufp.physical_region_path, sufp.primary_activity_category_path,
           sufp.sector_path, sufp.legal_form_id, sufp.physical_country_id, sufp.status_id,
           SUM(sufp.count)::BIGINT,
           jsonb_stats_merge_agg(sufp.stats_summary)
    FROM public.statistical_unit_facet_staging AS sufp
    GROUP BY sufp.valid_from, sufp.valid_to, sufp.valid_until, sufp.unit_type,
             sufp.physical_region_path, sufp.primary_activity_category_path,
             sufp.sector_path, sufp.legal_form_id, sufp.physical_country_id, sufp.status_id;

    -- Clear only the dirty partitions that were processed
    IF v_dirty_partitions IS NOT NULL THEN
        DELETE FROM public.statistical_unit_facet_dirty_partitions
        WHERE partition_seq = ANY(v_dirty_partitions);
        RAISE DEBUG 'statistical_unit_facet_reduce: cleared % dirty partitions', array_length(v_dirty_partitions, 1);
    ELSE
        TRUNCATE public.statistical_unit_facet_dirty_partitions;
        RAISE DEBUG 'statistical_unit_facet_reduce: full refresh — truncated dirty partitions';
    END IF;

    -- Enqueue next phase: derive_statistical_history_facet
    PERFORM worker.enqueue_derive_statistical_history_facet(
        p_valid_from => v_valid_from,
        p_valid_until => v_valid_until
    );

    RAISE DEBUG 'statistical_unit_facet_reduce: done, enqueued derive_statistical_history_facet';
END;
$procedure$;

-- 12d. Replace worker.statistical_history_facet_reduce
CREATE OR REPLACE PROCEDURE worker.statistical_history_facet_reduce(IN payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
BEGIN
    RAISE DEBUG 'statistical_history_facet_reduce: valid_from=%, valid_until=%', v_valid_from, v_valid_until;

    -- TRUNCATE is instant (no dead tuples, no per-row WAL), unlike DELETE which
    -- accumulates ~800K dead tuples per cycle causing progressive slowdown.
    TRUNCATE public.statistical_history_facet;

    -- Aggregate from UNLOGGED partition table into main LOGGED table
    INSERT INTO public.statistical_history_facet (
        resolution, year, month, unit_type,
        primary_activity_category_path, secondary_activity_category_path,
        sector_path, legal_form_id, physical_region_path,
        physical_country_id, unit_size_id, status_id,
        exists_count, exists_change, exists_added_count, exists_removed_count,
        countable_count, countable_change, countable_added_count, countable_removed_count,
        births, deaths,
        name_change_count, primary_activity_category_change_count,
        secondary_activity_category_change_count, sector_change_count,
        legal_form_change_count, physical_region_change_count,
        physical_country_change_count, physical_address_change_count,
        unit_size_change_count, status_change_count,
        stats_summary
    )
    SELECT
        resolution, year, month, unit_type,
        primary_activity_category_path, secondary_activity_category_path,
        sector_path, legal_form_id, physical_region_path,
        physical_country_id, unit_size_id, status_id,
        SUM(exists_count)::integer, SUM(exists_change)::integer,
        SUM(exists_added_count)::integer, SUM(exists_removed_count)::integer,
        SUM(countable_count)::integer, SUM(countable_change)::integer,
        SUM(countable_added_count)::integer, SUM(countable_removed_count)::integer,
        SUM(births)::integer, SUM(deaths)::integer,
        SUM(name_change_count)::integer, SUM(primary_activity_category_change_count)::integer,
        SUM(secondary_activity_category_change_count)::integer, SUM(sector_change_count)::integer,
        SUM(legal_form_change_count)::integer, SUM(physical_region_change_count)::integer,
        SUM(physical_country_change_count)::integer, SUM(physical_address_change_count)::integer,
        SUM(unit_size_change_count)::integer, SUM(status_change_count)::integer,
        jsonb_stats_merge_agg(stats_summary)
    FROM public.statistical_history_facet_partitions
    GROUP BY resolution, year, month, unit_type,
             primary_activity_category_path, secondary_activity_category_path,
             sector_path, legal_form_id, physical_region_path,
             physical_country_id, unit_size_id, status_id;

    RAISE DEBUG 'statistical_history_facet_reduce: done';
END;
$procedure$;

-- 13. Restore security_invoker on views (CREATE OR REPLACE VIEW resets reloptions)
ALTER VIEW public.timeline_establishment_def SET (security_invoker = on);
ALTER VIEW public.timeline_legal_unit_def SET (security_invoker = on);
ALTER VIEW public.timeline_enterprise_def SET (security_invoker = on);

-- 14. Restore search_path on SECURITY DEFINER functions (CREATE OR REPLACE FUNCTION resets proconfig)
ALTER FUNCTION public.statistical_history_drilldown(statistical_unit_type, history_resolution, integer, ltree, ltree, ltree, integer, integer, integer, integer, integer) SET search_path = public, pg_temp;
ALTER FUNCTION public.statistical_unit_facet_drilldown(statistical_unit_type, ltree, ltree, ltree, integer, integer, integer, date) SET search_path = public, pg_temp;

-- 15. Drop old PL/pgSQL functions (no longer needed)
DROP AGGREGATE IF EXISTS public.jsonb_stats_to_summary_agg(jsonb);
DROP AGGREGATE IF EXISTS public.jsonb_stats_summary_merge_agg(jsonb);
DROP FUNCTION IF EXISTS public.jsonb_stats_to_summary(jsonb, jsonb);
DROP FUNCTION IF EXISTS public.jsonb_stats_to_summary_round(jsonb);
DROP FUNCTION IF EXISTS public.jsonb_stats_summary_merge(jsonb, jsonb);

END;
