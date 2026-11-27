-- Migration 20261127091335: legal unit totals: rollup per variable and counting where a unit exists
--
-- s465ff: each summed variable chooses how a legal unit's total combines its own value with its
-- establishments' (stat_definition.lu_es_rollup): 'sum' adds them, as every released version did;
-- 'max' takes the larger (public.jsonb_stats_covers, master since ca6dk5). Default sum. The two
-- quality checks comparing the levels apply only to a variable set to max: under sum the levels add.
--
-- f2gx3m: a unit counts in its legal unit's and enterprise's totals only where it exists, by the
-- canonical rule (STATBUS-460): its validity covers the period and, where set, the period is on or
-- after its birth_date and before its death_date (public.unit_existence_from / unit_existence_until),
-- the rule the Links tree already uses (establishment_hierarchy). jo: establishment 86, valid from
-- 2023-01-01 and born 2024-11-01, was counted in 2023. Owner design 2026-11-26: birth and death are
-- timepoints, used_for_counting means "counts in this row" (public.unit_counts_in, the one place the
-- rule is written), and every count reads that column: the legal unit's and enterprise's totals
-- and the report facets. The import refuses a birth_date in a later calendar year than the row's
-- valid_from (import.analyse_date_consistency).
--
-- Every installation recalculates its totals once.
BEGIN;

CREATE TYPE public.lu_es_rollup AS ENUM ('sum', 'max');
COMMENT ON TYPE public.lu_es_rollup IS
  'How a legal unit''s total of a summed variable combines its own value with its establishments'' (s465ff). sum: own value plus the establishments'' sum, for a country that reports each value on one level. max: the larger of the two, for a country that reports a value on both levels (Norway''s employees), so the same people count once.';

ALTER TABLE public.stat_definition ADD COLUMN lu_es_rollup public.lu_es_rollup NOT NULL DEFAULT 'sum';
COMMENT ON COLUMN public.stat_definition.lu_es_rollup IS
  'How a legal unit''s total of this variable combines its own value with its establishments'' (public.lu_es_rollup); sum by default, the rule of every released version. Read by public.jsonb_stats_lu_es_rollup; changing it recalculates the totals (trigger stat_definition_lu_es_rollup_recalculate). The quality checks comparing the two levels apply only under max.';

CREATE FUNCTION public.jsonb_stats_lu_es_rollup(own jsonb, parts jsonb)
RETURNS jsonb
LANGUAGE sql
STABLE PARALLEL SAFE
AS $jsonb_stats_lu_es_rollup$
    -- Per stat: 'max' takes the summary with the larger sum (public.jsonb_stats_covers), 'sum' adds the
    -- two (public.jsonb_stats_merge); a stat held on one level only is that level's summary either way.
    SELECT CASE
        WHEN jsonb_stats_lu_es_rollup.own IS NULL THEN jsonb_stats_lu_es_rollup.parts
        WHEN jsonb_stats_lu_es_rollup.parts IS NULL THEN jsonb_stats_lu_es_rollup.own
        ELSE (
            SELECT jsonb_object_agg(k.key,
                CASE
                    WHEN k.key = 'type' THEN coalesce(jsonb_stats_lu_es_rollup.own->'type', jsonb_stats_lu_es_rollup.parts->'type')
                    WHEN NOT jsonb_stats_lu_es_rollup.own ? k.key THEN jsonb_stats_lu_es_rollup.parts->k.key
                    WHEN NOT jsonb_stats_lu_es_rollup.parts ? k.key THEN jsonb_stats_lu_es_rollup.own->k.key
                    WHEN COALESCE(sd.lu_es_rollup, 'sum') = 'sum'
                         AND (jsonb_stats_lu_es_rollup.own->k.key) ? 'sum' AND (jsonb_stats_lu_es_rollup.parts->k.key) ? 'sum'
                        THEN public.jsonb_stats_merge(
                                 jsonb_build_object('type', jsonb_stats_lu_es_rollup.own->'type', k.key, jsonb_stats_lu_es_rollup.own->k.key),
                                 jsonb_build_object('type', jsonb_stats_lu_es_rollup.parts->'type', k.key, jsonb_stats_lu_es_rollup.parts->k.key))->k.key
                    ELSE public.jsonb_stats_covers(
                             jsonb_build_object('type', jsonb_stats_lu_es_rollup.own->'type', k.key, jsonb_stats_lu_es_rollup.own->k.key),
                             jsonb_build_object('type', jsonb_stats_lu_es_rollup.parts->'type', k.key, jsonb_stats_lu_es_rollup.parts->k.key))->k.key
                END)
            FROM (SELECT jsonb_object_keys(jsonb_stats_lu_es_rollup.own) AS key
                  UNION
                  SELECT jsonb_object_keys(jsonb_stats_lu_es_rollup.parts)) AS k
            LEFT JOIN public.stat_definition AS sd ON sd.code = k.key)
    END
$jsonb_stats_lu_es_rollup$;

COMMENT ON FUNCTION public.jsonb_stats_lu_es_rollup(jsonb, jsonb) IS
  'A legal unit''s stats summary from its own summary and its counted establishments'' (s465ff): per stat by the variable''s stat_definition.lu_es_rollup, ''sum'' adding the two levels (public.jsonb_stats_merge) and ''max'' taking the level with the larger sum (public.jsonb_stats_covers). A stat held on one level only, or without a summed value, follows jsonb_stats_covers. Used by timeline_legal_unit_def_for; enterprises and power groups always add their legal units.';

CREATE FUNCTION public.unit_counts_in(status_counts boolean, valid_from date, valid_until date, birth_date date, death_date date, row_valid_from date, row_valid_until date)
RETURNS boolean
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
AS $unit_counts_in$
    SELECT unit_counts_in.status_counts
       AND public.unit_existence_from(unit_counts_in.valid_from, unit_counts_in.birth_date) <= unit_counts_in.row_valid_from
       AND unit_counts_in.row_valid_until <= public.unit_existence_until(unit_counts_in.valid_until, unit_counts_in.death_date)
