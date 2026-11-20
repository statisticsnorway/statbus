-- Down Migration 20261120122232: legal units and establishments have no short name
BEGIN;

ALTER TABLE public.legal_unit ADD COLUMN short_name character varying(16);
ALTER TABLE public.establishment ADD COLUMN short_name character varying(16);

CREATE OR REPLACE FUNCTION public.timeline_legal_unit_def_for(p_unit_ids integer[])
 RETURNS SETOF timeline_legal_unit
 LANGUAGE sql
 STABLE
AS $function$
 WITH legal_unit_stats AS (
         SELECT t.unit_id,
            t.valid_from,
            public.jsonb_stats_agg(sd.code::text, sfu.stat) FILTER (WHERE sd.code IS NOT NULL) AS stats
           FROM public.timesegments t
             JOIN public.stat_for_unit sfu ON sfu.legal_unit_id = t.unit_id AND public.from_until_overlaps(t.valid_from, t.valid_until, sfu.valid_from, sfu.valid_until)
             JOIN public.stat_definition sd ON sfu.stat_definition_id = sd.id
          WHERE t.unit_type = 'legal_unit'::public.statistical_unit_type AND (p_unit_ids IS NULL OR t.unit_id = ANY (p_unit_ids))
          GROUP BY t.unit_id, t.valid_from
        ), establishment_aggs AS (
         SELECT t.unit_id,
            t.valid_from,
            public.array_distinct_concat(tes.data_source_ids) AS data_source_ids,
            public.array_distinct_concat(tes.data_source_codes) AS data_source_codes,
            array_agg(DISTINCT tes.establishment_id) FILTER (WHERE tes.establishment_id IS NOT NULL) AS related_establishment_ids,
            array_agg(DISTINCT tes.establishment_id) FILTER (WHERE tes.establishment_id IS NOT NULL AND NOT tes.used_for_counting) AS excluded_establishment_ids,
            array_agg(DISTINCT tes.establishment_id) FILTER (WHERE tes.establishment_id IS NOT NULL AND tes.used_for_counting) AS included_establishment_ids,
            public.jsonb_stats_merge_agg(tes.stats_summary) FILTER (WHERE tes.used_for_counting) AS stats_summary
           FROM public.timesegments t
             JOIN public.timeline_establishment tes ON tes.legal_unit_id = t.unit_id AND public.from_until_overlaps(t.valid_from, t.valid_until, tes.valid_from, tes.valid_until)
          WHERE t.unit_type = 'legal_unit'::public.statistical_unit_type AND (p_unit_ids IS NULL OR t.unit_id = ANY (p_unit_ids))
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
            true AS has_legal_unit,
            lu.id AS legal_unit_id,
            lu.enterprise_id,
            lu.primary_for_enterprise,
            COALESCE(lu_stats.stats, '{}'::jsonb) AS stats,
            public.jsonb_stats_to_agg(COALESCE(lu_stats.stats, '{}'::jsonb)) AS stats_summary
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
                    lu_1.image_id
                   FROM public.legal_unit lu_1
                  WHERE lu_1.id = t.unit_id AND public.from_until_overlaps(t.valid_from, t.valid_until, lu_1.valid_from, lu_1.valid_until)
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
          WHERE t.unit_type = 'legal_unit'::public.statistical_unit_type AND (p_unit_ids IS NULL OR t.unit_id = ANY (p_unit_ids))
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
            WHEN basis.used_for_counting THEN COALESCE(public.jsonb_stats_merge(esa.stats_summary, basis.stats_summary), basis.stats_summary, esa.stats_summary, '{}'::jsonb)
            ELSE '{}'::jsonb
        END AS stats_summary
   FROM basis
     LEFT JOIN establishment_aggs esa ON esa.unit_id = basis.unit_id AND esa.valid_from = basis.valid_from
  ORDER BY basis.unit_type, basis.unit_id, basis.valid_from
$function$
;

CREATE OR REPLACE FUNCTION public.timeline_establishment_def_for(p_unit_ids integer[])
 RETURNS SETOF timeline_establishment
 LANGUAGE sql
 STABLE
AS $function$
 WITH establishment_stats AS (
         SELECT t_1.unit_id,
            t_1.valid_from,
            public.jsonb_stats_agg(sd.code::text, sfu.stat) FILTER (WHERE sd.code IS NOT NULL) AS stats
           FROM public.timesegments t_1
             JOIN public.stat_for_unit sfu ON sfu.establishment_id = t_1.unit_id AND public.from_until_overlaps(t_1.valid_from, t_1.valid_until, sfu.valid_from, sfu.valid_until)
             JOIN public.stat_definition sd ON sfu.stat_definition_id = sd.id
          WHERE t_1.unit_type = 'establishment'::public.statistical_unit_type AND (p_unit_ids IS NULL OR t_1.unit_id = ANY (p_unit_ids))
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
    NULLIF(array_remove(ARRAY[pac.path, sac.path], NULL::public.ltree), '{}'::public.ltree[]) AS activity_category_paths,
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
    public.jsonb_stats_to_agg(COALESCE(es_stats.stats, '{}'::jsonb)) AS stats_summary,
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
   FROM public.timesegments t
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
           FROM public.establishment es_1
          WHERE es_1.id = t.unit_id AND public.from_until_overlaps(t.valid_from, t.valid_until, es_1.valid_from, es_1.valid_until)
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
           FROM public.activity a
          WHERE a.establishment_id = es.id AND a.type = 'primary'::public.activity_type AND public.from_until_overlaps(t.valid_from, t.valid_until, a.valid_from, a.valid_until)
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
          WHERE a.establishment_id = es.id AND a.type = 'secondary'::public.activity_type AND public.from_until_overlaps(t.valid_from, t.valid_until, a.valid_from, a.valid_until)
          ORDER BY a.id DESC
         LIMIT 1) sa ON true
     LEFT JOIN public.activity_category sac ON sa.category_id = sac.id
     LEFT JOIN public.sector s ON es.sector_id = s.id
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
          WHERE l.establishment_id = es.id AND l.type = 'physical'::public.location_type AND public.from_until_overlaps(t.valid_from, t.valid_until, l.valid_from, l.valid_until)
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
          WHERE l.establishment_id = es.id AND l.type = 'postal'::public.location_type AND public.from_until_overlaps(t.valid_from, t.valid_until, l.valid_from, l.valid_until)
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
          WHERE c_1.establishment_id = es.id AND public.from_until_overlaps(t.valid_from, t.valid_until, c_1.valid_from, c_1.valid_until)
          ORDER BY c_1.id DESC
         LIMIT 1) c ON true
     LEFT JOIN public.unit_size us ON es.unit_size_id = us.id
     LEFT JOIN public.status st ON es.status_id = st.id
     LEFT JOIN LATERAL ( SELECT array_agg(DISTINCT sfu.data_source_id) FILTER (WHERE sfu.data_source_id IS NOT NULL) AS data_source_ids
           FROM public.stat_for_unit sfu
          WHERE sfu.establishment_id = es.id AND public.from_until_overlaps(t.valid_from, t.valid_until, sfu.valid_from, sfu.valid_until)) sfu_ds ON true
     LEFT JOIN LATERAL ( SELECT sfu.edit_comment,
            sfu.edit_by_user_id,
            sfu.edit_at
           FROM public.stat_for_unit sfu
          WHERE sfu.establishment_id = es.id AND public.from_until_overlaps(t.valid_from, t.valid_until, sfu.valid_from, sfu.valid_until)
          ORDER BY sfu.edit_at DESC
         LIMIT 1) sfu_le ON true
     LEFT JOIN LATERAL ( SELECT array_agg(ds_1.id) AS ids,
            array_agg(ds_1.code) AS codes
           FROM public.data_source ds_1
          WHERE COALESCE(ds_1.id = es.data_source_id, false) OR COALESCE(ds_1.id = pa.data_source_id, false) OR COALESCE(ds_1.id = sa.data_source_id, false) OR COALESCE(ds_1.id = phl.data_source_id, false) OR COALESCE(ds_1.id = pol.data_source_id, false) OR COALESCE(ds_1.id = ANY (sfu_ds.data_source_ids), false)) ds ON true
     LEFT JOIN LATERAL ( SELECT all_edits.edit_comment,
            all_edits.edit_by_user_id,
            all_edits.edit_at
           FROM ( VALUES (es.edit_comment,es.edit_by_user_id,es.edit_at), (pa.edit_comment,pa.edit_by_user_id,pa.edit_at), (sa.edit_comment,sa.edit_by_user_id,sa.edit_at), (phl.edit_comment,phl.edit_by_user_id,phl.edit_at), (pol.edit_comment,pol.edit_by_user_id,pol.edit_at), (c.edit_comment,c.edit_by_user_id,c.edit_at), (sfu_le.edit_comment,sfu_le.edit_by_user_id,sfu_le.edit_at)) all_edits(edit_comment, edit_by_user_id, edit_at)
          WHERE all_edits.edit_at IS NOT NULL
          ORDER BY all_edits.edit_at DESC
         LIMIT 1) last_edit ON true,
    public.settings current_settings
  WHERE t.unit_type = 'establishment'::public.statistical_unit_type AND (p_unit_ids IS NULL OR t.unit_id = ANY (p_unit_ids))
  ORDER BY t.unit_type, t.unit_id, t.valid_from
