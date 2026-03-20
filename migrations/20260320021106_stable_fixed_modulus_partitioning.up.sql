-- Migration: Stable Fixed-Modulus Partitioning
--
-- Replaces dynamic analytics_partition_count (4/8/16/32/64/128 based on data size)
-- with a fixed modulus of 256. This eliminates the repartitioning stall that occurs
-- when crossing size thresholds (e.g., 2M units → 13+ minute UPDATE of all rows).
--
-- Two-layer design:
--   Layer 1: Slot assignment (permanent) — hash % 256, never changes
--   Layer 2: Batch grouping (adaptive at spawn time) — group slots into ranges
--
-- See plan: .claude/plans/quirky-bouncing-yao.md
BEGIN;

------------------------------------------------------------
-- Phase 1: Drop dynamic partition infrastructure
------------------------------------------------------------

DROP TRIGGER trg_settings_partition_count_change ON public.settings;
DROP FUNCTION admin.propagate_partition_count_change();
DROP PROCEDURE admin.adjust_analytics_partition_count();
ALTER TABLE public.settings DROP COLUMN analytics_partition_count;

------------------------------------------------------------
-- Phase 2: Replace hash functions (3-arg → 2-arg, hardcode 256)
------------------------------------------------------------

DROP FUNCTION public.report_partition_seq(text, int, int);
DROP FUNCTION public.report_partition_seq(statistical_unit_type, int, int);

-- Fixed modulus 256: slot assignment is permanent, never changes regardless of data size.
-- 256 chosen because: power of 2 (uniform distribution), 256/4 = 64 max children (good parallelism),
-- even 50k datasets populate ~180 of 256 slots (low waste).
CREATE FUNCTION public.report_partition_seq(p_unit_type text, p_unit_id int)
RETURNS int
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
AS $report_partition_seq$
    SELECT abs(hashtext(p_unit_type || ':' || p_unit_id::text)) % 256;
$report_partition_seq$;

CREATE FUNCTION public.report_partition_seq(p_unit_type statistical_unit_type, p_unit_id int)
RETURNS int
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
AS $report_partition_seq$
    SELECT abs(hashtext(p_unit_type::text || ':' || p_unit_id::text)) % 256;
$report_partition_seq$;

------------------------------------------------------------
-- Phase 3: Update trigger function (no more settings lookup)
------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.set_report_partition_seq()
RETURNS trigger
LANGUAGE plpgsql
AS $set_report_partition_seq$
BEGIN
    NEW.report_partition_seq := public.report_partition_seq(NEW.unit_type, NEW.unit_id);
    RETURN NEW;
END;
$set_report_partition_seq$;

------------------------------------------------------------
-- Phase 4: Update derive_reports_phase (remove adjust call)
------------------------------------------------------------