$unit_counts_in$;

COMMENT ON FUNCTION public.unit_counts_in(boolean, date, date, date, date, date, date) IS
  'Whether a unit counts in a timeline row (f2gx3m): its status counts (status.used_for_counting) and the unit exists over the whole row, from public.unit_existence_from(valid_from, birth_date) to public.unit_existence_until(valid_until, death_date), the canonical existence rule (STATBUS-460). Birth and death only narrow counting where they are set; with neither, validity alone decides. valid_from/valid_until are the unit version''s, row_valid_from/row_valid_until the timeline row''s; timepoints_calculate splits a timeline at birth and death, so a row lies wholly inside or outside the existence. Every timeline computes its used_for_counting with it, and every count reads that column.';

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
    public.unit_counts_in(st.used_for_counting, es.valid_from, es.valid_until, es.birth_date, es.death_date, t.valid_from, t.valid_until) AS used_for_counting,
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
            WHEN public.unit_counts_in(st.used_for_counting, es.valid_from, es.valid_until, es.birth_date, es.death_date, t.valid_from, t.valid_until) THEN ARRAY[t.unit_id]
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
            public.unit_counts_in(st.used_for_counting, lu.valid_from, lu.valid_until, lu.birth_date, lu.death_date, t.valid_from, t.valid_until) AS used_for_counting,
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
            WHEN basis.used_for_counting THEN COALESCE(public.jsonb_stats_lu_es_rollup(own => basis.stats_summary, parts => esa.stats_summary), '{}'::jsonb)
            ELSE '{}'::jsonb
        END AS stats_summary
   FROM basis
     LEFT JOIN establishment_aggs esa ON esa.unit_id = basis.unit_id AND esa.valid_from = basis.valid_from
  ORDER BY basis.unit_type, basis.unit_id, basis.valid_from
$function$
;

CREATE OR REPLACE FUNCTION public.timepoints_calculate(p_establishment_id_ranges int4multirange, p_legal_unit_id_ranges int4multirange, p_enterprise_id_ranges int4multirange, p_power_group_id_ranges int4multirange DEFAULT NULL::int4multirange)
 RETURNS TABLE(unit_type statistical_unit_type, unit_id integer, timepoint date)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    v_es_ids INT[]; v_lu_ids INT[]; v_en_ids INT[]; v_pg_ids INT[];
