```sql
CREATE OR REPLACE PROCEDURE public.timeline_legal_unit_refresh(IN p_unit_id_ranges int4multirange DEFAULT NULL::int4multirange)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_unit_ids INT[];
BEGIN
    IF p_unit_id_ranges IS NULL THEN
        -- Full refresh: ANALYZE and use the generic timeline_refresh procedure
        ANALYZE public.timesegments, public.legal_unit, public.activity, public.location, public.contact, public.stat_for_unit, public.timeline_establishment;
        CALL public.timeline_refresh('timeline_legal_unit', 'legal_unit', p_unit_id_ranges);
    ELSE
        -- Partial refresh: Pre-materialize filtered timeline_establishment to avoid O(n²) scan
        v_unit_ids := public.int4multirange_to_array(p_unit_id_ranges);

        -- Drop staging table if exists from previous run (silent, no NOTICE)
        PERFORM set_config('client_min_messages', 'warning', true);
        DROP TABLE IF EXISTS public.timeline_establishment_filtered;
        PERFORM set_config('client_min_messages', 'notice', true);

        -- Pre-filter timeline_establishment to only rows for these legal units
        -- This is O(m) where m = establishments linked to these legal units
        -- Use UNLOGGED for cross-session visibility (enables concurrency > 1)
        CREATE UNLOGGED TABLE public.timeline_establishment_filtered AS
        SELECT tes.*
        FROM public.timeline_establishment tes
        WHERE tes.legal_unit_id = ANY(v_unit_ids);

        -- Create index on the staging table for the join
        CREATE INDEX ON public.timeline_establishment_filtered (legal_unit_id, valid_from, valid_until);

        -- ANALYZE the staging table for good query plans
        ANALYZE public.timeline_establishment_filtered;

        -- Delete existing rows for these units
        DELETE FROM public.timeline_legal_unit
        WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_unit_ids);

        -- Insert using the pre-filtered temp table instead of full timeline_establishment
        -- This query is identical to timeline_legal_unit_def but references the temp table
        INSERT INTO public.timeline_legal_unit
        WITH legal_unit_stats AS (
            SELECT t.unit_id AS src_unit_id,
               t.valid_from AS src_valid_from,
               jsonb_object_agg(sd.code,
                   CASE
                       WHEN sfu.value_float IS NOT NULL THEN to_jsonb(sfu.value_float)
                       WHEN sfu.value_int IS NOT NULL THEN to_jsonb(sfu.value_int)
                       WHEN sfu.value_string IS NOT NULL THEN to_jsonb(sfu.value_string)
                       WHEN sfu.value_bool IS NOT NULL THEN to_jsonb(sfu.value_bool)
                       ELSE NULL::jsonb
                   END) FILTER (WHERE sd.code IS NOT NULL) AS stats
              FROM public.timesegments t
                JOIN public.stat_for_unit sfu ON sfu.legal_unit_id = t.unit_id AND public.from_until_overlaps(t.valid_from, t.valid_until, sfu.valid_from, sfu.valid_until)
                JOIN public.stat_definition sd ON sfu.stat_definition_id = sd.id
             WHERE t.unit_type = 'legal_unit'::public.statistical_unit_type
               AND t.unit_id = ANY(v_unit_ids)
             GROUP BY t.unit_id, t.valid_from
        ), basis AS (
            SELECT t.unit_type AS src_unit_type,
               t.unit_id AS src_unit_id,
               t.valid_from AS src_valid_from,
               (t.valid_until - '1 day'::interval)::date AS src_valid_to,
               t.valid_until AS src_valid_until,
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
               NULLIF(array_remove(ARRAY[pac.path, sac.path], NULL::public.ltree), '{}'::public.ltree[]) AS activity_category_paths,
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
               public.jsonb_stats_to_summary('{}'::jsonb, COALESCE(lu_stats.stats, '{}'::jsonb)) AS stats_summary
              FROM public.timesegments t
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
                      FROM public.legal_unit lu_1
                     WHERE lu_1.id = t.unit_id AND public.from_until_overlaps(t.valid_from, t.valid_until, lu_1.valid_from, lu_1.valid_until)
                     ORDER BY lu_1.id DESC, lu_1.valid_from DESC
                    LIMIT 1) lu ON true
                LEFT JOIN legal_unit_stats lu_stats ON lu_stats.src_unit_id = t.unit_id AND lu_stats.src_valid_from = t.valid_from
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
                      FROM public.activity a
                     WHERE a.legal_unit_id = lu.id AND a.type = 'primary'::public.activity_type AND public.from_until_overlaps(t.valid_from, t.valid_until, a.valid_from, a.valid_until)
                     ORDER BY a.id DESC
                    LIMIT 1) pa ON true
                LEFT JOIN public.activity_category pac ON pa.category_id = pac.id
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
                      FROM public.activity a
                     WHERE a.legal_unit_id = lu.id AND a.type = 'secondary'::public.activity_type AND public.from_until_overlaps(t.valid_from, t.valid_until, a.valid_from, a.valid_until)
                     ORDER BY a.id DESC
                    LIMIT 1) sa ON true
                LEFT JOIN public.activity_category sac ON sa.category_id = sac.id
                LEFT JOIN public.sector s ON lu.sector_id = s.id
                LEFT JOIN public.legal_form lf ON lu.legal_form_id = lf.id
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
                      FROM public.location l
                     WHERE l.legal_unit_id = lu.id AND l.type = 'physical'::public.location_type AND public.from_until_overlaps(t.valid_from, t.valid_until, l.valid_from, l.valid_until)
                     ORDER BY l.id DESC
                    LIMIT 1) phl ON true
                LEFT JOIN public.region phr ON phl.region_id = phr.id
                LEFT JOIN public.country phc ON phl.country_id = phc.id
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
                      FROM public.location l
                     WHERE l.legal_unit_id = lu.id AND l.type = 'postal'::public.location_type AND public.from_until_overlaps(t.valid_from, t.valid_until, l.valid_from, l.valid_until)
                     ORDER BY l.id DESC
                    LIMIT 1) pol ON true
                LEFT JOIN public.region por ON pol.region_id = por.id
                LEFT JOIN public.country poc ON pol.country_id = poc.id
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
                      FROM public.contact c_1
                     WHERE c_1.legal_unit_id = lu.id AND public.from_until_overlaps(t.valid_from, t.valid_until, c_1.valid_from, c_1.valid_until)
                     ORDER BY c_1.id DESC
                    LIMIT 1) c ON true
                LEFT JOIN public.unit_size us ON lu.unit_size_id = us.id
                LEFT JOIN public.status st ON lu.status_id = st.id
                LEFT JOIN LATERAL ( SELECT array_agg(DISTINCT sfu.data_source_id) FILTER (WHERE sfu.data_source_id IS NOT NULL) AS data_source_ids
                      FROM public.stat_for_unit sfu
                     WHERE sfu.legal_unit_id = lu.id AND public.from_until_overlaps(t.valid_from, t.valid_until, sfu.valid_from, sfu.valid_until)) sfu_ds ON true
                LEFT JOIN LATERAL ( SELECT sfu.edit_comment,
                       sfu.edit_by_user_id,
                       sfu.edit_at
                      FROM public.stat_for_unit sfu
                     WHERE sfu.legal_unit_id = lu.id AND public.from_until_overlaps(t.valid_from, t.valid_until, sfu.valid_from, sfu.valid_until)
                     ORDER BY sfu.edit_at DESC
                    LIMIT 1) sfu_le ON true
                LEFT JOIN LATERAL ( SELECT array_agg(ds_1.id) AS ids,
                       array_agg(ds_1.code) AS codes
                      FROM public.data_source ds_1
                     WHERE COALESCE(ds_1.id = lu.data_source_id, false) OR COALESCE(ds_1.id = pa.data_source_id, false) OR COALESCE(ds_1.id = sa.data_source_id, false) OR COALESCE(ds_1.id = phl.data_source_id, false) OR COALESCE(ds_1.id = pol.data_source_id, false) OR COALESCE(ds_1.id = ANY (sfu_ds.data_source_ids), false)) ds ON true
                LEFT JOIN LATERAL ( SELECT all_edits.edit_comment,
                       all_edits.edit_by_user_id,
                       all_edits.edit_at
                      FROM ( VALUES (lu.edit_comment,lu.edit_by_user_id,lu.edit_at), (pa.edit_comment,pa.edit_by_user_id,pa.edit_at), (sa.edit_comment,sa.edit_by_user_id,sa.edit_at), (phl.edit_comment,phl.edit_by_user_id,phl.edit_at), (pol.edit_comment,pol.edit_by_user_id,pol.edit_at), (c.edit_comment,c.edit_by_user_id,c.edit_at), (sfu_le.edit_comment,sfu_le.edit_by_user_id,sfu_le.edit_at)) all_edits(edit_comment, edit_by_user_id, edit_at)
                     WHERE all_edits.edit_at IS NOT NULL
                     ORDER BY all_edits.edit_at DESC
                    LIMIT 1) last_edit ON true,
               public.settings current_settings
             WHERE t.unit_type = 'legal_unit'::public.statistical_unit_type
               AND t.unit_id = ANY(v_unit_ids)
        )
        SELECT basis.src_unit_type,
           basis.src_unit_id,
           basis.src_valid_from,
           basis.src_valid_to,
           basis.src_valid_until,
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
           ARRAY[basis.src_unit_id] AS related_legal_unit_ids,
           ARRAY[]::integer[] AS excluded_legal_unit_ids,
               CASE
                   WHEN basis.used_for_counting THEN ARRAY[basis.src_unit_id]
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
                   WHEN basis.used_for_counting THEN COALESCE(public.jsonb_stats_summary_merge(esa.stats_summary, basis.stats_summary), basis.stats_summary, esa.stats_summary, '{}'::jsonb)
                   ELSE '{}'::jsonb
               END AS stats_summary
          FROM basis
            -- CRITICAL FIX: Join against pre-filtered temp table instead of full timeline_establishment
            -- This eliminates the O(n²) GIST scan that was scanning 600K+ rows per iteration
            LEFT JOIN LATERAL ( SELECT tes.legal_unit_id,
                   public.array_distinct_concat(tes.data_source_ids) AS data_source_ids,
                   public.array_distinct_concat(tes.data_source_codes) AS data_source_codes,
                   array_agg(DISTINCT tes.establishment_id) FILTER (WHERE tes.establishment_id IS NOT NULL) AS related_establishment_ids,
                   array_agg(DISTINCT tes.establishment_id) FILTER (WHERE tes.establishment_id IS NOT NULL AND NOT tes.used_for_counting) AS excluded_establishment_ids,
                   array_agg(DISTINCT tes.establishment_id) FILTER (WHERE tes.establishment_id IS NOT NULL AND tes.used_for_counting) AS included_establishment_ids,
                   public.jsonb_stats_summary_merge_agg(tes.stats_summary) FILTER (WHERE tes.used_for_counting) AS stats_summary
                  FROM public.timeline_establishment_filtered tes
                 WHERE tes.legal_unit_id = basis.legal_unit_id
                   AND public.from_until_overlaps(basis.src_valid_from, basis.src_valid_until, tes.valid_from, tes.valid_until)
                 GROUP BY tes.legal_unit_id) esa ON true
         ORDER BY basis.src_unit_type, basis.src_unit_id, basis.src_valid_from;

        -- Clean up temp table (use to_regclass to avoid NOTICE)
        -- Clean up staging table (silent, no NOTICE)
        PERFORM set_config('client_min_messages', 'warning', true);
        DROP TABLE IF EXISTS public.timeline_establishment_filtered;
        PERFORM set_config('client_min_messages', 'notice', true);
    END IF;
END;
$procedure$
```