$function$
;

CREATE OR REPLACE PROCEDURE import.process_enterprise_link_for_legal_unit(IN p_job_id integer, IN p_batch_seq integer, IN p_step_code text)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_sql TEXT;
    v_update_count INT := 0;
    v_created_enterprise_count INT := 0;
    error_message TEXT; -- For main exception handler
    rec_new_lu RECORD;
    new_enterprise_id INT;
    v_job_mode public.import_mode;
BEGIN
    RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit (Batch): Starting operation for batch_seq %', p_job_id, p_batch_seq;

    -- Get job details
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    v_job_mode := (v_job.definition_snapshot->'import_definition'->>'mode')::public.import_mode;

    -- Find the step details from the snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'enterprise_link_for_legal_unit';
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] enterprise_link_for_legal_unit step not found in snapshot', p_job_id; END IF;

    IF v_job_mode != 'legal_unit' THEN
        RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit: Skipping, job mode is %, not ''legal_unit''. No action needed.', p_job_id, v_job_mode;
        RETURN;
    END IF;

    -- Step 1: Identify rows needing enterprise creation (new LUs, action = 'insert')
    IF to_regclass('pg_temp.temp_new_lu_for_enterprise_creation') IS NOT NULL THEN DROP TABLE temp_new_lu_for_enterprise_creation; END IF;
    CREATE TEMP TABLE temp_new_lu_for_enterprise_creation (
        data_row_id INTEGER PRIMARY KEY, -- This will be the founding_row_id for the new LU entity
        edit_by_user_id INT,
        edit_at TIMESTAMPTZ,
        edit_comment TEXT
    ) ON COMMIT DROP;

    v_sql := format($$
        INSERT INTO temp_new_lu_for_enterprise_creation (data_row_id, edit_by_user_id, edit_at, edit_comment)
        SELECT dt.row_id, dt.edit_by_user_id, dt.edit_at, dt.edit_comment
        FROM public.%1$I dt
        WHERE dt.batch_seq = $1
          AND dt.action = 'use' AND dt.legal_unit_id IS NULL AND dt.founding_row_id = dt.row_id; -- Only process founding rows for new LUs
    $$, v_data_table_name /* %1$I */);
    RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit: Populating temp table for new LUs with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_seq;

    -- Step 2: Create new enterprises for LUs in temp_new_lu_for_enterprise_creation and map them
    -- temp_created_enterprises.data_row_id will store the founding_row_id of the LU
    IF to_regclass('pg_temp.temp_created_enterprises') IS NOT NULL THEN DROP TABLE temp_created_enterprises; END IF;
    CREATE TEMP TABLE temp_created_enterprises (
        data_row_id INTEGER PRIMARY KEY, -- Stores the founding_row_id of the LU
        enterprise_id INT NOT NULL
    ) ON COMMIT DROP;

    v_created_enterprise_count := 0;
    BEGIN
        WITH new_enterprises AS (
            INSERT INTO public.enterprise (short_name, edit_by_user_id, edit_at, edit_comment)
            SELECT
                NULL, -- short_name is set to NULL, will be derived by trigger later
                t.edit_by_user_id,
                t.edit_at,
                t.edit_comment
            FROM temp_new_lu_for_enterprise_creation t
            RETURNING id
        ),
        -- This mapping is tricky because INSERT...RETURNING doesn't give us back the source rows.
        -- We rely on the fact that the order should be preserved and join by row_number.
        -- This is safe as we are in a single transaction and not using parallel workers.
        source_with_rn AS (
            SELECT *, ROW_NUMBER() OVER () as rn FROM temp_new_lu_for_enterprise_creation
        ),
        created_with_rn AS (
            SELECT id, ROW_NUMBER() OVER () as rn FROM new_enterprises
        )
        INSERT INTO temp_created_enterprises (data_row_id, enterprise_id)
        SELECT s.data_row_id, c.id
        FROM source_with_rn s
        JOIN created_with_rn c ON s.rn = c.rn;

        GET DIAGNOSTICS v_created_enterprise_count = ROW_COUNT;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_enterprise_link_for_legal_unit: Programming error suspected during enterprise creation loop: %', p_job_id, replace(error_message, '%', '%%');
        UPDATE public.import_job SET error = jsonb_build_object('programming_error_process_enterprise_link_lu', error_message) WHERE id = p_job_id;
        -- Constraints and temp table cleanup will be handled by the main exception block or successful completion
        RAISE; 
    END;

    RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit: Created % new enterprises.', p_job_id, v_created_enterprise_count;

    -- Step 3: Update _data table for newly created enterprises (action = 'insert')
    -- For new LUs linked to new Enterprises, all their initial slices are primary.
    v_sql := format($$
        UPDATE public.%1$I dt SET
            enterprise_id = tce.enterprise_id,
            primary_for_enterprise = TRUE, -- All slices of a new LU linked to a new Enterprise are initially primary
            state = %2$L
        FROM temp_created_enterprises tce -- tce.data_row_id is the founding_row_id
        WHERE dt.batch_seq = $1
          AND dt.founding_row_id = tce.data_row_id -- Link all rows of the entity via founding_row_id
          AND dt.action = 'use'; -- Only update usable rows
    $$, v_data_table_name /* %1$I */, 'processing'::public.import_data_state /* %2$L */);
    RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit: Updating _data for new enterprises and their related rows (action=insert): %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_seq;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;

    -- Step 4: Update rows that were already processed by analyse step (existing LUs) - just advance priority
    v_sql := format($$
        UPDATE public.%1$I dt SET
            state = %2$L::public.import_data_state
        WHERE dt.batch_seq = $1
          AND dt.action = 'use' AND dt.legal_unit_id IS NOT NULL; -- Only update rows for existing LUs
    $$, v_data_table_name /* %1$I */, 'processing' /* %2$L */);
     RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit: Updating existing LUs (action=replace, priority only): %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_seq;

    -- Step 5: Update skipped rows (action = 'skip') - no LCP update needed in processing phase.
    GET DIAGNOSTICS v_update_count = ROW_COUNT; -- Re-using v_update_count, fine for debug
    RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit: Advanced priority for % skipped rows.', p_job_id, v_update_count;

    RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit (Batch): Finished operation. Linked % LUs to enterprises (includes new and existing).', p_job_id, v_update_count; -- v_update_count here is from the last UPDATE (skipped rows)

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
    RAISE WARNING '[Job %] process_enterprise_link_for_legal_unit: Unhandled error during operation: %', p_job_id, replace(error_message, '%', '%%');
    -- Update job error
    UPDATE public.import_job
    SET error = jsonb_build_object('process_enterprise_link_for_legal_unit_error', error_message),
        state = 'finished'
    WHERE id = p_job_id;
    RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit: Marked job as failed due to error: %', p_job_id, error_message;
    RAISE; -- Re-raise the original exception
