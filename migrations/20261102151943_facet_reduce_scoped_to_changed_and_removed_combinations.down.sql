-- Down Migration 20261102151943: restore the global facet reduces (definitions dumped with \sf before the up migration)
BEGIN;

CREATE OR REPLACE PROCEDURE worker.derive_statistical_unit_facet(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
    v_task_id bigint;
    v_dirty_hash_slots integer[];
    v_child_count integer := 0;
    v_partition_count_target integer;
    v_hash_partition_size integer;
    v_hash_partition int4range;
BEGIN
    v_partition_count_target := public.get_partition_count_target();
    v_hash_partition_size := GREATEST(1, 16384 / v_partition_count_target);

    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY id DESC LIMIT 1;

    SELECT array_agg(dirty_hash_slot ORDER BY dirty_hash_slot) INTO v_dirty_hash_slots
    FROM public.statistical_unit_facet_dirty_hash_slots;

    -- Full rebuild when the request covers all time, valid_from = -infinity
    -- and valid_until = infinity (STATBUS-538, see
    -- worker.enqueue_derive_statistical_unit_all), or when the staging cache
    -- is empty (fresh install, unclean shutdown of the UNLOGGED table). A
    -- full rebuild drops the whole cache first: slots whose units no longer
    -- exist are never dirty and would otherwise keep counting in the reduce.
    IF v_valid_from = '-infinity'::date AND v_valid_until = 'infinity'::date THEN
        DELETE FROM public.statistical_unit_facet_staging;
        v_dirty_hash_slots := NULL;
    ELSIF NOT EXISTS (SELECT 1 FROM public.statistical_unit_facet_staging LIMIT 1) THEN
        v_dirty_hash_slots := NULL;
    END IF;

    IF v_dirty_hash_slots IS NOT NULL THEN
        -- One child per partition range holding a dirty slot, the same ranges
        -- as the full rebuild (STATBUS-543).
        FOR v_hash_partition IN
            SELECT DISTINCT int4range(
                (d.slot / v_hash_partition_size) * v_hash_partition_size,
                LEAST((d.slot / v_hash_partition_size) * v_hash_partition_size + v_hash_partition_size, 16384)
            )
            FROM unnest(v_dirty_hash_slots) AS d(slot)
            ORDER BY 1
        LOOP
            PERFORM worker.spawn(
                p_command => 'derive_statistical_unit_facet_partition',
                p_payload => jsonb_build_object(
                    'command', 'derive_statistical_unit_facet_partition',
                    'hash_partition', v_hash_partition::text
                ),
                p_parent_id => v_task_id
            );
            v_child_count := v_child_count + 1;
        END LOOP;
    ELSE
        FOR v_hash_partition IN
            SELECT DISTINCT int4range(
                (su.hash_slot / v_hash_partition_size) * v_hash_partition_size,
                LEAST((su.hash_slot / v_hash_partition_size) * v_hash_partition_size + v_hash_partition_size, 16384)
            )
            FROM public.statistical_unit AS su
            WHERE su.used_for_counting
            ORDER BY 1
        LOOP
            PERFORM worker.spawn(
                p_command => 'derive_statistical_unit_facet_partition',
                p_payload => jsonb_build_object(
                    'command', 'derive_statistical_unit_facet_partition',
                    'hash_partition', v_hash_partition::text
                ),
                p_parent_id => v_task_id
            );
            v_child_count := v_child_count + 1;
        END LOOP;
    END IF;

    p_info := jsonb_build_object('child_count', v_child_count);
END;
$procedure$
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

    -- STATBUS-475: aggregate by the unit's EXISTENCE window within each record
    -- (canonical rule, STATBUS-460), not by the record window, so the
    -- drilldown's valid_from <= valid_on < valid_until counts existing units.
    INSERT INTO public.statistical_unit_facet_staging
    SELECT su.hash_slot,
           e.existence_from, e.existence_until - 1, e.existence_until, su.unit_type,
           su.physical_region_path, su.primary_activity_category_path,
           su.sector_path, su.legal_form_id, su.physical_country_id, su.status_id,
           COUNT(*)::integer,
           public.jsonb_stats_merge_agg(su.stats_summary)
    FROM public.statistical_unit AS su
    CROSS JOIN LATERAL (
        SELECT public.unit_existence_from(su.valid_from, su.birth_date) AS existence_from,
               public.unit_existence_until(su.valid_until, su.death_date) AS existence_until
    ) AS e
    WHERE su.used_for_counting
      AND su.hash_slot >= v_from AND su.hash_slot < v_until
      AND e.existence_from < e.existence_until
    GROUP BY su.hash_slot, e.existence_from, e.existence_until, su.unit_type,
             su.physical_region_path, su.primary_activity_category_path,
             su.sector_path, su.legal_form_id, su.physical_country_id, su.status_id;
    GET DIAGNOSTICS v_row_count := ROW_COUNT;
    p_info := jsonb_build_object('rows_inserted', v_row_count);
END;
$procedure$
;

CREATE OR REPLACE PROCEDURE worker.statistical_unit_facet_reduce(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_dirty_hash_slots int[];
    v_row_count bigint;
BEGIN
    -- Read dirty hash slots for diagnostic logging only. The MERGE below
    -- is geometry-agnostic and operates on the full staging-aggregate, so
    -- the dirty set no longer gates which rows get touched.
    SELECT array_agg(dp.dirty_hash_slot)
      INTO v_dirty_hash_slots
      FROM public.statistical_unit_facet_dirty_hash_slots AS dp;

    MERGE INTO public.statistical_unit_facet AS target
    USING (
        SELECT s.valid_from, s.valid_to, s.valid_until, s.unit_type,
               s.physical_region_path, s.primary_activity_category_path,
               s.sector_path, s.legal_form_id, s.physical_country_id, s.status_id,
               SUM(s.count)::BIGINT AS count,
               jsonb_stats_merge_agg(s.stats_summary) AS stats_summary
          FROM public.statistical_unit_facet_staging AS s
         GROUP BY s.valid_from, s.valid_to, s.valid_until, s.unit_type,
                  s.physical_region_path, s.primary_activity_category_path,
                  s.sector_path, s.legal_form_id, s.physical_country_id, s.status_id
    ) AS source
       ON target.valid_from = source.valid_from
      AND target.valid_to = source.valid_to
      AND COALESCE(target.valid_until, 'infinity'::date) = COALESCE(source.valid_until, 'infinity'::date)
      AND target.unit_type = source.unit_type
      AND COALESCE(target.physical_region_path::text, '') = COALESCE(source.physical_region_path::text, '')
      AND COALESCE(target.primary_activity_category_path::text, '') = COALESCE(source.primary_activity_category_path::text, '')
      AND COALESCE(target.sector_path::text, '') = COALESCE(source.sector_path::text, '')
      AND COALESCE(target.legal_form_id, -1) = COALESCE(source.legal_form_id, -1)
      AND COALESCE(target.physical_country_id, -1) = COALESCE(source.physical_country_id, -1)
      AND COALESCE(target.status_id, -1) = COALESCE(source.status_id, -1)
    WHEN MATCHED AND (target.count <> source.count
                      OR target.stats_summary IS DISTINCT FROM source.stats_summary)
        THEN UPDATE SET count = source.count,
                        stats_summary = source.stats_summary
    WHEN NOT MATCHED BY TARGET
        THEN INSERT (valid_from, valid_to, valid_until, unit_type,
                     physical_region_path, primary_activity_category_path,
                     sector_path, legal_form_id, physical_country_id, status_id,
                     count, stats_summary)
             VALUES (source.valid_from, source.valid_to, source.valid_until, source.unit_type,
                     source.physical_region_path, source.primary_activity_category_path,
                     source.sector_path, source.legal_form_id, source.physical_country_id, source.status_id,
                     source.count, source.stats_summary)
    WHEN NOT MATCHED BY SOURCE THEN DELETE;
    GET DIAGNOSTICS v_row_count := ROW_COUNT;

    p_info := jsonb_build_object(
        'mode', 'global',
        'dirty_hash_slots', to_jsonb(v_dirty_hash_slots),
        'rows_merged', v_row_count);
END;
$procedure$
;

CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_facet(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_valid_from date := COALESCE((payload->>'valid_from')::date, '-infinity'::date);
    v_valid_until date := COALESCE((payload->>'valid_until')::date, 'infinity'::date);
    v_task_id bigint;
    v_period record;
    v_dirty_hash_slots integer[];
    v_child_count integer := 0;
    v_partition_count_target integer;
    v_hash_partition_size integer;
    v_hash_partition int4range;
BEGIN
    v_partition_count_target := public.get_partition_count_target();
    v_hash_partition_size := GREATEST(1, 16384 / v_partition_count_target);

    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY id DESC LIMIT 1;

    SELECT array_agg(dirty_hash_slot ORDER BY dirty_hash_slot) INTO v_dirty_hash_slots
    FROM public.statistical_unit_facet_dirty_hash_slots;

    -- Full rebuild when the request covers all time, valid_from = -infinity
    -- and valid_until = infinity (STATBUS-538, see
    -- worker.enqueue_derive_statistical_unit_all), or when the per-slot cache
    -- is empty (fresh install). A full rebuild drops the whole cache first,
    -- so slots and periods without units do not survive into the reduce.
    IF (payload->>'valid_from')::date = '-infinity'::date
       AND (payload->>'valid_until')::date = 'infinity'::date THEN
        DELETE FROM public.statistical_history_facet_partitions;
        v_dirty_hash_slots := NULL;
    ELSIF NOT EXISTS (SELECT 1 FROM public.statistical_history_facet_partitions LIMIT 1) THEN
        v_dirty_hash_slots := NULL;
    END IF;

    FOR v_period IN
        SELECT resolution, year, month
        FROM public.get_statistical_history_periods(
            p_resolution => null::public.history_resolution,
            p_valid_from => v_valid_from,
            p_valid_until => v_valid_until
        )
    LOOP
        IF v_dirty_hash_slots IS NOT NULL THEN
            -- One child per partition range holding a dirty slot, the same
            -- ranges as the full rebuild (STATBUS-543).
            FOR v_hash_partition IN
                SELECT DISTINCT int4range(
                    (d.slot / v_hash_partition_size) * v_hash_partition_size,
                    LEAST((d.slot / v_hash_partition_size) * v_hash_partition_size + v_hash_partition_size, 16384)
                )
                FROM unnest(v_dirty_hash_slots) AS d(slot)
                ORDER BY 1
            LOOP
                PERFORM worker.spawn(
                    p_command => 'derive_statistical_history_facet_period',
                    p_payload => jsonb_build_object(
                        'command', 'derive_statistical_history_facet_period',
                        'resolution', v_period.resolution::text,
                        'year', v_period.year,
                        'month', v_period.month,
                        'hash_partition', v_hash_partition::text
                    ),
                    p_parent_id => v_task_id
                );
                v_child_count := v_child_count + 1;
            END LOOP;
        ELSE
            FOR v_hash_partition IN
                SELECT DISTINCT int4range(
                    (su.hash_slot / v_hash_partition_size) * v_hash_partition_size,
                    LEAST((su.hash_slot / v_hash_partition_size) * v_hash_partition_size + v_hash_partition_size, 16384)
                )
                FROM public.statistical_unit AS su
                ORDER BY 1
            LOOP
                PERFORM worker.spawn(
                    p_command => 'derive_statistical_history_facet_period',
                    p_payload => jsonb_build_object(
                        'command', 'derive_statistical_history_facet_period',
                        'resolution', v_period.resolution::text,
                        'year', v_period.year,
                        'month', v_period.month,
                        'hash_partition', v_hash_partition::text
                    ),
                    p_parent_id => v_task_id
                );
                v_child_count := v_child_count + 1;
            END LOOP;
        END IF;
    END LOOP;

    p_info := jsonb_build_object('child_count', v_child_count);
END;
$procedure$
;

CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_facet_period(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_resolution public.history_resolution := (payload->>'resolution')::public.history_resolution;
    v_year integer := (payload->>'year')::integer;
    v_month integer := (payload->>'month')::integer;
    v_hash_partition int4range := (payload->>'hash_partition')::int4range;
    v_row_count bigint;
BEGIN
    DELETE FROM public.statistical_history_facet_partitions
     WHERE resolution = v_resolution
       AND year = v_year
       AND month IS NOT DISTINCT FROM v_month
       AND hash_slot >= lower(v_hash_partition)
       AND hash_slot <  upper(v_hash_partition);

    INSERT INTO public.statistical_history_facet_partitions
    SELECT * FROM public.statistical_history_facet_def(
        v_resolution, v_year, v_month, v_hash_partition
    );

    GET DIAGNOSTICS v_row_count := ROW_COUNT;
    p_info := jsonb_build_object('rows_inserted', v_row_count);
END;
$procedure$
;

CREATE OR REPLACE PROCEDURE worker.statistical_history_facet_reduce(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_dirty_hash_slots int[];
    v_row_count bigint;
BEGIN
    -- Read dirty hash slots for diagnostic logging only.
    SELECT array_agg(dp.dirty_hash_slot)
      INTO v_dirty_hash_slots
      FROM public.statistical_unit_facet_dirty_hash_slots AS dp;

    MERGE INTO public.statistical_history_facet AS target
    USING (
        SELECT
            resolution, year, month, unit_type,
            primary_activity_category_path, secondary_activity_category_path,
            sector_path, legal_form_id, physical_region_path,
            physical_country_id, unit_size_id, status_id,
            SUM(exists_count)::integer AS exists_count,
            SUM(exists_change)::integer AS exists_change,
            SUM(exists_added_count)::integer AS exists_added_count,
            SUM(exists_removed_count)::integer AS exists_removed_count,
            SUM(countable_count)::integer AS countable_count,
            SUM(countable_change)::integer AS countable_change,
            SUM(countable_added_count)::integer AS countable_added_count,
            SUM(countable_removed_count)::integer AS countable_removed_count,
            SUM(births)::integer AS births,
            SUM(deaths)::integer AS deaths,
            SUM(name_change_count)::integer AS name_change_count,
            SUM(primary_activity_category_change_count)::integer AS primary_activity_category_change_count,
            SUM(secondary_activity_category_change_count)::integer AS secondary_activity_category_change_count,
            SUM(sector_change_count)::integer AS sector_change_count,
            SUM(legal_form_change_count)::integer AS legal_form_change_count,
            SUM(physical_region_change_count)::integer AS physical_region_change_count,
            SUM(physical_country_change_count)::integer AS physical_country_change_count,
            SUM(physical_address_change_count)::integer AS physical_address_change_count,
            SUM(unit_size_change_count)::integer AS unit_size_change_count,
            SUM(status_change_count)::integer AS status_change_count,
            jsonb_stats_merge_agg(stats_summary) AS stats_summary
        FROM public.statistical_history_facet_partitions
        GROUP BY resolution, year, month, unit_type,
                 primary_activity_category_path, secondary_activity_category_path,
                 sector_path, legal_form_id, physical_region_path,
                 physical_country_id, unit_size_id, status_id
    ) AS source
       ON target.resolution = source.resolution
      AND target.year = source.year
      AND COALESCE(target.month, -1) = COALESCE(source.month, -1)
      AND target.unit_type = source.unit_type
      AND COALESCE(target.primary_activity_category_path::text, '') = COALESCE(source.primary_activity_category_path::text, '')
      AND COALESCE(target.secondary_activity_category_path::text, '') = COALESCE(source.secondary_activity_category_path::text, '')
      AND COALESCE(target.sector_path::text, '') = COALESCE(source.sector_path::text, '')
      AND COALESCE(target.legal_form_id, -1) = COALESCE(source.legal_form_id, -1)
      AND COALESCE(target.physical_region_path::text, '') = COALESCE(source.physical_region_path::text, '')
      AND COALESCE(target.physical_country_id, -1) = COALESCE(source.physical_country_id, -1)
      AND COALESCE(target.unit_size_id, -1) = COALESCE(source.unit_size_id, -1)
      AND COALESCE(target.status_id, -1) = COALESCE(source.status_id, -1)
    WHEN MATCHED AND (
            target.exists_count <> source.exists_count
         OR target.stats_summary IS DISTINCT FROM source.stats_summary)
        THEN UPDATE SET
            exists_count = source.exists_count,
            exists_change = source.exists_change,
            exists_added_count = source.exists_added_count,
            exists_removed_count = source.exists_removed_count,
            countable_count = source.countable_count,
            countable_change = source.countable_change,
            countable_added_count = source.countable_added_count,
            countable_removed_count = source.countable_removed_count,
            births = source.births,
            deaths = source.deaths,
            name_change_count = source.name_change_count,
            primary_activity_category_change_count = source.primary_activity_category_change_count,
            secondary_activity_category_change_count = source.secondary_activity_category_change_count,
            sector_change_count = source.sector_change_count,
            legal_form_change_count = source.legal_form_change_count,
            physical_region_change_count = source.physical_region_change_count,
            physical_country_change_count = source.physical_country_change_count,
            physical_address_change_count = source.physical_address_change_count,
            unit_size_change_count = source.unit_size_change_count,
            status_change_count = source.status_change_count,
            stats_summary = source.stats_summary
    WHEN NOT MATCHED BY TARGET
        THEN INSERT (
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
            stats_summary)
        VALUES (
            source.resolution, source.year, source.month, source.unit_type,
            source.primary_activity_category_path, source.secondary_activity_category_path,
            source.sector_path, source.legal_form_id, source.physical_region_path,
            source.physical_country_id, source.unit_size_id, source.status_id,
            source.exists_count, source.exists_change, source.exists_added_count, source.exists_removed_count,
            source.countable_count, source.countable_change, source.countable_added_count, source.countable_removed_count,
            source.births, source.deaths,
            source.name_change_count, source.primary_activity_category_change_count,
            source.secondary_activity_category_change_count, source.sector_change_count,
            source.legal_form_change_count, source.physical_region_change_count,
            source.physical_country_change_count, source.physical_address_change_count,
            source.unit_size_change_count, source.status_change_count,
            source.stats_summary)
    WHEN NOT MATCHED BY SOURCE THEN DELETE;
    GET DIAGNOSTICS v_row_count := ROW_COUNT;

    p_info := jsonb_build_object(
        'mode', 'global',
        'dirty_hash_slots', to_jsonb(v_dirty_hash_slots),
        'rows_merged', v_row_count);

    -- Clean up dirty partitions at the very end, after all consumers have read them.
    -- (statistical_unit_facet_reduce ran earlier in the pipeline and read dirty_hash_slots
    -- for diagnostic logging; truncating here is safe because no later step needs it.)
    TRUNCATE public.statistical_unit_facet_dirty_hash_slots;

    PERFORM pg_notify('worker_status',
        json_build_object('type', 'is_deriving_reports', 'status', false)::text);
END;
$procedure$
;

DROP TABLE worker.statistical_unit_facet_changed;
DROP TABLE worker.statistical_history_facet_changed;

END;
