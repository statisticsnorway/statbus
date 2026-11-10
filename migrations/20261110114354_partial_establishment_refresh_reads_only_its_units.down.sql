-- Down Migration 20261110114354: partial establishment refresh reads only its units (STATBUS-605)
BEGIN;

CREATE OR REPLACE VIEW public.timeline_establishment_def
 WITH (security_invoker='on') AS
 WITH establishment_stats AS (
         SELECT t_1.unit_id,
            t_1.valid_from,
            public.jsonb_stats_agg(sd.code::text, sfu.stat) FILTER (WHERE sd.code IS NOT NULL) AS stats
           FROM public.timesegments t_1
             JOIN public.stat_for_unit sfu ON sfu.establishment_id = t_1.unit_id AND public.from_until_overlaps(t_1.valid_from, t_1.valid_until, sfu.valid_from, sfu.valid_until)
             JOIN public.stat_definition sd ON sfu.stat_definition_id = sd.id
          WHERE t_1.unit_type = 'establishment'::public.statistical_unit_type
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
  ORDER BY t.unit_type, t.unit_id, t.valid_from;

COMMENT ON VIEW public.timeline_establishment_def IS NULL;

DROP FUNCTION public.timeline_establishment_def_for(integer[]);

CREATE OR REPLACE PROCEDURE public.timeline_establishment_refresh(IN p_unit_id_ranges int4multirange DEFAULT NULL::int4multirange)
 LANGUAGE plpgsql
AS $procedure$
BEGIN
    -- Only ANALYZE for full refresh (sync points handle partial refresh ANALYZE)
    IF p_unit_id_ranges IS NULL THEN
        ANALYZE public.timesegments, public.establishment, public.activity, public.location, public.contact, public.stat_for_unit;
    END IF;
    CALL public.timeline_refresh('timeline_establishment', 'establishment', p_unit_id_ranges);
END;
$procedure$
;

DROP INDEX public.statistical_unit_staging_hash_slot_unit_idx;
DROP INDEX public.idx_statistical_unit_hash_slot;
CREATE INDEX idx_statistical_unit_hash_slot ON public.statistical_unit USING btree (hash_slot);

END;