END;
$procedure$
;

CREATE OR REPLACE PROCEDURE import.process_enterprise_link_for_establishment(IN p_job_id integer, IN p_batch_seq integer, IN p_step_code text)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_sql TEXT;
    v_update_count INT := 0;
    v_created_enterprise_count INT := 0;
    error_message TEXT;
    rec_new_est RECORD;
    new_enterprise_id INT;
    v_job_mode public.import_mode;
BEGIN
    RAISE DEBUG '[Job %] process_enterprise_link_for_establishment (batch_seq=%): Starting operation', p_job_id, p_batch_seq;

    -- Get job details
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    v_job_mode := (v_job.definition_snapshot->'import_definition'->>'mode')::public.import_mode;

    -- Find the step details from the snapshot first
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'enterprise_link_for_establishment';
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] enterprise_link_for_establishment step not found in snapshot', p_job_id; END IF;

    IF v_job_mode != 'establishment_informal' THEN
        RAISE DEBUG '[Job %] process_enterprise_link_for_establishment: Skipping, job mode is %, not ''establishment_informal''. No action needed.', p_job_id, v_job_mode;
        RETURN;
    END IF;

    -- Step 1: Identify rows needing enterprise creation (new standalone ESTs, action = 'insert')
    IF to_regclass('pg_temp.temp_new_est_for_enterprise_creation') IS NOT NULL THEN DROP TABLE temp_new_est_for_enterprise_creation; END IF;
    CREATE TEMP TABLE temp_new_est_for_enterprise_creation (
        data_row_id INTEGER PRIMARY KEY, -- This will be the founding_row_id for the new EST entity
        edit_by_user_id INT,
        edit_at TIMESTAMPTZ,
        edit_comment TEXT
    ) ON COMMIT DROP;

    v_sql := format($$
        INSERT INTO temp_new_est_for_enterprise_creation (data_row_id, edit_by_user_id, edit_at, edit_comment)
        SELECT dt.row_id, dt.edit_by_user_id, dt.edit_at, dt.edit_comment
        FROM public.%1$I dt
        WHERE dt.batch_seq = $1
          AND dt.operation = 'insert' AND dt.founding_row_id = dt.row_id; -- Only process founding rows for new ESTs
    $$, v_data_table_name /* %1$I */);
    RAISE DEBUG '[Job %] process_enterprise_link_for_establishment (batch_seq=%): Populating temp table for new ESTs with SQL: %', p_job_id, p_batch_seq, v_sql;
    EXECUTE v_sql USING p_batch_seq;

    -- Step 2: Create new enterprises for ESTs in temp_new_est_for_enterprise_creation and map them
    -- temp_created_enterprises.data_row_id will store the founding_row_id of the EST
    IF to_regclass('pg_temp.temp_created_enterprises') IS NOT NULL THEN DROP TABLE temp_created_enterprises; END IF;
    CREATE TEMP TABLE temp_created_enterprises (
        data_row_id INTEGER PRIMARY KEY, -- Stores the founding_row_id of the EST
        enterprise_id INT NOT NULL
    ) ON COMMIT DROP;

    v_created_enterprise_count := 0;
    BEGIN
        WITH new_enterprises AS (
            INSERT INTO public.enterprise (short_name, edit_by_user_id, edit_at, edit_comment)
            SELECT
                NULL, -- short_name is set to NULL, will be derived by trigger later
                t.edit_by_user_id,
                t.edit_at,
                t.edit_comment
            FROM temp_new_est_for_enterprise_creation t
            RETURNING id
        ),
        source_with_rn AS (
            SELECT *, ROW_NUMBER() OVER () as rn FROM temp_new_est_for_enterprise_creation
        ),
        created_with_rn AS (
            SELECT id, ROW_NUMBER() OVER () as rn FROM new_enterprises
        )
        INSERT INTO temp_created_enterprises (data_row_id, enterprise_id)
        SELECT s.data_row_id, c.id
        FROM source_with_rn s
        JOIN created_with_rn c ON s.rn = c.rn;

        GET DIAGNOSTICS v_created_enterprise_count = ROW_COUNT;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_enterprise_link_for_establishment: Programming error suspected during enterprise creation loop: %', p_job_id, replace(error_message, '%', '%%');
        UPDATE public.import_job SET error = jsonb_build_object('programming_error_process_enterprise_link_est', error_message) WHERE id = p_job_id;
        -- Constraints and temp table cleanup will be handled by the main exception block or successful completion
        RAISE;
    END;

    RAISE DEBUG '[Job %] process_enterprise_link_for_establishment: Created % new enterprises.', p_job_id, v_created_enterprise_count;

    -- Step 3: Update _data table for newly created enterprises (action = 'insert') and their related 'replace' rows
    -- For new informal ESTs linked to new Enterprises, all their initial slices are primary.
    v_sql := format($$
        UPDATE public.%1$I dt SET -- v_data_table_name
            enterprise_id = tce.enterprise_id,
            primary_for_enterprise = TRUE, -- All slices of a new informal EST linked to a new Enterprise are initially primary
            state = %2$L -- 'processing'
        FROM temp_created_enterprises tce -- tce.data_row_id is the founding_row_id
        WHERE dt.batch_seq = $1
          AND dt.founding_row_id = tce.data_row_id -- Link all rows of the entity via founding_row_id
          AND dt.action = 'use'; -- Only update usable rows
    $$, v_data_table_name, 'processing'::public.import_data_state);
    RAISE DEBUG '[Job %] process_enterprise_link_for_establishment (batch_seq=%): Updating _data for new enterprises and their related rows: %', p_job_id, p_batch_seq, v_sql;
    EXECUTE v_sql USING p_batch_seq;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;

    -- Step 4: Update rows that were already processed by analyse step (existing ESTs, action = 'replace') - just advance priority
    v_sql := format($$
        UPDATE public.%1$I dt SET
            state = %2$L
        WHERE dt.batch_seq = $1
          AND dt.operation = 'replace' -- Only update rows for existing ESTs (mode 'establishment_informal' implies no LU link in data)
          AND dt.action = 'use'; -- Only update usable rows
    $$, v_data_table_name /* %1$I */, 'processing' /* %2$L */);
    RAISE DEBUG '[Job %] process_enterprise_link_for_establishment (batch_seq=%): Updating existing ESTs (action=replace, priority only): %', p_job_id, p_batch_seq, v_sql;
    EXECUTE v_sql USING p_batch_seq;

    -- Step 5: Update skipped rows (action = 'skip') - no LCP update needed in processing phase.
    GET DIAGNOSTICS v_update_count = ROW_COUNT; -- Re-using v_update_count, fine for debug
    RAISE DEBUG '[Job %] process_enterprise_link_for_establishment: Advanced priority for % skipped rows.', p_job_id, v_update_count;

    RAISE DEBUG '[Job %] process_enterprise_link_for_establishment (batch_seq=%): Finished operation. Created % enterprises.', p_job_id, p_batch_seq, v_created_enterprise_count;

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
    RAISE WARNING '[Job %] process_enterprise_link_for_establishment: Unhandled error during operation: %', p_job_id, replace(error_message, '%', '%%');
    -- Update job error
    UPDATE public.import_job
    SET error = jsonb_build_object('process_enterprise_link_for_establishment_error', error_message),
        state = 'finished'
    WHERE id = p_job_id;
    RAISE DEBUG '[Job %] process_enterprise_link_for_establishment: Marked job as failed due to error: %', p_job_id, error_message;
    RAISE; -- Re-raise the original exception
END;
$procedure$
;

END;