CREATE OR REPLACE PROCEDURE worker.derive_reports_phase(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, worker, pg_temp
AS $derive_reports_phase$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
BEGIN
    PERFORM pg_notify('worker_status',
        json_build_object('type', 'is_deriving_reports', 'status', true)::text);
    -- Partition count is now fixed at 256 — no dynamic adjustment needed.
    -- (Removed: CALL admin.adjust_analytics_partition_count())

    p_info := jsonb_build_object(
        'valid_from', v_valid_from,
        'valid_until', v_valid_until
    );
    -- Add year count only when both dates are finite
    IF isfinite(v_valid_from) AND isfinite(v_valid_until) THEN
        p_info := p_info || jsonb_build_object(
            'years', EXTRACT(YEAR FROM v_valid_until)::int - EXTRACT(YEAR FROM v_valid_from)::int
        );
    END IF;
END;
$derive_reports_phase$;

------------------------------------------------------------
-- Phase 5: Update import.get_statistical_unit_data_partial
-- (replace 3-arg report_partition_seq with 2-arg)
------------------------------------------------------------

CREATE OR REPLACE FUNCTION import.get_statistical_unit_data_partial(p_unit_type statistical_unit_type, p_id_ranges int4multirange)
RETURNS SETOF statistical_unit
LANGUAGE plpgsql
STABLE
AS $get_statistical_unit_data_partial$
DECLARE
    v_ids INT[] := public.int4multirange_to_array(p_id_ranges);
BEGIN
    IF p_unit_type = 'establishment' THEN
        RETURN QUERY
        SELECT t.unit_type, t.unit_id, t.valid_from, t.valid_to, t.valid_until,
            COALESCE(eia1.external_idents, '{}'::jsonb) AS external_idents,
            t.name, t.birth_date, t.death_date, t.search,
            t.primary_activity_category_id, t.primary_activity_category_path, t.primary_activity_category_code,
            t.secondary_activity_category_id, t.secondary_activity_category_path, t.secondary_activity_category_code,
            t.activity_category_paths, t.sector_id, t.sector_path, t.sector_code, t.sector_name,
            t.data_source_ids, t.data_source_codes, t.legal_form_id, t.legal_form_code, t.legal_form_name,
            t.physical_address_part1, t.physical_address_part2, t.physical_address_part3, t.physical_postcode, t.physical_postplace,
            t.physical_region_id, t.physical_region_path, t.physical_region_code, t.physical_country_id, t.physical_country_iso_2,
            t.physical_latitude, t.physical_longitude, t.physical_altitude, t.domestic,
            t.postal_address_part1, t.postal_address_part2, t.postal_address_part3, t.postal_postcode, t.postal_postplace,
            t.postal_region_id, t.postal_region_path, t.postal_region_code, t.postal_country_id, t.postal_country_iso_2,
            t.postal_latitude, t.postal_longitude, t.postal_altitude,
            t.web_address, t.email_address, t.phone_number, t.landline, t.mobile_number, t.fax_number,
            t.unit_size_id, t.unit_size_code, t.status_id, t.status_code, t.used_for_counting,
            t.last_edit_comment, t.last_edit_by_user_id, t.last_edit_at, t.has_legal_unit,
            t.related_establishment_ids, t.excluded_establishment_ids, t.included_establishment_ids,
            t.related_legal_unit_ids, t.excluded_legal_unit_ids, t.included_legal_unit_ids,
            t.related_enterprise_ids, t.excluded_enterprise_ids, t.included_enterprise_ids,
            t.stats, t.stats_summary,
            array_length(t.included_establishment_ids, 1) AS included_establishment_count,
            array_length(t.included_legal_unit_ids, 1) AS included_legal_unit_count,
            array_length(t.included_enterprise_ids, 1) AS included_enterprise_count,
            COALESCE(tpa.tag_paths, ARRAY[]::public.ltree[]) AS tag_paths,
            daterange(t.valid_from, t.valid_until) AS valid_range,
            public.report_partition_seq(t.unit_type, t.unit_id) AS report_partition_seq
        FROM public.timeline_establishment t
        LEFT JOIN LATERAL (SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents FROM public.external_ident ei JOIN public.external_ident_type eit ON ei.type_id = eit.id WHERE ei.establishment_id = t.unit_id) eia1 ON true
        LEFT JOIN LATERAL (SELECT array_agg(tag.path ORDER BY tag.path) AS tag_paths FROM public.tag_for_unit tfu JOIN public.tag ON tfu.tag_id = tag.id WHERE tfu.establishment_id = t.unit_id) tpa ON true
        WHERE t.unit_id = ANY(v_ids);

    ELSIF p_unit_type = 'legal_unit' THEN
        RETURN QUERY
        SELECT t.unit_type, t.unit_id, t.valid_from, t.valid_to, t.valid_until,
            COALESCE(eia1.external_idents, '{}'::jsonb) AS external_idents,
            t.name, t.birth_date, t.death_date, t.search,
            t.primary_activity_category_id, t.primary_activity_category_path, t.primary_activity_category_code,
            t.secondary_activity_category_id, t.secondary_activity_category_path, t.secondary_activity_category_code,
            t.activity_category_paths, t.sector_id, t.sector_path, t.sector_code, t.sector_name,
            t.data_source_ids, t.data_source_codes, t.legal_form_id, t.legal_form_code, t.legal_form_name,
            t.physical_address_part1, t.physical_address_part2, t.physical_address_part3, t.physical_postcode, t.physical_postplace,
            t.physical_region_id, t.physical_region_path, t.physical_region_code, t.physical_country_id, t.physical_country_iso_2,
            t.physical_latitude, t.physical_longitude, t.physical_altitude, t.domestic,
            t.postal_address_part1, t.postal_address_part2, t.postal_address_part3, t.postal_postcode, t.postal_postplace,
            t.postal_region_id, t.postal_region_path, t.postal_region_code, t.postal_country_id, t.postal_country_iso_2,
            t.postal_latitude, t.postal_longitude, t.postal_altitude,
            t.web_address, t.email_address, t.phone_number, t.landline, t.mobile_number, t.fax_number,
            t.unit_size_id, t.unit_size_code, t.status_id, t.status_code, t.used_for_counting,
            t.last_edit_comment, t.last_edit_by_user_id, t.last_edit_at, t.has_legal_unit,
            t.related_establishment_ids, t.excluded_establishment_ids, t.included_establishment_ids,
            t.related_legal_unit_ids, t.excluded_legal_unit_ids, t.included_legal_unit_ids,
            t.related_enterprise_ids, t.excluded_enterprise_ids, t.included_enterprise_ids,
            t.stats, t.stats_summary,
            array_length(t.included_establishment_ids, 1) AS included_establishment_count,
            array_length(t.included_legal_unit_ids, 1) AS included_legal_unit_count,
            array_length(t.included_enterprise_ids, 1) AS included_enterprise_count,
            COALESCE(tpa.tag_paths, ARRAY[]::public.ltree[]) AS tag_paths,
            daterange(t.valid_from, t.valid_until) AS valid_range,
            public.report_partition_seq(t.unit_type, t.unit_id) AS report_partition_seq
        FROM public.timeline_legal_unit t
        LEFT JOIN LATERAL (SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents FROM public.external_ident ei JOIN public.external_ident_type eit ON ei.type_id = eit.id WHERE ei.legal_unit_id = t.unit_id) eia1 ON true
        LEFT JOIN LATERAL (SELECT array_agg(tag.path ORDER BY tag.path) AS tag_paths FROM public.tag_for_unit tfu JOIN public.tag ON tfu.tag_id = tag.id WHERE tfu.legal_unit_id = t.unit_id) tpa ON true
        WHERE t.unit_id = ANY(v_ids);

    ELSIF p_unit_type = 'enterprise' THEN
        RETURN QUERY
        SELECT t.unit_type, t.unit_id, t.valid_from, t.valid_to, t.valid_until,
            COALESCE(eia1.external_idents, eia2.external_idents, eia3.external_idents, '{}'::jsonb) AS external_idents,
            t.name::varchar, t.birth_date, t.death_date, t.search,
            t.primary_activity_category_id, t.primary_activity_category_path, t.primary_activity_category_code,
            t.secondary_activity_category_id, t.secondary_activity_category_path, t.secondary_activity_category_code,
            t.activity_category_paths, t.sector_id, t.sector_path, t.sector_code, t.sector_name,
            t.data_source_ids, t.data_source_codes, t.legal_form_id, t.legal_form_code, t.legal_form_name,
            t.physical_address_part1, t.physical_address_part2, t.physical_address_part3, t.physical_postcode, t.physical_postplace,
            t.physical_region_id, t.physical_region_path, t.physical_region_code, t.physical_country_id, t.physical_country_iso_2,
            t.physical_latitude, t.physical_longitude, t.physical_altitude, t.domestic,
            t.postal_address_part1, t.postal_address_part2, t.postal_address_part3, t.postal_postcode, t.postal_postplace,
            t.postal_region_id, t.postal_region_path, t.postal_region_code, t.postal_country_id, t.postal_country_iso_2,
            t.postal_latitude, t.postal_longitude, t.postal_altitude,
            t.web_address, t.email_address, t.phone_number, t.landline, t.mobile_number, t.fax_number,
            t.unit_size_id, t.unit_size_code, t.status_id, t.status_code, t.used_for_counting,
            t.last_edit_comment, t.last_edit_by_user_id, t.last_edit_at, t.has_legal_unit,
            t.related_establishment_ids, t.excluded_establishment_ids, t.included_establishment_ids,
            t.related_legal_unit_ids, t.excluded_legal_unit_ids, t.included_legal_unit_ids,
            t.related_enterprise_ids, t.excluded_enterprise_ids, t.included_enterprise_ids,
            NULL::JSONB AS stats, t.stats_summary,
            array_length(t.included_establishment_ids, 1) AS included_establishment_count,
            array_length(t.included_legal_unit_ids, 1) AS included_legal_unit_count,
            array_length(t.included_enterprise_ids, 1) AS included_enterprise_count,
            COALESCE(tpa.tag_paths, ARRAY[]::public.ltree[]) AS tag_paths,
            daterange(t.valid_from, t.valid_until) AS valid_range,
            public.report_partition_seq(t.unit_type, t.unit_id) AS report_partition_seq
        FROM public.timeline_enterprise t
        LEFT JOIN LATERAL (SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents FROM public.external_ident ei JOIN public.external_ident_type eit ON ei.type_id = eit.id WHERE ei.enterprise_id = t.unit_id) eia1 ON true
        LEFT JOIN LATERAL (SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents FROM public.external_ident ei JOIN public.external_ident_type eit ON ei.type_id = eit.id WHERE ei.establishment_id = t.primary_establishment_id) eia2 ON true
        LEFT JOIN LATERAL (SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents FROM public.external_ident ei JOIN public.external_ident_type eit ON ei.type_id = eit.id WHERE ei.legal_unit_id = t.primary_legal_unit_id) eia3 ON true
        LEFT JOIN LATERAL (SELECT array_agg(tag.path ORDER BY tag.path) AS tag_paths FROM public.tag_for_unit tfu JOIN public.tag ON tfu.tag_id = tag.id WHERE tfu.enterprise_id = t.unit_id) tpa ON true
        WHERE t.unit_id = ANY(v_ids);

    ELSIF p_unit_type = 'power_group' THEN
        RETURN QUERY
        SELECT t.unit_type, t.unit_id, t.valid_from, t.valid_to, t.valid_until,
            COALESCE(eia1.external_idents, '{}'::jsonb) AS external_idents,
            t.name::varchar, t.birth_date, t.death_date, t.search,
            t.primary_activity_category_id, t.primary_activity_category_path, t.primary_activity_category_code,
            t.secondary_activity_category_id, t.secondary_activity_category_path, t.secondary_activity_category_code,
            t.activity_category_paths, t.sector_id, t.sector_path, t.sector_code, t.sector_name,
            t.data_source_ids, t.data_source_codes, t.legal_form_id, t.legal_form_code, t.legal_form_name,
            t.physical_address_part1, t.physical_address_part2, t.physical_address_part3, t.physical_postcode, t.physical_postplace,
            t.physical_region_id, t.physical_region_path, t.physical_region_code, t.physical_country_id, t.physical_country_iso_2,
            t.physical_latitude, t.physical_longitude, t.physical_altitude, t.domestic,
            t.postal_address_part1, t.postal_address_part2, t.postal_address_part3, t.postal_postcode, t.postal_postplace,
            t.postal_region_id, t.postal_region_path, t.postal_region_code, t.postal_country_id, t.postal_country_iso_2,
            t.postal_latitude, t.postal_longitude, t.postal_altitude,
            t.web_address, t.email_address, t.phone_number, t.landline, t.mobile_number, t.fax_number,
            t.unit_size_id, t.unit_size_code, t.status_id, t.status_code, t.used_for_counting,
            t.last_edit_comment, t.last_edit_by_user_id, t.last_edit_at, t.has_legal_unit,
            t.related_establishment_ids, t.excluded_establishment_ids, t.included_establishment_ids,
            t.related_legal_unit_ids, t.excluded_legal_unit_ids, t.included_legal_unit_ids,
            t.related_enterprise_ids, t.excluded_enterprise_ids, t.included_enterprise_ids,
            NULL::JSONB AS stats, t.stats_summary,
            array_length(t.included_establishment_ids, 1) AS included_establishment_count,
            array_length(t.included_legal_unit_ids, 1) AS included_legal_unit_count,
            array_length(t.included_enterprise_ids, 1) AS included_enterprise_count,
            COALESCE(tpa.tag_paths, ARRAY[]::public.ltree[]) AS tag_paths,
            daterange(t.valid_from, t.valid_until) AS valid_range,
            public.report_partition_seq(t.unit_type, t.unit_id) AS report_partition_seq
        FROM public.timeline_power_group t
        LEFT JOIN LATERAL (SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents FROM public.external_ident ei JOIN public.external_ident_type eit ON ei.type_id = eit.id WHERE ei.power_group_id = t.power_group_id) eia1 ON true
        LEFT JOIN LATERAL (SELECT array_agg(tag.path ORDER BY tag.path) AS tag_paths FROM public.tag_for_unit tfu JOIN public.tag ON tfu.tag_id = tag.id WHERE tfu.power_group_id = t.power_group_id) tpa ON true
        WHERE t.unit_id = ANY(v_ids);
    END IF;
END;
$get_statistical_unit_data_partial$;

------------------------------------------------------------
-- Phase 6: Update derive_statistical_unit function
-- (replace settings queries with constant 256, adaptive power group batching)
------------------------------------------------------------

CREATE OR REPLACE FUNCTION worker.derive_statistical_unit(
    p_establishment_id_ranges int4multirange DEFAULT NULL,
    p_legal_unit_id_ranges int4multirange DEFAULT NULL,
    p_enterprise_id_ranges int4multirange DEFAULT NULL,
    p_power_group_id_ranges int4multirange DEFAULT NULL,
    p_valid_from date DEFAULT NULL,
    p_valid_until date DEFAULT NULL,
    p_task_id bigint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
AS $derive_statistical_unit$
DECLARE
    v_batch RECORD;
    v_establishment_ids INT[];
    v_legal_unit_ids INT[];
    v_enterprise_ids INT[];
    v_power_group_ids INT[];
    v_batch_count INT := 0;
    v_is_full_refresh BOOLEAN;
    v_orphan_enterprise_ids INT[];
    v_orphan_legal_unit_ids INT[];
    v_orphan_establishment_ids INT[];
    v_orphan_power_group_ids INT[];
    v_enterprise_count INT := 0;
    v_legal_unit_count INT := 0;
    v_establishment_count INT := 0;
    v_power_group_count INT := 0;
    -- Adaptive power group batching: target ~64 batches for large datasets
    v_pg_batch_size INT;
BEGIN
    v_is_full_refresh := (p_establishment_id_ranges IS NULL
                         AND p_legal_unit_id_ranges IS NULL
                         AND p_enterprise_id_ranges IS NULL
                         AND p_power_group_id_ranges IS NULL);

    IF v_is_full_refresh THEN
        FOR v_batch IN SELECT * FROM public.get_closed_group_batches(p_target_batch_size => 1000)
        LOOP
            v_enterprise_count := v_enterprise_count + COALESCE(array_length(v_batch.enterprise_ids, 1), 0);
            v_legal_unit_count := v_legal_unit_count + COALESCE(array_length(v_batch.legal_unit_ids, 1), 0);
            v_establishment_count := v_establishment_count + COALESCE(array_length(v_batch.establishment_ids, 1), 0);

            PERFORM worker.spawn(
                p_command => 'statistical_unit_refresh_batch',
                p_payload => jsonb_build_object(
                    'command', 'statistical_unit_refresh_batch',
                    'batch_seq', v_batch.batch_seq,
                    'enterprise_ids', v_batch.enterprise_ids,
                    'legal_unit_ids', v_batch.legal_unit_ids,
                    'establishment_ids', v_batch.establishment_ids,
                    'valid_from', p_valid_from,
                    'valid_until', p_valid_until
                ),
                p_parent_id => p_task_id
            );
            v_batch_count := v_batch_count + 1;
        END LOOP;

        v_power_group_ids := ARRAY(SELECT id FROM public.power_group ORDER BY id);
        v_power_group_count := COALESCE(array_length(v_power_group_ids, 1), 0);
        IF v_power_group_count > 0 THEN
            -- Adaptive batch size: target ~64 batches max, minimum 1 per batch
            v_pg_batch_size := GREATEST(1, ceil(v_power_group_count::numeric / 64));
            FOR v_batch IN
                SELECT array_agg(pg_id ORDER BY pg_id) AS pg_ids
                FROM (SELECT pg_id, ((row_number() OVER (ORDER BY pg_id)) - 1) / v_pg_batch_size AS batch_idx
                      FROM unnest(v_power_group_ids) AS pg_id) AS t
                GROUP BY batch_idx ORDER BY batch_idx
            LOOP
                PERFORM worker.spawn(
                    p_command => 'statistical_unit_refresh_batch',
                    p_payload => jsonb_build_object(
                        'command', 'statistical_unit_refresh_batch',
                        'batch_seq', v_batch_count + 1,
                        'power_group_ids', v_batch.pg_ids,
                        'valid_from', p_valid_from,
                        'valid_until', p_valid_until
                    ),
                    p_parent_id => p_task_id
                );
                v_batch_count := v_batch_count + 1;
            END LOOP;
        END IF;
    ELSE
        v_establishment_ids := ARRAY(SELECT generate_series(lower(r), upper(r)-1) FROM unnest(COALESCE(p_establishment_id_ranges, '{}'::int4multirange)) AS t(r));
        v_legal_unit_ids := ARRAY(SELECT generate_series(lower(r), upper(r)-1) FROM unnest(COALESCE(p_legal_unit_id_ranges, '{}'::int4multirange)) AS t(r));
        v_enterprise_ids := ARRAY(SELECT generate_series(lower(r), upper(r)-1) FROM unnest(COALESCE(p_enterprise_id_ranges, '{}'::int4multirange)) AS t(r));
        v_power_group_ids := ARRAY(SELECT generate_series(lower(r), upper(r)-1) FROM unnest(COALESCE(p_power_group_id_ranges, '{}'::int4multirange)) AS t(r));

        -- ORPHAN CLEANUP
        IF COALESCE(array_length(v_enterprise_ids, 1), 0) > 0 THEN
            v_orphan_enterprise_ids := ARRAY(SELECT id FROM unnest(v_enterprise_ids) AS id EXCEPT SELECT e.id FROM public.enterprise AS e WHERE e.id = ANY(v_enterprise_ids));
            IF COALESCE(array_length(v_orphan_enterprise_ids, 1), 0) > 0 THEN
                DELETE FROM public.timepoints WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.timeline_enterprise WHERE enterprise_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
            END IF;
        END IF;
        IF COALESCE(array_length(v_legal_unit_ids, 1), 0) > 0 THEN
            v_orphan_legal_unit_ids := ARRAY(SELECT id FROM unnest(v_legal_unit_ids) AS id EXCEPT SELECT lu.id FROM public.legal_unit AS lu WHERE lu.id = ANY(v_legal_unit_ids));
            IF COALESCE(array_length(v_orphan_legal_unit_ids, 1), 0) > 0 THEN
                DELETE FROM public.timepoints WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.timeline_legal_unit WHERE legal_unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
            END IF;
        END IF;
        IF COALESCE(array_length(v_establishment_ids, 1), 0) > 0 THEN
            v_orphan_establishment_ids := ARRAY(SELECT id FROM unnest(v_establishment_ids) AS id EXCEPT SELECT es.id FROM public.establishment AS es WHERE es.id = ANY(v_establishment_ids));
            IF COALESCE(array_length(v_orphan_establishment_ids, 1), 0) > 0 THEN
                DELETE FROM public.timepoints WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.timeline_establishment WHERE establishment_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
            END IF;
        END IF;
        IF COALESCE(array_length(v_power_group_ids, 1), 0) > 0 THEN
            v_orphan_power_group_ids := ARRAY(SELECT id FROM unnest(v_power_group_ids) AS id EXCEPT SELECT pg.id FROM public.power_group AS pg WHERE pg.id = ANY(v_power_group_ids));
            IF COALESCE(array_length(v_orphan_power_group_ids, 1), 0) > 0 THEN
                DELETE FROM public.timepoints WHERE unit_type = 'power_group' AND unit_id = ANY(v_orphan_power_group_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'power_group' AND unit_id = ANY(v_orphan_power_group_ids);
                DELETE FROM public.timeline_power_group WHERE power_group_id = ANY(v_orphan_power_group_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'power_group' AND unit_id = ANY(v_orphan_power_group_ids);
            END IF;
        END IF;

        IF p_establishment_id_ranges IS NOT NULL
           OR p_legal_unit_id_ranges IS NOT NULL
           OR p_enterprise_id_ranges IS NOT NULL THEN
            IF to_regclass('pg_temp._batches') IS NOT NULL THEN DROP TABLE _batches; END IF;
            CREATE TEMP TABLE _batches ON COMMIT DROP AS
            SELECT * FROM public.get_closed_group_batches(
                p_target_batch_size => 1000,
                p_establishment_id_ranges => NULLIF(p_establishment_id_ranges, '{}'::int4multirange),
                p_legal_unit_id_ranges => NULLIF(p_legal_unit_id_ranges, '{}'::int4multirange),
                p_enterprise_id_ranges => NULLIF(p_enterprise_id_ranges, '{}'::int4multirange)
            );
            -- Fixed modulus 256: no settings lookup needed
            INSERT INTO public.statistical_unit_facet_dirty_partitions (partition_seq)
            SELECT DISTINCT public.report_partition_seq(t.unit_type, t.unit_id)
            FROM (
                SELECT 'enterprise'::text AS unit_type, unnest(b.enterprise_ids) AS unit_id FROM _batches AS b
                UNION ALL SELECT 'legal_unit', unnest(b.legal_unit_ids) FROM _batches AS b
                UNION ALL SELECT 'establishment', unnest(b.establishment_ids) FROM _batches AS b
            ) AS t WHERE t.unit_id IS NOT NULL
            ON CONFLICT DO NOTHING;

            <<effective_counts>>
            DECLARE
                v_all_batch_est_ranges int4multirange;
                v_all_batch_lu_ranges int4multirange;
                v_all_batch_en_ranges int4multirange;
                v_propagated_lu int4multirange;
                v_propagated_en int4multirange;
                v_eff_est int4multirange;
                v_eff_lu int4multirange;
                v_eff_en int4multirange;
            BEGIN
                v_all_batch_est_ranges := (SELECT range_agg(int4range(id, id, '[]'))
                    FROM (SELECT unnest(establishment_ids) AS id FROM _batches) AS t);
                v_all_batch_lu_ranges := (SELECT range_agg(int4range(id, id, '[]'))
                    FROM (SELECT unnest(legal_unit_ids) AS id FROM _batches) AS t);
                v_all_batch_en_ranges := (SELECT range_agg(int4range(id, id, '[]'))
                    FROM (SELECT unnest(enterprise_ids) AS id FROM _batches) AS t);

                v_eff_est := NULLIF(
                    COALESCE(v_all_batch_est_ranges, '{}'::int4multirange)
                    * COALESCE(p_establishment_id_ranges, '{}'::int4multirange),
                    '{}'::int4multirange);

                SELECT range_agg(int4range(es.legal_unit_id, es.legal_unit_id, '[]'))
                  INTO v_propagated_lu
                  FROM public.establishment AS es
                 WHERE es.id <@ COALESCE(p_establishment_id_ranges, '{}'::int4multirange)
                   AND es.legal_unit_id IS NOT NULL;
                v_eff_lu := NULLIF(
                    COALESCE(v_all_batch_lu_ranges, '{}'::int4multirange)
                    * (COALESCE(p_legal_unit_id_ranges, '{}'::int4multirange)
                     + COALESCE(v_propagated_lu, '{}'::int4multirange)),
                    '{}'::int4multirange);

                SELECT range_agg(int4range(lu.enterprise_id, lu.enterprise_id, '[]'))
                  INTO v_propagated_en
                  FROM public.legal_unit AS lu
                 WHERE lu.id <@ COALESCE(v_eff_lu, '{}'::int4multirange)
                   AND lu.enterprise_id IS NOT NULL;
                v_eff_en := NULLIF(
                    COALESCE(v_all_batch_en_ranges, '{}'::int4multirange)
                    * (COALESCE(p_enterprise_id_ranges, '{}'::int4multirange)
                     + COALESCE(v_propagated_en, '{}'::int4multirange)),
                    '{}'::int4multirange);

                v_establishment_count := COALESCE((SELECT count(*) FROM unnest(COALESCE(v_eff_est, '{}'::int4multirange)) AS r, generate_series(lower(r), upper(r)-1))::INT, 0);
                v_legal_unit_count := COALESCE((SELECT count(*) FROM unnest(COALESCE(v_eff_lu, '{}'::int4multirange)) AS r, generate_series(lower(r), upper(r)-1))::INT, 0);
                v_enterprise_count := COALESCE((SELECT count(*) FROM unnest(COALESCE(v_eff_en, '{}'::int4multirange)) AS r, generate_series(lower(r), upper(r)-1))::INT, 0);
            END effective_counts;

            FOR v_batch IN SELECT * FROM _batches LOOP
                PERFORM worker.spawn(
                    p_command => 'statistical_unit_refresh_batch',
                    p_payload => jsonb_build_object(
                        'command', 'statistical_unit_refresh_batch',
                        'batch_seq', v_batch.batch_seq,
                        'enterprise_ids', v_batch.enterprise_ids,
                        'legal_unit_ids', v_batch.legal_unit_ids,
                        'establishment_ids', v_batch.establishment_ids,
                        'valid_from', p_valid_from,
                        'valid_until', p_valid_until,
                        'changed_establishment_id_ranges', p_establishment_id_ranges::text,
                        'changed_legal_unit_id_ranges', p_legal_unit_id_ranges::text,
                        'changed_enterprise_id_ranges', p_enterprise_id_ranges::text
                    ),
                    p_parent_id => p_task_id
                );
                v_batch_count := v_batch_count + 1;
            END LOOP;
        END IF;

        IF COALESCE(array_length(v_power_group_ids, 1), 0) > 0 THEN
            v_power_group_count := array_length(v_power_group_ids, 1);
            -- Fixed modulus 256: no settings lookup needed
            INSERT INTO public.statistical_unit_facet_dirty_partitions (partition_seq)
            SELECT DISTINCT public.report_partition_seq('power_group', pg_id)
            FROM unnest(v_power_group_ids) AS pg_id
            ON CONFLICT DO NOTHING;

            -- Adaptive batch size: target ~64 batches max
            v_pg_batch_size := GREATEST(1, ceil(v_power_group_count::numeric / 64));
            FOR v_batch IN
                SELECT array_agg(pg_id ORDER BY pg_id) AS pg_ids
                FROM (SELECT pg_id, ((row_number() OVER (ORDER BY pg_id)) - 1) / v_pg_batch_size AS batch_idx
                      FROM unnest(v_power_group_ids) AS pg_id) AS t
                GROUP BY batch_idx ORDER BY batch_idx
            LOOP
                PERFORM worker.spawn(
                    p_command => 'statistical_unit_refresh_batch',
                    p_payload => jsonb_build_object(
                        'command', 'statistical_unit_refresh_batch',
                        'batch_seq', v_batch_count + 1,
                        'power_group_ids', v_batch.pg_ids,
                        'valid_from', p_valid_from,
                        'valid_until', p_valid_until
                    ),
                    p_parent_id => p_task_id
                );
                v_batch_count := v_batch_count + 1;
            END LOOP;
        END IF;
    END IF;

    RAISE DEBUG 'derive_statistical_unit: Spawned % batch children with parent_id %, counts: es=%, lu=%, en=%, pg=%',
        v_batch_count, p_task_id, v_establishment_count, v_legal_unit_count, v_enterprise_count, v_power_group_count;

    PERFORM public.activity_category_used_derive();
    PERFORM public.region_used_derive();
    PERFORM public.sector_used_derive();
    PERFORM public.data_source_used_derive();
    PERFORM public.legal_form_used_derive();
    PERFORM public.country_used_derive();

    -- Info Principle: report effective counts (post-propagation), not affected counts (raw change-log)
    RETURN jsonb_build_object(
        'effective_establishment_count', v_establishment_count,
        'effective_legal_unit_count', v_legal_unit_count,
        'effective_enterprise_count', v_enterprise_count,
        'effective_power_group_count', v_power_group_count,
        'batch_count', v_batch_count
    );
END;
$derive_statistical_unit$;

------------------------------------------------------------
-- Phase 7: Update spawner functions to use range-based children
-- Spawners now group adjacent slots into ranges instead of
-- spawning one child per individual slot.
------------------------------------------------------------

-- derive_statistical_unit_facet: range-based spawning
CREATE OR REPLACE PROCEDURE worker.derive_statistical_unit_facet(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, worker, pg_temp
AS $derive_statistical_unit_facet$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
    v_task_id bigint;
    v_dirty_partitions INT[];
    v_populated_partitions INT;
    v_expected_partitions INT;
    v_child_count INT := 0;
    -- Range-based spawning variables
    v_partitions_to_process INT[];
    v_target_children INT;
    v_range_size INT;
    v_range_start INT;
    v_range_end INT;
BEGIN
    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY id DESC LIMIT 1;

    RAISE DEBUG 'derive_statistical_unit_facet: task_id=%, valid_from=%, valid_until=%',
                 v_task_id, v_valid_from, v_valid_until;

    SELECT COUNT(DISTINCT partition_seq) INTO v_populated_partitions
    FROM public.statistical_unit_facet_staging;

    SELECT COUNT(DISTINCT report_partition_seq) INTO v_expected_partitions
    FROM public.statistical_unit
    WHERE used_for_counting;

    SELECT array_agg(partition_seq ORDER BY partition_seq) INTO v_dirty_partitions
    FROM public.statistical_unit_facet_dirty_partitions;

    IF v_populated_partitions < v_expected_partitions THEN
        v_dirty_partitions := NULL;
        RAISE DEBUG 'derive_statistical_unit_facet: Staging has %/% expected partitions populated, forcing full refresh',
            v_populated_partitions, v_expected_partitions;
    END IF;

    IF v_dirty_partitions IS NULL THEN
        -- Full refresh: get all populated partitions
        v_partitions_to_process := ARRAY(
            SELECT DISTINCT report_partition_seq
            FROM public.statistical_unit
            WHERE used_for_counting
            ORDER BY report_partition_seq
        );
    ELSE
        -- Partial refresh: use dirty partitions
        v_partitions_to_process := v_dirty_partitions;
    END IF;

    -- Adaptive range-based spawning: group adjacent slots into ranges.
    -- Target 4-64 children based on how many slots need processing.
    v_target_children := GREATEST(4, LEAST(64, ceil(COALESCE(array_length(v_partitions_to_process, 1), 0)::numeric / 4)));
    v_range_size := GREATEST(1, ceil(256.0 / v_target_children));

    FOR v_range_start IN 0..255 BY v_range_size LOOP
        v_range_end := LEAST(v_range_start + v_range_size - 1, 255);
        -- Only spawn if there are partitions in this range
        IF EXISTS (SELECT 1 FROM unnest(v_partitions_to_process) AS p WHERE p BETWEEN v_range_start AND v_range_end) THEN
            PERFORM worker.spawn(
                p_command => 'derive_statistical_unit_facet_partition',
                p_payload => jsonb_build_object(
                    'command', 'derive_statistical_unit_facet_partition',
                    'partition_seq_from', v_range_start,
                    'partition_seq_to', v_range_end
                ),
                p_parent_id => v_task_id
            );
            v_child_count := v_child_count + 1;
        END IF;
    END LOOP;

    RAISE DEBUG 'derive_statistical_unit_facet: Spawned % range children (range_size=%)',
        v_child_count, v_range_size;

    p_info := jsonb_build_object('child_count', v_child_count);
END;
$derive_statistical_unit_facet$;

-- derive_statistical_unit_facet_partition: accept range
CREATE OR REPLACE PROCEDURE worker.derive_statistical_unit_facet_partition(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, worker, pg_temp
AS $derive_statistical_unit_facet_partition$
DECLARE
    -- Support both single partition_seq (legacy/backward compat) and range
    v_partition_seq_from INT := COALESCE(
        (payload->>'partition_seq_from')::int,
        (payload->>'partition_seq')::int
    );
    v_partition_seq_to INT := COALESCE(
        (payload->>'partition_seq_to')::int,
        (payload->>'partition_seq')::int
    );
    v_row_count bigint;
BEGIN
    RAISE DEBUG 'derive_statistical_unit_facet_partition: partition_seq_from=%, partition_seq_to=%',
        v_partition_seq_from, v_partition_seq_to;

    DELETE FROM public.statistical_unit_facet_staging
    WHERE partition_seq BETWEEN v_partition_seq_from AND v_partition_seq_to;

    INSERT INTO public.statistical_unit_facet_staging
    SELECT su.report_partition_seq,
           su.valid_from, su.valid_to, su.valid_until, su.unit_type,
           su.physical_region_path, su.primary_activity_category_path,
           su.sector_path, su.legal_form_id, su.physical_country_id, su.status_id,
           COUNT(*)::INT,
           jsonb_stats_merge_agg(su.stats_summary)
    FROM public.statistical_unit AS su
    WHERE su.used_for_counting
      AND su.report_partition_seq BETWEEN v_partition_seq_from AND v_partition_seq_to
    GROUP BY su.report_partition_seq, su.valid_from, su.valid_to, su.valid_until, su.unit_type,
             su.physical_region_path, su.primary_activity_category_path,
             su.sector_path, su.legal_form_id, su.physical_country_id, su.status_id;
    GET DIAGNOSTICS v_row_count := ROW_COUNT;

    RAISE DEBUG 'derive_statistical_unit_facet_partition: range [%, %] done, % rows',
        v_partition_seq_from, v_partition_seq_to, v_row_count;

    p_info := jsonb_build_object('rows_inserted', v_row_count);
END;
$derive_statistical_unit_facet_partition$;

-- derive_statistical_history: range-based spawning
CREATE OR REPLACE PROCEDURE worker.derive_statistical_history(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, worker, pg_temp
AS $derive_statistical_history$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
    v_task_id bigint;
    v_period record;
    v_dirty_partitions INT[];
    v_child_count integer := 0;
    -- Range-based spawning
    v_partitions_to_process INT[];
    v_target_children INT;
    v_range_size INT;
    v_range_start INT;
    v_range_end INT;
BEGIN
    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY id DESC LIMIT 1;

    RAISE DEBUG 'derive_statistical_history: task_id=%, valid_from=%, valid_until=%',
                 v_task_id, v_valid_from, v_valid_until;

    SELECT array_agg(partition_seq ORDER BY partition_seq) INTO v_dirty_partitions
    FROM public.statistical_unit_facet_dirty_partitions;

    IF NOT EXISTS (SELECT 1 FROM public.statistical_history WHERE partition_seq IS NOT NULL LIMIT 1) THEN
        v_dirty_partitions := NULL;
        RAISE DEBUG 'derive_statistical_history: No partition entries exist, forcing full refresh';
    END IF;

    IF v_dirty_partitions IS NULL THEN
        v_partitions_to_process := ARRAY(
            SELECT DISTINCT report_partition_seq
            FROM public.statistical_unit
            ORDER BY report_partition_seq
        );
    ELSE
        v_partitions_to_process := v_dirty_partitions;
    END IF;

    -- Adaptive range-based spawning
    v_target_children := GREATEST(4, LEAST(64, ceil(COALESCE(array_length(v_partitions_to_process, 1), 0)::numeric / 4)));
    v_range_size := GREATEST(1, ceil(256.0 / v_target_children));

    FOR v_period IN
        SELECT resolution, year, month
        FROM public.get_statistical_history_periods(
            p_resolution => null::public.history_resolution,
            p_valid_from => v_valid_from,
            p_valid_until => v_valid_until
        )
    LOOP
        FOR v_range_start IN 0..255 BY v_range_size LOOP
            v_range_end := LEAST(v_range_start + v_range_size - 1, 255);
            IF EXISTS (SELECT 1 FROM unnest(v_partitions_to_process) AS p WHERE p BETWEEN v_range_start AND v_range_end) THEN
                PERFORM worker.spawn(
                    p_command => 'derive_statistical_history_period',
                    p_payload => jsonb_build_object(
                        'resolution', v_period.resolution::text,
                        'year', v_period.year,
                        'month', v_period.month,
                        'partition_seq_from', v_range_start,
                        'partition_seq_to', v_range_end
                    ),
                    p_parent_id => v_task_id
                );
                v_child_count := v_child_count + 1;
            END IF;
        END LOOP;
    END LOOP;

    RAISE DEBUG 'derive_statistical_history: spawned % period x range children',
        v_child_count;

    p_info := jsonb_build_object('child_count', v_child_count);
END;
$derive_statistical_history$;

-- derive_statistical_history_period: accept range
CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_period(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, worker, pg_temp
AS $derive_statistical_history_period$
DECLARE
    v_resolution public.history_resolution := (payload->>'resolution')::public.history_resolution;
    v_year integer := (payload->>'year')::integer;
    v_month integer := (payload->>'month')::integer;
    -- Support both single partition_seq (legacy) and range
    v_partition_seq_from integer := COALESCE(
        (payload->>'partition_seq_from')::integer,
        (payload->>'partition_seq')::integer
    );
    v_partition_seq_to integer := COALESCE(
        (payload->>'partition_seq_to')::integer,
        (payload->>'partition_seq')::integer
    );
    v_row_count bigint;
BEGIN
    RAISE DEBUG 'Processing statistical_history for resolution=%, year=%, month=%, partition_seq=[%,%]',
                 v_resolution, v_year, v_month, v_partition_seq_from, v_partition_seq_to;

    IF v_partition_seq_from IS NOT NULL THEN
        DELETE FROM public.statistical_history
        WHERE resolution = v_resolution
          AND year = v_year
          AND month IS NOT DISTINCT FROM v_month
          AND partition_seq BETWEEN v_partition_seq_from AND v_partition_seq_to;

        INSERT INTO public.statistical_history
        SELECT h.*
        FROM public.statistical_history_def(v_resolution, v_year, v_month, v_partition_seq_from, v_partition_seq_to) AS h;
        GET DIAGNOSTICS v_row_count := ROW_COUNT;
    ELSE
        DELETE FROM public.statistical_history
        WHERE resolution = v_resolution
          AND year = v_year
          AND month IS NOT DISTINCT FROM v_month
          AND partition_seq IS NULL;

        INSERT INTO public.statistical_history
        SELECT h.*
        FROM public.statistical_history_def(v_resolution, v_year, v_month) AS h;
        GET DIAGNOSTICS v_row_count := ROW_COUNT;
    END IF;

    RAISE DEBUG 'Completed statistical_history for resolution=%, year=%, month=%, partition_seq=[%,%]',
                 v_resolution, v_year, v_month, v_partition_seq_from, v_partition_seq_to;

    p_info := jsonb_build_object('rows_inserted', v_row_count);
END;
$derive_statistical_history_period$;

-- derive_statistical_history_facet: range-based spawning
CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_facet(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, worker, pg_temp
AS $derive_statistical_history_facet$
DECLARE
    v_valid_from date := COALESCE((payload->>'valid_from')::date, '-infinity'::date);
    v_valid_until date := COALESCE((payload->>'valid_until')::date, 'infinity'::date);
    v_task_id bigint;
    v_period record;
    v_dirty_partitions INT[];
    v_child_count integer := 0;
    -- Range-based spawning
    v_partitions_to_process INT[];
    v_target_children INT;
    v_range_size INT;
    v_range_start INT;
    v_range_end INT;
BEGIN
    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY id DESC LIMIT 1;

    RAISE DEBUG 'derive_statistical_history_facet: task_id=%, valid_from=%, valid_until=%',
                 v_task_id, v_valid_from, v_valid_until;

    SELECT array_agg(partition_seq ORDER BY partition_seq) INTO v_dirty_partitions
    FROM public.statistical_unit_facet_dirty_partitions;

    IF NOT EXISTS (SELECT 1 FROM public.statistical_history_facet_partitions LIMIT 1) THEN
        v_dirty_partitions := NULL;
        RAISE DEBUG 'derive_statistical_history_facet: No partition entries exist, forcing full refresh';
    END IF;

    IF v_dirty_partitions IS NULL THEN
        v_partitions_to_process := ARRAY(
            SELECT DISTINCT report_partition_seq
            FROM public.statistical_unit
            ORDER BY report_partition_seq
        );
    ELSE
        v_partitions_to_process := v_dirty_partitions;
    END IF;

    -- Adaptive range-based spawning
    v_target_children := GREATEST(4, LEAST(64, ceil(COALESCE(array_length(v_partitions_to_process, 1), 0)::numeric / 4)));
    v_range_size := GREATEST(1, ceil(256.0 / v_target_children));

    FOR v_period IN
        SELECT resolution, year, month
        FROM public.get_statistical_history_periods(
            p_resolution => null::public.history_resolution,
            p_valid_from => v_valid_from,
            p_valid_until => v_valid_until
        )
    LOOP
        FOR v_range_start IN 0..255 BY v_range_size LOOP
            v_range_end := LEAST(v_range_start + v_range_size - 1, 255);
            IF EXISTS (SELECT 1 FROM unnest(v_partitions_to_process) AS p WHERE p BETWEEN v_range_start AND v_range_end) THEN
                PERFORM worker.spawn(
                    p_command => 'derive_statistical_history_facet_period',
                    p_payload => jsonb_build_object(
                        'resolution', v_period.resolution::text,
                        'year', v_period.year,
                        'month', v_period.month,
                        'partition_seq_from', v_range_start,
                        'partition_seq_to', v_range_end
                    ),
                    p_parent_id => v_task_id
                );
                v_child_count := v_child_count + 1;
            END IF;
        END LOOP;
    END LOOP;

    RAISE DEBUG 'derive_statistical_history_facet: spawned % period x range children', v_child_count;

    p_info := jsonb_build_object('child_count', v_child_count);
END;
$derive_statistical_history_facet$;

-- derive_statistical_history_facet_period: accept range
CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_facet_period(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, worker, pg_temp
AS $derive_statistical_history_facet_period$
DECLARE
    v_resolution public.history_resolution := (payload->>'resolution')::public.history_resolution;
    v_year integer := (payload->>'year')::integer;
    v_month integer := (payload->>'month')::integer;
    -- Support both single partition_seq (legacy) and range
    v_partition_seq_from integer := COALESCE(
        (payload->>'partition_seq_from')::integer,
        (payload->>'partition_seq')::integer
    );
    v_partition_seq_to integer := COALESCE(
        (payload->>'partition_seq_to')::integer,
        (payload->>'partition_seq')::integer
    );
    v_row_count bigint;
BEGIN
    RAISE DEBUG 'Processing statistical_history_facet for resolution=%, year=%, month=%, partition_seq=[%,%]',
                 v_resolution, v_year, v_month, v_partition_seq_from, v_partition_seq_to;

    IF v_partition_seq_from IS NOT NULL THEN
        DELETE FROM public.statistical_history_facet_partitions
        WHERE resolution = v_resolution
          AND year = v_year
          AND month IS NOT DISTINCT FROM v_month
          AND partition_seq BETWEEN v_partition_seq_from AND v_partition_seq_to;

        INSERT INTO public.statistical_history_facet_partitions (
            partition_seq,
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
        SELECT partition_seq, h.*
        FROM generate_series(v_partition_seq_from, v_partition_seq_to) AS partition_seq
        CROSS JOIN LATERAL public.statistical_history_facet_def(v_resolution, v_year, v_month, partition_seq) AS h;
        GET DIAGNOSTICS v_row_count := ROW_COUNT;
    ELSE
        DELETE FROM public.statistical_history_facet
        WHERE resolution = v_resolution
          AND year = v_year
          AND month IS NOT DISTINCT FROM v_month;

        INSERT INTO public.statistical_history_facet
        SELECT h.*
        FROM public.statistical_history_facet_def(v_resolution, v_year, v_month) AS h;
        GET DIAGNOSTICS v_row_count := ROW_COUNT;
    END IF;

    RAISE DEBUG 'Completed statistical_history_facet for resolution=%, year=%, month=%, partition_seq=[%,%]',
                 v_resolution, v_year, v_month, v_partition_seq_from, v_partition_seq_to;

    p_info := jsonb_build_object('rows_inserted', v_row_count);
END;
$derive_statistical_history_facet_period$;

------------------------------------------------------------
-- Phase 8: Update def functions to accept range
------------------------------------------------------------

-- Drop the old 4-arg overload: (resolution, year, month, partition_seq).
-- It is replaced by the 5-arg version with (partition_seq_from, partition_seq_to).
-- Callers now use either 3 args (full refresh) or 5 args (range).
DROP FUNCTION IF EXISTS public.statistical_history_def(public.history_resolution, integer, integer, integer);

-- statistical_history_def: accept range via partition_seq_from/to
-- Backward compat: calling with single value works (from=to)
-- Calling with NULLs processes all partitions (full refresh)
CREATE OR REPLACE FUNCTION public.statistical_history_def(
    p_resolution history_resolution,
    p_year integer,
    p_month integer,
    p_partition_seq_from integer DEFAULT NULL,
    p_partition_seq_to integer DEFAULT NULL
)
RETURNS SETOF statistical_history_type
LANGUAGE plpgsql
AS $statistical_history_def$
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
          -- When computing a partition range, filter by report_partition_seq
          AND (p_partition_seq_from IS NULL
               OR su.report_partition_seq BETWEEN p_partition_seq_from AND p_partition_seq_to)
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
    -- PERF: Pre-aggregate stats_summary by unit_type instead of using LATERAL JOIN.
    stats_by_unit_type AS (
        SELECT
            lvc.unit_type,
            COALESCE(public.jsonb_stats_merge_agg(lvc.stats_summary), '{}'::jsonb) AS stats_summary
        FROM latest_versions_curr lvc
        WHERE lvc.used_for_counting
        GROUP BY lvc.unit_type
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
        COALESCE(sbut.stats_summary, '{}'::jsonb) AS stats_summary,
        -- partition_seq stores the range start. DELETE uses BETWEEN so range boundaries
        -- are self-consistent: the same range that INSERTs data also DELETEs it.
        p_partition_seq_from AS partition_seq
    FROM demographics d
    LEFT JOIN stats_by_unit_type sbut ON sbut.unit_type = d.unit_type;
END;
$statistical_history_def$;

-- statistical_history_facet_def: keep existing signature (single partition_seq)
-- The facet_def is called per-partition from the facet_period handler via
-- generate_series + CROSS JOIN LATERAL, so it still receives a single value.
-- No signature change needed here.

------------------------------------------------------------
-- Phase 9: Recompute slot assignments and clear derived data
------------------------------------------------------------

-- Recompute slot assignments with fixed modulus 256
UPDATE public.statistical_unit
SET report_partition_seq = public.report_partition_seq(unit_type, unit_id);

UPDATE public.statistical_unit_staging
SET report_partition_seq = public.report_partition_seq(unit_type, unit_id);

-- Clear all derived data — worker will rebuild on next trigger
TRUNCATE public.statistical_unit_facet_staging;
TRUNCATE public.statistical_unit_facet;
TRUNCATE public.statistical_history_facet_partitions;
TRUNCATE public.statistical_history_facet;
DELETE FROM public.statistical_history;
TRUNCATE public.statistical_unit_facet_dirty_partitions;

END;
