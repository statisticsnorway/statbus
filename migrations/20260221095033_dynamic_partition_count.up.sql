-- Migration 20260221095033: dynamic_partition_count
--
-- Start with 4 partitions instead of 128, auto-scale based on data volume.
-- Reduces analytics pipeline overhead from 128×N tasks to 4×N for small datasets.
BEGIN;

-- =============================================================================
-- Part 1: Rename settings column and change default from 128 → 4
-- =============================================================================
ALTER TABLE public.settings RENAME COLUMN report_partition_count TO analytics_partition_count;
ALTER TABLE public.settings ALTER COLUMN analytics_partition_count SET DEFAULT 4;
UPDATE public.settings SET analytics_partition_count = 4;

-- =============================================================================
-- Part 2: Replace GENERATED column with regular column + trigger
-- =============================================================================

-- Drop GENERATED expressions (keeps data, becomes regular columns)
ALTER TABLE public.statistical_unit ALTER COLUMN report_partition_seq DROP EXPRESSION;
ALTER TABLE public.statistical_unit_staging ALTER COLUMN report_partition_seq DROP EXPRESSION;

-- Remove function DEFAULTs (require explicit count parameter)
DROP FUNCTION public.report_partition_seq(text, int, int);
CREATE FUNCTION public.report_partition_seq(
    p_unit_type text, p_unit_id int, p_num_partitions int
) RETURNS int
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $report_partition_seq$
    SELECT abs(hashtext(p_unit_type || ':' || p_unit_id::text)) % p_num_partitions;
$report_partition_seq$;

DROP FUNCTION public.report_partition_seq(public.statistical_unit_type, int, int);
CREATE FUNCTION public.report_partition_seq(
    p_unit_type public.statistical_unit_type, p_unit_id int, p_num_partitions int
) RETURNS int
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $report_partition_seq$
    SELECT abs(hashtext(p_unit_type::text || ':' || p_unit_id::text)) % p_num_partitions;
$report_partition_seq$;

-- Update get_statistical_unit_data_partial: 2-arg calls → 3-arg with settings count
CREATE OR REPLACE FUNCTION import.get_statistical_unit_data_partial(p_unit_type statistical_unit_type, p_id_ranges int4multirange)
 RETURNS SETOF statistical_unit
 LANGUAGE plpgsql
 STABLE
AS $get_statistical_unit_data_partial$
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
            t.invalid_codes,
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
            t.invalid_codes,
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
            t.invalid_codes,
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
$get_statistical_unit_data_partial$;

-- BEFORE INSERT trigger to compute partition_seq on insert
CREATE FUNCTION public.set_report_partition_seq()
RETURNS trigger
LANGUAGE plpgsql
AS $set_report_partition_seq$
BEGIN
    NEW.report_partition_seq := public.report_partition_seq(
        NEW.unit_type, NEW.unit_id,
        (SELECT analytics_partition_count FROM public.settings)
    );
    RETURN NEW;
END;
$set_report_partition_seq$;

CREATE TRIGGER trg_set_report_partition_seq
    BEFORE INSERT ON public.statistical_unit
    FOR EACH ROW
    EXECUTE FUNCTION public.set_report_partition_seq();

CREATE TRIGGER trg_set_report_partition_seq
    BEFORE INSERT ON public.statistical_unit_staging
    FOR EACH ROW
    EXECUTE FUNCTION public.set_report_partition_seq();

-- =============================================================================
-- Part 3: Settings change trigger (automatic propagation)
-- =============================================================================
CREATE FUNCTION admin.propagate_partition_count_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, admin, pg_temp
AS $propagate_partition_count_change$
BEGIN
    IF NEW.analytics_partition_count IS DISTINCT FROM OLD.analytics_partition_count THEN
        RAISE LOG 'propagate_partition_count_change: % → % partitions',
            OLD.analytics_partition_count, NEW.analytics_partition_count;

        -- Recompute all partition assignments
        UPDATE public.statistical_unit
        SET report_partition_seq = public.report_partition_seq(
            unit_type, unit_id, NEW.analytics_partition_count
        );

        -- Clear derived partition data (force full refresh)
        TRUNCATE public.statistical_unit_facet_staging;
        TRUNCATE public.statistical_history_facet_partitions;
        DELETE FROM public.statistical_history WHERE partition_seq IS NOT NULL;
        TRUNCATE public.statistical_unit_facet_dirty_partitions;
    END IF;
    RETURN NEW;