BEGIN
    -- COALESCE: int4multirange_to_array('{}') returns NULL, but we need empty array '{}'
    -- so that "v_es_ids IS NULL" only triggers for truly NULL params (= full scan),
    -- not for empty multiranges (= skip this unit type).
    IF p_establishment_id_ranges IS NOT NULL THEN v_es_ids := COALESCE(public.int4multirange_to_array(p_establishment_id_ranges), '{}'); END IF;
    IF p_legal_unit_id_ranges IS NOT NULL THEN v_lu_ids := COALESCE(public.int4multirange_to_array(p_legal_unit_id_ranges), '{}'); END IF;
    IF p_enterprise_id_ranges IS NOT NULL THEN v_en_ids := COALESCE(public.int4multirange_to_array(p_enterprise_id_ranges), '{}'); END IF;
    IF p_power_group_id_ranges IS NOT NULL THEN v_pg_ids := COALESCE(public.int4multirange_to_array(p_power_group_id_ranges), '{}'); END IF;
    RETURN QUERY
    WITH es_periods AS (
        SELECT id AS src_unit_id, valid_from, valid_until FROM public.establishment WHERE v_es_ids IS NULL OR id = ANY(v_es_ids)
        UNION ALL SELECT establishment_id, valid_from, valid_until FROM public.activity WHERE v_es_ids IS NULL OR establishment_id = ANY(v_es_ids)
        UNION ALL SELECT establishment_id, valid_from, valid_until FROM public.location WHERE v_es_ids IS NULL OR establishment_id = ANY(v_es_ids)
        UNION ALL SELECT establishment_id, valid_from, valid_until FROM public.contact WHERE v_es_ids IS NULL OR establishment_id = ANY(v_es_ids)
        UNION ALL SELECT establishment_id, valid_from, valid_until FROM public.stat_for_unit WHERE v_es_ids IS NULL OR establishment_id = ANY(v_es_ids)
        UNION ALL SELECT establishment_id, valid_from, valid_until FROM public.person_for_unit WHERE v_es_ids IS NULL OR establishment_id = ANY(v_es_ids)
        -- f2gx3m: birth and death, where set and inside the validity, split the timeline (public.unit_counts_in).
        UNION ALL SELECT id, public.existence_from(establishment), public.existence_until(establishment) FROM public.establishment
                  WHERE (birth_date IS NOT NULL OR death_date IS NOT NULL) AND (v_es_ids IS NULL OR id = ANY(v_es_ids))
    ),
    lu_periods_base AS (
        SELECT id AS src_unit_id, valid_from, valid_until FROM public.legal_unit WHERE v_lu_ids IS NULL OR id = ANY(v_lu_ids)
        UNION ALL SELECT legal_unit_id, valid_from, valid_until FROM public.activity WHERE v_lu_ids IS NULL OR legal_unit_id = ANY(v_lu_ids)
        UNION ALL SELECT legal_unit_id, valid_from, valid_until FROM public.location WHERE v_lu_ids IS NULL OR legal_unit_id = ANY(v_lu_ids)
        UNION ALL SELECT legal_unit_id, valid_from, valid_until FROM public.contact WHERE v_lu_ids IS NULL OR legal_unit_id = ANY(v_lu_ids)
        UNION ALL SELECT legal_unit_id, valid_from, valid_until FROM public.stat_for_unit WHERE v_lu_ids IS NULL OR legal_unit_id = ANY(v_lu_ids)
        UNION ALL SELECT legal_unit_id, valid_from, valid_until FROM public.person_for_unit WHERE v_lu_ids IS NULL OR legal_unit_id = ANY(v_lu_ids)
        UNION ALL SELECT id, public.existence_from(legal_unit), public.existence_until(legal_unit) FROM public.legal_unit
                  WHERE (birth_date IS NOT NULL OR death_date IS NOT NULL) AND (v_lu_ids IS NULL OR id = ANY(v_lu_ids))
    ),
    lu_periods_with_children AS (
        SELECT src_unit_id, valid_from, valid_until FROM lu_periods_base
        UNION ALL
        SELECT es.legal_unit_id, GREATEST(p.valid_from, es.valid_from), LEAST(p.valid_until, es.valid_until)
        FROM es_periods AS p JOIN public.establishment AS es ON p.src_unit_id = es.id
        WHERE (v_lu_ids IS NULL OR es.legal_unit_id = ANY(v_lu_ids)) AND from_until_overlaps(p.valid_from, p.valid_until, es.valid_from, es.valid_until)
    ),
    pg_periods AS (
        SELECT lr.derived_power_group_id AS src_unit_id, lower(lr.valid_range) AS valid_from, upper(lr.valid_range) AS valid_until
        FROM public.legal_relationship AS lr
        WHERE lr.derived_power_group_id IS NOT NULL AND (v_pg_ids IS NULL OR lr.derived_power_group_id = ANY(v_pg_ids))
    ),
    all_periods (src_unit_type, src_unit_id, valid_from, valid_until) AS (
        SELECT 'establishment'::public.statistical_unit_type, e.id, GREATEST(p.valid_from, e.valid_from), LEAST(p.valid_until, e.valid_until)
        FROM es_periods p JOIN public.establishment e ON p.src_unit_id = e.id
        WHERE (v_es_ids IS NULL OR e.id = ANY(v_es_ids)) AND from_until_overlaps(p.valid_from, p.valid_until, e.valid_from, e.valid_until)
        UNION ALL
        SELECT 'legal_unit', l.id, GREATEST(p.valid_from, l.valid_from), LEAST(p.valid_until, l.valid_until)
        FROM lu_periods_with_children p JOIN public.legal_unit l ON p.src_unit_id = l.id
        WHERE (v_lu_ids IS NULL OR l.id = ANY(v_lu_ids)) AND from_until_overlaps(p.valid_from, p.valid_until, l.valid_from, l.valid_until)
        UNION ALL
        SELECT 'enterprise', lu.enterprise_id, GREATEST(p.valid_from, lu.valid_from), LEAST(p.valid_until, lu.valid_until)
        FROM lu_periods_with_children p JOIN public.legal_unit lu ON p.src_unit_id = lu.id
        WHERE (v_en_ids IS NULL OR lu.enterprise_id = ANY(v_en_ids)) AND from_until_overlaps(p.valid_from, p.valid_until, lu.valid_from, lu.valid_until)
        UNION ALL
        SELECT 'enterprise', es.enterprise_id, GREATEST(p.valid_from, es.valid_from), LEAST(p.valid_until, es.valid_until)
        FROM es_periods p JOIN public.establishment es ON p.src_unit_id = es.id
        WHERE es.enterprise_id IS NOT NULL AND (v_en_ids IS NULL OR es.enterprise_id = ANY(v_en_ids)) AND from_until_overlaps(p.valid_from, p.valid_until, es.valid_from, es.valid_until)
        UNION ALL
        SELECT 'power_group', pg.id, p.valid_from, p.valid_until
        FROM pg_periods p JOIN public.power_group pg ON p.src_unit_id = pg.id
        WHERE v_pg_ids IS NULL OR pg.id = ANY(v_pg_ids)
    ),
    unpivoted AS (
        SELECT p.src_unit_type, p.src_unit_id, p.valid_from AS timepoint FROM all_periods p WHERE p.valid_from < p.valid_until
        UNION
        SELECT p.src_unit_type, p.src_unit_id, p.valid_until AS timepoint FROM all_periods p WHERE p.valid_from < p.valid_until
    )
    SELECT DISTINCT up.src_unit_type, up.src_unit_id, up.timepoint FROM unpivoted up WHERE up.timepoint IS NOT NULL;
END;
$function$
;

CREATE OR REPLACE PROCEDURE worker.derive_statistical_unit_facet_partition(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_hash_partition int4range := (payload->>'hash_partition')::int4range;
    -- Pre-compute explicit half-open bounds so the btree index on hash_slot is
    -- used. Range containment (<@) via a variable int4range is not planned as a
    -- btree scan at 2.2M rows; explicit bounds are. Mirrors the sibling
    -- derive_statistical_history_facet_period which passes scalar bounds.
    v_from  integer := lower(v_hash_partition);
    v_until integer := upper(v_hash_partition);
    v_row_count bigint;
BEGIN
    DELETE FROM public.statistical_unit_facet_staging
     WHERE hash_slot >= v_from AND hash_slot < v_until;

    -- STATBUS-475, f2gx3m: a row counts where the unit exists. The timelines split at birth and
    -- death and carry the rule in used_for_counting (public.unit_counts_in), so a counted row's
    -- period is the existence and the drilldown's valid_from <= valid_on < valid_until counts it.
    INSERT INTO public.statistical_unit_facet_staging
    SELECT su.hash_slot,
           su.valid_from, su.valid_to, su.valid_until, su.unit_type,
           su.physical_region_path, su.primary_activity_category_path,
           su.sector_path, su.legal_form_id, su.physical_country_id, su.status_id,
           COUNT(*)::integer,
           public.jsonb_stats_merge_agg(su.stats_summary)
    FROM public.statistical_unit AS su
    WHERE su.used_for_counting
      AND su.hash_slot >= v_from AND su.hash_slot < v_until
    GROUP BY su.hash_slot, su.valid_from, su.valid_to, su.valid_until, su.unit_type,
             su.physical_region_path, su.primary_activity_category_path,
             su.sector_path, su.legal_form_id, su.physical_country_id, su.status_id;
    GET DIAGNOSTICS v_row_count := ROW_COUNT;
    p_info := jsonb_build_object('rows_inserted', v_row_count);
END;
$procedure$
;

CREATE OR REPLACE PROCEDURE worker.statistical_history_facet_delta_contribution(IN p_source regclass, IN p_sign smallint)
 LANGUAGE plpgsql
AS $procedure$
BEGIN
    IF to_regclass('pg_temp.hd_v') IS NOT NULL THEN DROP TABLE pg_temp.hd_v; END IF;
    EXECUTE format($SQL$
    CREATE TEMP TABLE hd_v AS
    SELECT s.unit_type, s.unit_id, s.valid_from, s.valid_until, s.birth_date, s.death_date,
           s.used_for_counting AS counted, s.name, s.stats_summary,
           s.primary_activity_category_path, s.secondary_activity_category_path, s.sector_path, s.legal_form_id,
           s.physical_region_path, s.physical_country_id, s.unit_size_id, s.status_id,
           (s.physical_address_part1, s.physical_address_part2, s.physical_address_part3,
            s.physical_postcode, s.physical_postplace)::text AS addr,
           public.unit_existence_from(s.valid_from, s.birth_date) AS ef,
           public.unit_existence_until(s.valid_until, s.death_date) AS eu,
           -- The next counted version: a row that does not count (before a birth, after a death, f2gx3m) carries no
           -- stats, so the stats of the version before it end where that row starts.
           min(CASE WHEN s.used_for_counting THEN s.valid_from END) OVER (PARTITION BY s.unit_type, s.unit_id ORDER BY s.valid_from
               ROWS BETWEEN 1 FOLLOWING AND UNBOUNDED FOLLOWING) AS next_valid_from
      FROM %1$s AS s
      JOIN pg_temp.hd_units AS u ON u.unit_type = s.unit_type AND u.unit_id = s.unit_id
    $SQL$, p_source);  -- a regclass renders as its quoted, schema-qualified name

    -- The existence windows in order, with their neighbours. A version whose window is empty (born after it
    -- ended, or died before it began) is no existence and takes no part.
    IF to_regclass('pg_temp.hd_w') IS NOT NULL THEN DROP TABLE pg_temp.hd_w; END IF;
    CREATE TEMP TABLE hd_w AS
    SELECT v.*,
           lag(v.eu) OVER w IS NOT DISTINCT FROM v.ef AS continues,
           lead(v.ef) OVER w IS NOT DISTINCT FROM v.eu AS continued,
           lag(v.cell) OVER w AS prev_cell, lead(v.cell) OVER w AS next_cell,
           lag(v.counted) OVER w AS prev_counted, lead(v.counted) OVER w AS next_counted,
           lag(v.name) OVER w AS prev_name,
           lag(v.primary_activity_category_path) OVER w AS prev_primary_activity_category_path,
           lag(v.secondary_activity_category_path) OVER w AS prev_secondary_activity_category_path,
           lag(v.sector_path) OVER w AS prev_sector_path, lag(v.legal_form_id) OVER w AS prev_legal_form_id,
           lag(v.physical_region_path) OVER w AS prev_physical_region_path,
           lag(v.physical_country_id) OVER w AS prev_physical_country_id, lag(v.addr) OVER w AS prev_addr,
           lag(v.unit_size_id) OVER w AS prev_unit_size_id, lag(v.status_id) OVER w AS prev_status_id
      FROM (SELECT hd_v.*,
                   ROW(hd_v.primary_activity_category_path, hd_v.secondary_activity_category_path, hd_v.sector_path,
                       hd_v.legal_form_id, hd_v.physical_region_path, hd_v.physical_country_id, hd_v.unit_size_id,
                       hd_v.status_id)::text AS cell
              FROM pg_temp.hd_v WHERE hd_v.ef < hd_v.eu) AS v
    WINDOW w AS (PARTITION BY v.unit_type, v.unit_id ORDER BY v.ef);

    -- One row per event: (kind, count) or (kind, stats delta), in the cell and month it belongs to.
    IF to_regclass('pg_temp.hd_ev') IS NOT NULL THEN DROP TABLE pg_temp.hd_ev; END IF;
    CREATE TEMP TABLE hd_ev AS
    -- Start of a window, in its cell.
    SELECT w.unit_type, w.unit_id, w.primary_activity_category_path, w.secondary_activity_category_path, w.sector_path,
           w.legal_form_id, w.physical_region_path, w.physical_country_id, w.unit_size_id, w.status_id,
           date_trunc('month', w.ef)::date AS on_month, e.kind, 1 AS n, NULL::jsonb AS sd
      FROM pg_temp.hd_w AS w
     CROSS JOIN LATERAL (VALUES
            ('exists_added_count', NOT w.continues),
            ('countable_added_count', w.counted AND NOT (w.continues AND w.prev_counted)),
            ('births', w.counted AND NOT w.continues AND w.ef = w.birth_date),
            ('exists_moved_in_count', w.continues AND w.prev_cell IS DISTINCT FROM w.cell),
            ('countable_moved_in_count', w.continues AND w.prev_cell IS DISTINCT FROM w.cell AND w.prev_counted AND w.counted),
            ('name_change_count', w.continues AND w.prev_counted AND w.counted AND w.name IS DISTINCT FROM w.prev_name),
            ('primary_activity_category_change_count', w.continues AND w.prev_counted AND w.counted
                 AND w.primary_activity_category_path IS DISTINCT FROM w.prev_primary_activity_category_path),
            ('secondary_activity_category_change_count', w.continues AND w.prev_counted AND w.counted
                 AND w.secondary_activity_category_path IS DISTINCT FROM w.prev_secondary_activity_category_path),
            ('sector_change_count', w.continues AND w.prev_counted AND w.counted AND w.sector_path IS DISTINCT FROM w.prev_sector_path),
            ('legal_form_change_count', w.continues AND w.prev_counted AND w.counted AND w.legal_form_id IS DISTINCT FROM w.prev_legal_form_id),
            ('physical_region_change_count', w.continues AND w.prev_counted AND w.counted
                 AND w.physical_region_path IS DISTINCT FROM w.prev_physical_region_path),
            ('physical_country_change_count', w.continues AND w.prev_counted AND w.counted
                 AND w.physical_country_id IS DISTINCT FROM w.prev_physical_country_id),
            ('physical_address_change_count', w.continues AND w.prev_counted AND w.counted AND w.addr IS DISTINCT FROM w.prev_addr),
            ('unit_size_change_count', w.continues AND w.prev_counted AND w.counted AND w.unit_size_id IS DISTINCT FROM w.prev_unit_size_id),
            ('status_change_count', w.continues AND w.prev_counted AND w.counted AND w.status_id IS DISTINCT FROM w.prev_status_id)
           ) AS e(kind, applies)
     WHERE e.applies
    UNION ALL
    -- End of a window, in its cell.
    SELECT w.unit_type, w.unit_id, w.primary_activity_category_path, w.secondary_activity_category_path, w.sector_path,
           w.legal_form_id, w.physical_region_path, w.physical_country_id, w.unit_size_id, w.status_id,
           date_trunc('month', w.eu)::date, e.kind, 1, NULL::jsonb
      FROM pg_temp.hd_w AS w
     CROSS JOIN LATERAL (VALUES
            ('exists_removed_count', NOT w.continued),
            ('countable_removed_count', w.counted AND NOT (w.continued AND w.next_counted)),
            ('deaths', w.counted AND NOT w.continued AND w.eu = w.death_date),
            ('exists_moved_out_count', w.continued AND w.next_cell IS DISTINCT FROM w.cell),
            ('countable_moved_out_count', w.continued AND w.next_cell IS DISTINCT FROM w.cell AND w.counted AND w.next_counted)
           ) AS e(kind, applies)
     WHERE e.applies AND w.eu <> 'infinity'::date
    UNION ALL
    -- Stats of a counted version, from valid_from until valid_until.
    SELECT v.unit_type, v.unit_id, v.primary_activity_category_path, v.secondary_activity_category_path, v.sector_path,
           v.legal_form_id, v.physical_region_path, v.physical_country_id, v.unit_size_id, v.status_id,
           date_trunc('month', x.d)::date, 'stats_delta', 0, x.sd
      FROM pg_temp.hd_v AS v
     CROSS JOIN LATERAL (VALUES (v.valid_from, public.jsonb_stats_to_delta(v.stats_summary)),
                                (v.valid_until, public.jsonb_stats_negate(public.jsonb_stats_to_delta(v.stats_summary)))) AS x(d, sd)
     WHERE v.counted AND v.stats_summary IS NOT NULL AND x.d <> 'infinity'::date
    UNION ALL
    -- Stats of a counted version that ends inside a month (valid_until is not the 1st), when no later
    -- version starts by that month's end; likewise for the year.
    SELECT v.unit_type, v.unit_id, v.primary_activity_category_path, v.secondary_activity_category_path, v.sector_path,
           v.legal_form_id, v.physical_region_path, v.physical_country_id, v.unit_size_id, v.status_id,
           date_trunc('month', v.valid_until)::date, e.kind, 0, public.jsonb_stats_to_delta(v.stats_summary)
      FROM pg_temp.hd_v AS v
     CROSS JOIN LATERAL (VALUES
            ('stats_ended_month', extract(day FROM v.valid_until) <> 1
                AND (v.next_valid_from IS NULL
                     OR v.next_valid_from > (date_trunc('month', v.valid_until) + interval '1 month - 1 day')::date)),
            ('stats_ended_year', NOT (extract(month FROM v.valid_until) = 1 AND extract(day FROM v.valid_until) = 1)
                AND (v.next_valid_from IS NULL
                     OR v.next_valid_from > make_date(extract(year FROM v.valid_until)::int, 12, 31)))
           ) AS e(kind, applies)
     WHERE e.applies AND v.counted AND v.stats_summary IS NOT NULL AND isfinite(v.valid_until);

    INSERT INTO pg_temp.hd_rows (unit_id, sign, unit_type, primary_activity_category_path, secondary_activity_category_path,
           sector_path, legal_form_id, physical_region_path, physical_country_id, unit_size_id, status_id, on_month,
           exists_added_count, exists_removed_count, countable_added_count, countable_removed_count,
           exists_moved_in_count, exists_moved_out_count, countable_moved_in_count, countable_moved_out_count,
           births, deaths, name_change_count, primary_activity_category_change_count,
           secondary_activity_category_change_count, sector_change_count, legal_form_change_count,
           physical_region_change_count, physical_country_change_count, physical_address_change_count,
           unit_size_change_count, status_change_count, stats_delta, stats_ended_month, stats_ended_year)
    SELECT r.unit_id, r.sign, r.unit_type, r.primary_activity_category_path, r.secondary_activity_category_path,
           r.sector_path, r.legal_form_id, r.physical_region_path, r.physical_country_id, r.unit_size_id, r.status_id,
           r.on_month, r.c1, r.c2, r.c3, r.c4, r.c5, r.c6, r.c7, r.c8, r.c9, r.c10, r.c11, r.c12, r.c13, r.c14, r.c15,
           r.c16, r.c17, r.c18, r.c19, r.c20, r.sd, r.sem, r.sey
      FROM (
        SELECT unit_id, p_sign, unit_type, primary_activity_category_path, secondary_activity_category_path,
               sector_path, legal_form_id, physical_region_path, physical_country_id, unit_size_id, status_id, on_month,
               count(*) FILTER (WHERE kind = 'exists_added_count')::int AS a,
               count(*) FILTER (WHERE kind = 'exists_removed_count')::int,
               count(*) FILTER (WHERE kind = 'countable_added_count')::int,
               count(*) FILTER (WHERE kind = 'countable_removed_count')::int,
               count(*) FILTER (WHERE kind = 'exists_moved_in_count')::int,
               count(*) FILTER (WHERE kind = 'exists_moved_out_count')::int,
               count(*) FILTER (WHERE kind = 'countable_moved_in_count')::int,
               count(*) FILTER (WHERE kind = 'countable_moved_out_count')::int,
               count(*) FILTER (WHERE kind = 'births')::int,
               count(*) FILTER (WHERE kind = 'deaths')::int,
               count(*) FILTER (WHERE kind = 'name_change_count')::int,
               count(*) FILTER (WHERE kind = 'primary_activity_category_change_count')::int,
               count(*) FILTER (WHERE kind = 'secondary_activity_category_change_count')::int,
               count(*) FILTER (WHERE kind = 'sector_change_count')::int,
               count(*) FILTER (WHERE kind = 'legal_form_change_count')::int,
               count(*) FILTER (WHERE kind = 'physical_region_change_count')::int,
               count(*) FILTER (WHERE kind = 'physical_country_change_count')::int,
               count(*) FILTER (WHERE kind = 'physical_address_change_count')::int,
               count(*) FILTER (WHERE kind = 'unit_size_change_count')::int,
               count(*) FILTER (WHERE kind = 'status_change_count')::int,
               public.jsonb_stats_delta_nullif_zero(public.jsonb_stats_delta_agg(sd) FILTER (WHERE kind = 'stats_delta')) AS sd,
               public.jsonb_stats_delta_nullif_zero(public.jsonb_stats_delta_agg(sd) FILTER (WHERE kind = 'stats_ended_month')) AS sem,
               public.jsonb_stats_delta_nullif_zero(public.jsonb_stats_delta_agg(sd) FILTER (WHERE kind = 'stats_ended_year')) AS sey,
               count(*) FILTER (WHERE n <> 0) AS events
          FROM pg_temp.hd_ev
         GROUP BY unit_id, unit_type, primary_activity_category_path, secondary_activity_category_path, sector_path,
                  legal_form_id, physical_region_path, physical_country_id, unit_size_id, status_id, on_month
    ) AS r(unit_id, sign, unit_type, primary_activity_category_path, secondary_activity_category_path,
           sector_path, legal_form_id, physical_region_path, physical_country_id, unit_size_id, status_id, on_month,
           c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12, c13, c14, c15, c16, c17, c18, c19, c20, sd, sem, sey, events)
     WHERE r.events > 0 OR r.sd IS NOT NULL OR r.sem IS NOT NULL OR r.sey IS NOT NULL;
END;
$procedure$
;

CREATE OR REPLACE PROCEDURE import.analyse_date_consistency(IN p_job_id integer, IN p_batch_seq integer, IN p_step_code text)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_job_mode public.import_mode;
    v_unit_label TEXT;
    v_sql TEXT;
    v_ident_label_expr TEXT;
    v_has_name BOOLEAN;
    v_update_count INT := 0;
    -- The keys this step owns. They are real source_input column names, so the
    -- import UI (ErrorDisplay strips the _raw suffix) shows a meaningful field label.
    -- A birth after the window names birth_date and the window end (valid_to);
    -- a death before the window names death_date and the window start (valid_from).
    v_error_keys_arr TEXT[] := ARRAY['birth_date_raw', 'death_date_raw', 'valid_from_raw', 'valid_to_raw'];
BEGIN
    RAISE DEBUG '[Job %] analyse_date_consistency (Batch): Starting analysis for batch_seq %', p_job_id, p_batch_seq;

    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    v_job_mode := (v_job.definition_snapshot->'import_definition'->>'mode')::public.import_mode;

    SELECT * INTO v_step
    FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list')
    WHERE code = p_step_code;
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] analyse_date_consistency: step % not found in snapshot', p_job_id, p_step_code;
    END IF;

    -- The rule needs both life dates. A definition whose data table has neither
    -- (a definition without a unit step) has nothing to check: advance only.
    IF EXISTS (
        SELECT 1
        FROM jsonb_array_elements(v_job.definition_snapshot->'import_data_column_list') AS idc
        WHERE idc->>'column_name' = 'birth_date_raw' AND idc->>'purpose' = 'source_input'
    ) AND EXISTS (
        SELECT 1
        FROM jsonb_array_elements(v_job.definition_snapshot->'import_data_column_list') AS idc
        WHERE idc->>'column_name' = 'death_date_raw' AND idc->>'purpose' = 'source_input'
    ) THEN
        v_unit_label := CASE v_job_mode
            WHEN 'legal_unit' THEN 'Legal unit'
            WHEN 'establishment_formal' THEN 'Establishment'
            WHEN 'establishment_informal' THEN 'Establishment'
            ELSE 'Unit'
        END;

        SELECT EXISTS (
            SELECT 1
            FROM jsonb_array_elements(v_job.definition_snapshot->'import_data_column_list') AS idc
            WHERE idc->>'column_name' = 'name_raw' AND idc->>'purpose' = 'source_input'
        ) INTO v_has_name;

        -- Name the unit by the identifiers the row itself carries (at this point
        -- in the pipeline the unit has no database id yet), e.g. 'tax_ident 123'.
        SELECT COALESCE(
                   'concat_ws('', '', ' || string_agg(
                       format($fmt$CASE WHEN NULLIF(dt.%1$I, '') IS NOT NULL THEN %2$L || ' ' || dt.%1$I END$fmt$,
                              idc.column_name, regexp_replace(idc.column_name, '_raw$', '')),
                       ', ' ORDER BY idc.column_name) || ')',
                   'NULL::TEXT')
        INTO v_ident_label_expr
        FROM (
            SELECT idc->>'column_name' AS column_name
            FROM jsonb_array_elements(v_job.definition_snapshot->'import_data_column_list') AS idc
            JOIN jsonb_array_elements(v_job.definition_snapshot->'import_step_list') AS s
              ON (s->>'id')::int = (idc->>'step_id')::int
            WHERE s->>'code' = 'external_idents' AND idc->>'purpose' = 'source_input'
        ) AS idc;

        v_sql := format($SQL$
            WITH batch AS (
                SELECT dt.row_id,
                       dt.valid_from,
                       dt.valid_to,
                       dt.valid_until,
                       NULLIF(dt.birth_date_raw, '') AS birth_date_raw,
                       NULLIF(dt.death_date_raw, '') AS death_date_raw,
                       %4$s AS unit_name,
                       NULLIF(%5$s, '') AS ident_label
                FROM public.%1$I AS dt
                WHERE dt.batch_seq = $1
                  AND dt.action IS DISTINCT FROM 'skip'
            ),
            distinct_dates AS (
                SELECT birth_date_raw AS date_string FROM batch WHERE birth_date_raw IS NOT NULL
                UNION
                SELECT death_date_raw AS date_string FROM batch WHERE death_date_raw IS NOT NULL
            ),
            -- The same cast the core unit step uses later. An unparseable date is
            -- NULL here; reporting it is the core step's job (a warning), not ours.
            cast_dates AS MATERIALIZED (
                SELECT dd.date_string, sc.p_value
                FROM distinct_dates AS dd
                LEFT JOIN LATERAL import.safe_cast_to_date(dd.date_string) AS sc ON TRUE
            ),
            checked AS (
                SELECT b.*,
                       bd.p_value AS birth_date,
                       dd.p_value AS death_date,
                       (bd.p_value IS NOT NULL AND b.valid_until IS NOT NULL AND bd.p_value >= b.valid_until) AS born_after_window,
                       -- f2gx3m: a unit valid from a year is born in that year or before it.
                       (bd.p_value IS NOT NULL AND b.valid_from IS NOT NULL AND bd.p_value < b.valid_until
                        AND extract(year FROM b.valid_from) < extract(year FROM bd.p_value)) AS born_in_later_year,
                       (dd.p_value IS NOT NULL AND b.valid_from IS NOT NULL AND dd.p_value <= b.valid_from) AS died_before_window
                FROM batch AS b
                LEFT JOIN cast_dates AS bd ON bd.date_string = b.birth_date_raw
                LEFT JOIN cast_dates AS dd ON dd.date_string = b.death_date_raw
            ),
            described AS (
                SELECT c.*,
                       format('%2$s %%s%%s', quote_literal(c.unit_name), CASE WHEN c.ident_label IS NULL THEN '' ELSE ' (' || c.ident_label || ')' END) AS unit_text,
                       c.valid_from::TEXT || ' to ' || CASE WHEN c.valid_to = 'infinity'::date THEN 'infinity' ELSE c.valid_to::TEXT END
                           || ' (valid until ' || CASE WHEN c.valid_until = 'infinity'::date THEN 'infinity' ELSE c.valid_until::TEXT END || ')' AS window_text
                FROM checked AS c
            ),
            messages AS (
                SELECT d.row_id,
                       (d.born_after_window OR d.born_in_later_year) AS born_after_window,
                       d.died_before_window,
                       CASE WHEN d.born_in_later_year AND NOT d.born_after_window THEN
                           'Row ' || d.row_id || ': ' || d.unit_text || ' was born ' || d.birth_date::TEXT
                           || ', in a later year than this row''s valid_from ' || d.valid_from::TEXT
                           || '. A unit valid from a year is born in that year or before it. Correct the birth date or valid_from.'
                       END AS later_year_message,
                       CASE WHEN d.born_after_window THEN
                           'Row ' || d.row_id || ': ' || d.unit_text || ' was born ' || d.birth_date::TEXT
                           || ', on or after the end of this row''s validity period ' || d.window_text
                           || ', so the unit cannot exist in that period. Correct the birth date or the period.'
                       END AS birth_message,
                       CASE WHEN d.died_before_window THEN
                           'Row ' || d.row_id || ': ' || d.unit_text || ' died ' || d.death_date::TEXT
                           || ', on or before the start of this row''s validity period ' || d.window_text
                           || ', so the unit cannot exist in that period. Correct the death date or the period.'
                       END AS death_message
                FROM described AS d
            )
            UPDATE public.%1$I AS dt SET
                state = CASE
                            WHEN m.born_after_window OR m.died_before_window THEN 'error'::public.import_data_state
                            ELSE dt.state
                        END,
                action = CASE
                            WHEN m.born_after_window OR m.died_before_window THEN 'skip'::public.import_row_action_type
                            ELSE dt.action
                         END,
                errors = (COALESCE(dt.errors, '{}'::jsonb) - %3$L::TEXT[])
                         || jsonb_strip_nulls(jsonb_build_object(
                                'birth_date_raw', COALESCE(m.birth_message, m.later_year_message),
                                'valid_to_raw',   m.birth_message,
                                'death_date_raw', m.death_message,
                                'valid_from_raw', COALESCE(m.death_message, m.later_year_message)
                            )),
                last_completed_priority = %6$L
            FROM messages AS m
            WHERE dt.row_id = m.row_id;
        $SQL$,
            v_data_table_name                                                       /* %1$I */,
            v_unit_label                                                            /* %2$s */,
            v_error_keys_arr                                                        /* %3$L */,
            CASE WHEN v_has_name THEN 'NULLIF(trim(dt.name_raw), '''')' ELSE 'NULL::TEXT' END /* %4$s */,
            v_ident_label_expr                                                      /* %5$s */,
            v_step.priority                                                         /* %6$L */
        );
        RAISE DEBUG '[Job %] analyse_date_consistency: batch UPDATE SQL: %', p_job_id, v_sql;

        BEGIN
            EXECUTE v_sql USING p_batch_seq;
            GET DIAGNOSTICS v_update_count = ROW_COUNT;
            RAISE DEBUG '[Job %] analyse_date_consistency: checked % rows in batch_seq %', p_job_id, v_update_count, p_batch_seq;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING '[Job %] analyse_date_consistency: error during batch update: %', p_job_id, SQLERRM;
            UPDATE public.import_job
            SET error = jsonb_build_object('analyse_date_consistency_batch_error', SQLERRM)::TEXT,
                state = 'failed'
            WHERE id = p_job_id;
            RETURN;
        END;
    ELSE
        RAISE DEBUG '[Job %] analyse_date_consistency: no birth_date_raw/death_date_raw columns; advancing priority only', p_job_id;
    END IF;

    -- Always advance every row of the batch, including rows already skipped by
    -- an earlier step, so the analysis pipeline cannot loop.
    v_sql := format($adv$
        UPDATE public.%1$I AS dt SET last_completed_priority = %2$L
        WHERE dt.batch_seq = $1 AND dt.last_completed_priority < %2$L
    $adv$, v_data_table_name /* %1$I */, v_step.priority /* %2$L */);
    EXECUTE v_sql USING p_batch_seq;

    RAISE DEBUG '[Job %] analyse_date_consistency (Batch): Finished for batch_seq %', p_job_id, p_batch_seq;
END;
$procedure$
;

CREATE OR REPLACE VIEW public.legal_unit_establishment_stat_comparison
WITH (security_invoker = on) AS
 WITH establishment_values AS (
         SELECT su_1.hash_slot,
            su_1.unit_id,
            su_1.valid_from,
            sd.code AS stat_code,
            count(*) AS establishment_count,
            count(te.stats -> sd.code::text) AS establishments_with_value,
            sum(((te.stats -> sd.code::text) ->> 'value'::text)::numeric) AS establishments_sum
           FROM statistical_unit su_1
             JOIN timeline_establishment te ON te.legal_unit_id = su_1.unit_id AND te.used_for_counting AND te.valid_from <= su_1.valid_from AND su_1.valid_from < te.valid_until
             JOIN stat_definition sd ON sd.enabled AND (sd.type = ANY (ARRAY['int'::stat_type, 'float'::stat_type])) AND sd.lu_es_rollup = 'max'::lu_es_rollup
          WHERE su_1.unit_type = 'legal_unit'::statistical_unit_type AND su_1.stats ? sd.code::text
          GROUP BY su_1.hash_slot, su_1.unit_id, su_1.valid_from, sd.code
        )
 SELECT su.unit_type,
    su.unit_id,
    su.valid_from,
    su.valid_until,
    ev.stat_code,
    ((su.stats -> ev.stat_code::text) ->> 'value'::text)::numeric AS legal_unit_value,
    ev.establishment_count,
    ev.establishments_with_value,
    ev.establishments_sum,
    ev.hash_slot
   FROM statistical_unit su
     JOIN establishment_values ev ON ev.hash_slot = su.hash_slot AND ev.unit_id = su.unit_id AND ev.valid_from = su.valid_from
  WHERE su.unit_type = 'legal_unit'::statistical_unit_type AND ev.establishments_with_value > 0;
COMMENT ON VIEW public.legal_unit_establishment_stat_comparison IS
  'Per legal_unit row of statistical_unit and enabled summed stat (int, float) whose lu_es_rollup is max, held both by the legal unit and by at least one counted establishment: the legal unit''s own value (statistical_unit.stats) and its counted establishments'' count, count with a value, and sum at the row''s valid_from. The quality rules establishments_above_legal_unit and legal_unit_above_establishments read it (public.quality_finding_def); under max a legal unit''s total takes the larger level, so the levels disagreeing is worth a look. Under sum the levels add and the checks do not apply (s465ff).';

CREATE OR REPLACE VIEW public.quality_check
WITH (security_invoker = on) AS
 WITH check_of AS (
         SELECT r.rule,
            NULL::integer AS stat_definition_id,
            0 AS stat_priority
           FROM unnest(enum_range(NULL::quality_rule)) r(rule)
          WHERE NOT quality_rule_per_stat(r.rule)
        UNION ALL
         SELECT r.rule,
            sd.id,
            sd.priority
           FROM unnest(enum_range(NULL::quality_rule)) r(rule)
             JOIN stat_definition sd ON sd.enabled AND (sd.type = ANY (ARRAY['int'::stat_type, 'float'::stat_type])) AND sd.lu_es_rollup = 'max'::lu_es_rollup
          WHERE quality_rule_per_stat(r.rule)
        )
 SELECT rule,
    stat_definition_id,
    (EXISTS ( SELECT 1
           FROM quality_check_switched_on qs
          WHERE qs.rule = c.rule AND COALESCE(qs.stat_definition_id, 0) = COALESCE(c.stat_definition_id, 0))) AS on_dashboard,
    row_number() OVER (ORDER BY rule, stat_priority, stat_definition_id) AS priority
   FROM check_of c;

CREATE FUNCTION admin.stat_definition_lu_es_rollup_recalculate()
RETURNS trigger
LANGUAGE plpgsql
AS $stat_definition_lu_es_rollup_recalculate$
BEGIN
    -- Every legal unit total and the totals above it follow the changed rule: one full derive.
    IF EXISTS (SELECT 1 FROM old_rows AS o JOIN new_rows AS n ON n.id = o.id
               WHERE o.lu_es_rollup IS DISTINCT FROM n.lu_es_rollup) THEN
        PERFORM worker.enqueue_derive_statistical_unit_all();
    END IF;
    RETURN NULL;
END;
$stat_definition_lu_es_rollup_recalculate$;

COMMENT ON FUNCTION admin.stat_definition_lu_es_rollup_recalculate() IS
  'Recalculates the stored totals when a variable''s lu_es_rollup changes (s465ff): enqueues a full derive (worker.enqueue_derive_statistical_unit_all) once per statement that changed it.';

CREATE TRIGGER stat_definition_lu_es_rollup_recalculate
AFTER UPDATE ON public.stat_definition
REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows
FOR EACH STATEMENT EXECUTE FUNCTION admin.stat_definition_lu_es_rollup_recalculate();

SELECT worker.enqueue_derive_statistical_unit_all();

END;