END;
$propagate_partition_count_change$;

CREATE TRIGGER trg_settings_partition_count_change
    AFTER UPDATE OF analytics_partition_count ON public.settings
    FOR EACH ROW
    EXECUTE FUNCTION admin.propagate_partition_count_change();

-- =============================================================================
-- Part 4: admin.adjust_analytics_partition_count()
-- =============================================================================
CREATE PROCEDURE admin.adjust_analytics_partition_count()
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, admin, pg_temp
AS $adjust_analytics_partition_count$
DECLARE
    v_unit_count bigint;
    v_current_count int;
    v_desired_count int;
BEGIN
    SELECT analytics_partition_count INTO v_current_count FROM public.settings;
    SELECT count(*) INTO v_unit_count FROM public.statistical_unit;

    v_desired_count := CASE
        WHEN v_unit_count <= 5000 THEN 4
        WHEN v_unit_count <= 25000 THEN 8
        WHEN v_unit_count <= 100000 THEN 16
        WHEN v_unit_count <= 500000 THEN 32
        WHEN v_unit_count <= 2000000 THEN 64
        ELSE 128
    END;

    IF v_desired_count != v_current_count THEN
        RAISE LOG 'adjust_analytics_partition_count: % units → % partitions (was %)',
            v_unit_count, v_desired_count, v_current_count;
        -- This fires the settings trigger which handles propagation
        UPDATE public.settings SET analytics_partition_count = v_desired_count;
    END IF;
END;
$adjust_analytics_partition_count$;

-- =============================================================================
-- Part 5: derive_reports — add adjust call
-- =============================================================================
CREATE OR REPLACE FUNCTION worker.derive_reports(p_valid_from date DEFAULT NULL::date, p_valid_until date DEFAULT NULL::date)
 RETURNS void
 LANGUAGE plpgsql
AS $derive_reports$
BEGIN
  -- Auto-scale partition count based on data volume
  CALL admin.adjust_analytics_partition_count();

  -- Instead of running all phases in one transaction, enqueue the first phase.
  -- Each phase will enqueue the next one when it completes.
  PERFORM worker.enqueue_derive_statistical_history(
    p_valid_from => p_valid_from,
    p_valid_until => p_valid_until
  );
END;
$derive_reports$;

-- =============================================================================
-- Part 6: derive_statistical_unit — explicit count for dirty partition tracking
-- =============================================================================
CREATE OR REPLACE FUNCTION worker.derive_statistical_unit(p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange, p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange, p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange, p_valid_from date DEFAULT NULL::date, p_valid_until date DEFAULT NULL::date, p_task_id bigint DEFAULT NULL::bigint)
 RETURNS void
 LANGUAGE plpgsql
AS $derive_statistical_unit$
DECLARE
    v_batch RECORD;
    v_establishment_ids INT[];
    v_legal_unit_ids INT[];
    v_enterprise_ids INT[];
    v_batch_count INT := 0;
    v_is_full_refresh BOOLEAN;
    v_child_priority BIGINT;
    v_orphan_enterprise_ids INT[];
    v_orphan_legal_unit_ids INT[];
    v_orphan_establishment_ids INT[];
BEGIN
    v_is_full_refresh := (p_establishment_id_ranges IS NULL
                         AND p_legal_unit_id_ranges IS NULL
                         AND p_enterprise_id_ranges IS NULL);

    -- Priority for children: same as current task (will run next due to structured concurrency)
    v_child_priority := nextval('public.worker_task_priority_seq');

    IF v_is_full_refresh THEN
        -- Full refresh: spawn batch children (no orphan cleanup needed - covers everything)
        -- No dirty partition tracking needed: full refresh recomputes all partitions
        FOR v_batch IN
            SELECT * FROM public.get_closed_group_batches(p_target_batch_size := 1000)
        LOOP
            PERFORM worker.spawn(
                p_command := 'statistical_unit_refresh_batch',
                p_payload := jsonb_build_object(
                    'command', 'statistical_unit_refresh_batch',
                    'batch_seq', v_batch.batch_seq,
                    'enterprise_ids', v_batch.enterprise_ids,
                    'legal_unit_ids', v_batch.legal_unit_ids,
                    'establishment_ids', v_batch.establishment_ids,
                    'valid_from', p_valid_from,
                    'valid_until', p_valid_until
                ),
                p_parent_id := p_task_id,
                p_priority := v_child_priority
            );
            v_batch_count := v_batch_count + 1;
        END LOOP;
    ELSE
        -- Partial refresh: convert multiranges to arrays
        v_establishment_ids := ARRAY(
            SELECT generate_series(lower(r), upper(r)-1)
            FROM unnest(COALESCE(p_establishment_id_ranges, '{}'::int4multirange)) AS t(r)
        );
        v_legal_unit_ids := ARRAY(
            SELECT generate_series(lower(r), upper(r)-1)
            FROM unnest(COALESCE(p_legal_unit_id_ranges, '{}'::int4multirange)) AS t(r)
        );
        v_enterprise_ids := ARRAY(
            SELECT generate_series(lower(r), upper(r)-1)
            FROM unnest(COALESCE(p_enterprise_id_ranges, '{}'::int4multirange)) AS t(r)
        );

        -- =====================================================================
        -- ORPHAN CLEANUP: Handle deleted entities BEFORE batching
        -- =====================================================================
        IF COALESCE(array_length(v_enterprise_ids, 1), 0) > 0 THEN
            v_orphan_enterprise_ids := ARRAY(
                SELECT id FROM unnest(v_enterprise_ids) AS id
                EXCEPT SELECT e.id FROM public.enterprise AS e WHERE e.id = ANY(v_enterprise_ids)
            );
            IF COALESCE(array_length(v_orphan_enterprise_ids, 1), 0) > 0 THEN
                RAISE DEBUG 'derive_statistical_unit: Cleaning up % orphan enterprise IDs',
                    array_length(v_orphan_enterprise_ids, 1);
                DELETE FROM public.timepoints WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.timeline_enterprise WHERE enterprise_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
            END IF;
        END IF;

        IF COALESCE(array_length(v_legal_unit_ids, 1), 0) > 0 THEN
            v_orphan_legal_unit_ids := ARRAY(
                SELECT id FROM unnest(v_legal_unit_ids) AS id
                EXCEPT SELECT lu.id FROM public.legal_unit AS lu WHERE lu.id = ANY(v_legal_unit_ids)
            );
            IF COALESCE(array_length(v_orphan_legal_unit_ids, 1), 0) > 0 THEN
                RAISE DEBUG 'derive_statistical_unit: Cleaning up % orphan legal_unit IDs',
                    array_length(v_orphan_legal_unit_ids, 1);
                DELETE FROM public.timepoints WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.timeline_legal_unit WHERE legal_unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
            END IF;
        END IF;

        IF COALESCE(array_length(v_establishment_ids, 1), 0) > 0 THEN
            v_orphan_establishment_ids := ARRAY(
                SELECT id FROM unnest(v_establishment_ids) AS id
                EXCEPT SELECT es.id FROM public.establishment AS es WHERE es.id = ANY(v_establishment_ids)
            );
            IF COALESCE(array_length(v_orphan_establishment_ids, 1), 0) > 0 THEN
                RAISE DEBUG 'derive_statistical_unit: Cleaning up % orphan establishment IDs',
                    array_length(v_orphan_establishment_ids, 1);
                DELETE FROM public.timepoints WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.timeline_establishment WHERE establishment_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
            END IF;
        END IF;

        -- =====================================================================
        -- BATCHING: Only existing entities, partitioned with no overlap
        -- Compute batches FIRST, then mark dirty partitions for ALL units
        -- in ALL batches (covers closed-group expansion).
        -- =====================================================================

        -- Collect all batches into a temp table for two-pass processing
        IF to_regclass('pg_temp._batches') IS NOT NULL THEN
            DROP TABLE _batches;
        END IF;
        CREATE TEMP TABLE _batches ON COMMIT DROP AS
        SELECT * FROM public.get_closed_group_batches(
            p_target_batch_size := 1000,
            p_establishment_ids := NULLIF(v_establishment_ids, '{}'),
            p_legal_unit_ids := NULLIF(v_legal_unit_ids, '{}'),
            p_enterprise_ids := NULLIF(v_enterprise_ids, '{}')
        );

        -- =====================================================================
        -- DIRTY PARTITION TRACKING: Mark partitions for ALL units in ALL batches
        -- Explicit count from settings (no function DEFAULT).
        -- =====================================================================
        INSERT INTO public.statistical_unit_facet_dirty_partitions (partition_seq)
        SELECT DISTINCT public.report_partition_seq(
            t.unit_type, t.unit_id,
            (SELECT analytics_partition_count FROM public.settings)
        )
        FROM (
            SELECT 'enterprise'::text AS unit_type, unnest(b.enterprise_ids) AS unit_id
            FROM _batches AS b
            UNION ALL
            SELECT 'legal_unit', unnest(b.legal_unit_ids)
            FROM _batches AS b
            UNION ALL
            SELECT 'establishment', unnest(b.establishment_ids)
            FROM _batches AS b
        ) AS t
        WHERE t.unit_id IS NOT NULL
        ON CONFLICT DO NOTHING;

        RAISE DEBUG 'derive_statistical_unit: Tracked dirty facet partitions for closed group across % batches',
            (SELECT count(*) FROM _batches);

        -- Spawn batch children
        FOR v_batch IN SELECT * FROM _batches
        LOOP
            PERFORM worker.spawn(
                p_command := 'statistical_unit_refresh_batch',
                p_payload := jsonb_build_object(
                    'command', 'statistical_unit_refresh_batch',
                    'batch_seq', v_batch.batch_seq,
                    'enterprise_ids', v_batch.enterprise_ids,
                    'legal_unit_ids', v_batch.legal_unit_ids,
                    'establishment_ids', v_batch.establishment_ids,
                    'valid_from', p_valid_from,
                    'valid_until', p_valid_until
                ),
                p_parent_id := p_task_id,
                p_priority := v_child_priority
            );
            v_batch_count := v_batch_count + 1;
        END LOOP;
    END IF;

    RAISE DEBUG 'derive_statistical_unit: Spawned % batch children with parent_id %', v_batch_count, p_task_id;

    -- Refresh derived data (used flags) - always full refreshes, run synchronously
    PERFORM public.activity_category_used_derive();
    PERFORM public.region_used_derive();
    PERFORM public.sector_used_derive();
    PERFORM public.data_source_used_derive();
    PERFORM public.legal_form_used_derive();
    PERFORM public.country_used_derive();

    -- =========================================================================
    -- STAGING PATTERN: Enqueue flush task (runs after all batches complete)
    -- =========================================================================
    PERFORM worker.enqueue_statistical_unit_flush_staging();
    RAISE DEBUG 'derive_statistical_unit: Enqueued flush_staging task';

    -- Enqueue derive_reports as an "uncle" task (runs after flush completes)
    PERFORM worker.enqueue_derive_reports(
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until
    );

    RAISE DEBUG 'derive_statistical_unit: Enqueued derive_reports';
END;
$derive_statistical_unit$;

-- =============================================================================
-- Part 7: Recompute existing data with new count
-- =============================================================================
UPDATE public.statistical_unit
SET report_partition_seq = public.report_partition_seq(unit_type, unit_id, 4);

-- Clear derived data (force full refresh on next run)
TRUNCATE public.statistical_unit_facet_staging;
TRUNCATE public.statistical_history_facet_partitions;
DELETE FROM public.statistical_history WHERE partition_seq IS NOT NULL;
TRUNCATE public.statistical_unit_facet_dirty_partitions;

END;
