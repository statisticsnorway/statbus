-- Migration 20260324232001: snapshot_tables_for_scoped_merge_reduce
--
-- Problem: The incremental MERGE in both facet reduce procedures reads ALL
-- staging rows to build the aggregate, even when only 1-3 partitions changed.
-- With 70+ partitions × ~8,800 rows each ≈ 616k rows scanned for every
-- incremental run. The MERGE also uses NOT MATCHED BY SOURCE THEN DELETE
-- which compares every target row against the full aggregate.
--
-- Solution: Two snapshot tables capture the dim combos that existed in dirty
-- partitions BEFORE children rewrite staging. The reduce then:
--   1. Scoped aggregate: only re-aggregates staging rows whose dim combos
--      appear in either current dirty staging OR the pre-dirty snapshot.
--   2. Scoped MERGE: only touches target rows matching those dim combos.
--   3. DELETE stale: removes target rows that were in the pre-dirty snapshot
--      but disappeared from staging (the combo no longer exists).
BEGIN;

----------------------------------------------------------------------
-- 1. Snapshot tables (UNLOGGED = no WAL, fast writes; ephemeral data)
----------------------------------------------------------------------

CREATE UNLOGGED TABLE public.statistical_unit_facet_pre_dirty_dims (
    valid_from                     date,
    valid_to                       date,
    valid_until                    date,
    unit_type                      statistical_unit_type,
    physical_region_path           ltree,
    primary_activity_category_path ltree,
    sector_path                    ltree,
    legal_form_id                  integer,
    physical_country_id            integer,
    status_id                      integer
);

CREATE UNLOGGED TABLE public.statistical_history_facet_pre_dirty_dims (
    resolution                       history_resolution,
    year                             integer,
    month                            integer,
    unit_type                        statistical_unit_type,
    primary_activity_category_path   ltree,
    secondary_activity_category_path ltree,
    sector_path                      ltree,
    legal_form_id                    integer,
    physical_region_path             ltree,
    physical_country_id              integer,
    unit_size_id                     integer,
    status_id                        integer
);


----------------------------------------------------------------------
-- 2. derive_statistical_unit_facet: snapshot dirty dims before spawning
----------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE worker.derive_statistical_unit_facet(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $derive_statistical_unit_facet$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
    v_task_id bigint;
    v_dirty_partitions INT[];
    v_populated_partitions INT;
    v_expected_partitions INT;
    v_child_count INT := 0;
    -- Range-based spawning variables (used for full refresh only)
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

    -- Fixed modulus (was COUNT DISTINCT on 3.1M rows = 35s)
    v_expected_partitions := 256;

    SELECT array_agg(partition_seq ORDER BY partition_seq) INTO v_dirty_partitions
    FROM public.statistical_unit_facet_dirty_partitions;

    IF v_populated_partitions < v_expected_partitions THEN
        v_dirty_partitions := NULL;
        RAISE DEBUG 'derive_statistical_unit_facet: Staging has %/% expected partitions populated, forcing full refresh',
            v_populated_partitions, v_expected_partitions;
    END IF;

    IF v_dirty_partitions IS NOT NULL THEN
        -- Snapshot dirty partition dim combos BEFORE children rewrite staging.
        -- This allows the reduce to find combos that DISAPPEAR from dirty partitions.
        TRUNCATE public.statistical_unit_facet_pre_dirty_dims;
        INSERT INTO public.statistical_unit_facet_pre_dirty_dims
            (valid_from, valid_to, valid_until, unit_type,
             physical_region_path, primary_activity_category_path,
             sector_path, legal_form_id, physical_country_id, status_id)
        SELECT DISTINCT
            s.valid_from, s.valid_to, s.valid_until, s.unit_type,
            s.physical_region_path, s.primary_activity_category_path,
            s.sector_path, s.legal_form_id, s.physical_country_id, s.status_id
        FROM public.statistical_unit_facet_staging AS s
        WHERE s.partition_seq = ANY(v_dirty_partitions);

        -- Partial refresh: spawn one child per dirty partition (no range grouping overhead).
        -- For typical incremental changes this is 1-3 partitions, each processing ~12k rows.
        FOR i IN 1..COALESCE(array_length(v_dirty_partitions, 1), 0) LOOP
            PERFORM worker.spawn(
                p_command => 'derive_statistical_unit_facet_partition',
                p_payload => jsonb_build_object(
                    'command', 'derive_statistical_unit_facet_partition',
                    'partition_seq_from', v_dirty_partitions[i],
                    'partition_seq_to', v_dirty_partitions[i]
                ),
                p_parent_id => v_task_id
            );
            v_child_count := v_child_count + 1;
        END LOOP;
    ELSE
        -- Full refresh: clear snapshot (not needed, but keep clean state)
        TRUNCATE public.statistical_unit_facet_pre_dirty_dims;

        -- Full refresh: use adaptive range-based spawning across all populated partitions
        v_partitions_to_process := ARRAY(
            SELECT DISTINCT report_partition_seq
            FROM public.statistical_unit
            WHERE used_for_counting
            ORDER BY report_partition_seq
        );

        v_target_children := GREATEST(4, LEAST(64, ceil(COALESCE(array_length(v_partitions_to_process, 1), 0)::numeric / 4)));
        v_range_size := GREATEST(1, ceil(256.0 / v_target_children));

        FOR v_range_start IN 0..255 BY v_range_size LOOP
            v_range_end := LEAST(v_range_start + v_range_size - 1, 255);
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
    END IF;

    RAISE DEBUG 'derive_statistical_unit_facet: Spawned % children', v_child_count;

    p_info := jsonb_build_object('child_count', v_child_count);
END;
$derive_statistical_unit_facet$;


----------------------------------------------------------------------
-- 3. derive_statistical_history_facet: snapshot dirty dims before spawning
----------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_facet(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $derive_statistical_history_facet$
DECLARE
    v_valid_from date := COALESCE((payload->>'valid_from')::date, '-infinity'::date);
    v_valid_until date := COALESCE((payload->>'valid_until')::date, 'infinity'::date);
    v_task_id bigint;
    v_period record;
    v_dirty_partitions INT[];
    v_child_count integer := 0;
    -- Range-based spawning (full refresh only)
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

    IF v_dirty_partitions IS NOT NULL THEN
        -- Snapshot dirty partition dim combos BEFORE children rewrite staging.
        -- This allows the reduce to find combos that DISAPPEAR from dirty partitions.
        TRUNCATE public.statistical_history_facet_pre_dirty_dims;
        INSERT INTO public.statistical_history_facet_pre_dirty_dims
            (resolution, year, month, unit_type,
             primary_activity_category_path, secondary_activity_category_path,
             sector_path, legal_form_id, physical_region_path,
             physical_country_id, unit_size_id, status_id)
        SELECT DISTINCT
            s.resolution, s.year, s.month, s.unit_type,
            s.primary_activity_category_path, s.secondary_activity_category_path,
            s.sector_path, s.legal_form_id, s.physical_region_path,
            s.physical_country_id, s.unit_size_id, s.status_id
        FROM public.statistical_history_facet_partitions AS s
        WHERE s.partition_seq = ANY(v_dirty_partitions);
    ELSE
        -- Full refresh: clear snapshot (not needed, but keep clean state)
        TRUNCATE public.statistical_history_facet_pre_dirty_dims;
    END IF;

    FOR v_period IN
        SELECT resolution, year, month
        FROM public.get_statistical_history_periods(
            p_resolution => null::public.history_resolution,
            p_valid_from => v_valid_from,
            p_valid_until => v_valid_until
        )
    LOOP
        IF v_dirty_partitions IS NOT NULL THEN
            -- Partial refresh: one child per dirty partition per period
            FOR i IN 1..COALESCE(array_length(v_dirty_partitions, 1), 0) LOOP
                PERFORM worker.spawn(
                    p_command => 'derive_statistical_history_facet_period',
                    p_payload => jsonb_build_object(
                        'command', 'derive_statistical_history_facet_period',
                        'resolution', v_period.resolution::text,
                        'year', v_period.year,
                        'month', v_period.month,
                        'partition_seq_from', v_dirty_partitions[i],
                        'partition_seq_to', v_dirty_partitions[i]
                    ),
                    p_parent_id => v_task_id
                );
                v_child_count := v_child_count + 1;
            END LOOP;
        ELSE
            -- Full refresh: adaptive range-based spawning
            IF v_partitions_to_process IS NULL THEN
                v_partitions_to_process := ARRAY(
                    SELECT DISTINCT report_partition_seq
                    FROM public.statistical_unit
                    ORDER BY report_partition_seq
                );
                v_target_children := GREATEST(4, LEAST(64, ceil(COALESCE(array_length(v_partitions_to_process, 1), 0)::numeric / 4)));
                v_range_size := GREATEST(1, ceil(256.0 / v_target_children));
            END IF;

            FOR v_range_start IN 0..255 BY v_range_size LOOP
                v_range_end := LEAST(v_range_start + v_range_size - 1, 255);
                IF EXISTS (SELECT 1 FROM unnest(v_partitions_to_process) AS p WHERE p BETWEEN v_range_start AND v_range_end) THEN
                    PERFORM worker.spawn(
                        p_command => 'derive_statistical_history_facet_period',
                        p_payload => jsonb_build_object(
                            'command', 'derive_statistical_history_facet_period',
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
        END IF;
    END LOOP;

    RAISE DEBUG 'derive_statistical_history_facet: spawned % period x partition children', v_child_count;

    p_info := jsonb_build_object('child_count', v_child_count);
END;
$derive_statistical_history_facet$;


----------------------------------------------------------------------
-- 4. statistical_unit_facet_reduce: scoped MERGE using snapshot
----------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE worker.statistical_unit_facet_reduce(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $statistical_unit_facet_reduce$
DECLARE
    v_dirty_partitions int[];
    v_row_count bigint;
    v_delete_count bigint;
BEGIN
    -- Read dirty partitions BEFORE anything else, because
    -- statistical_history_facet_reduce (which runs later) truncates them.
    SELECT array_agg(dp.partition_seq)
      INTO v_dirty_partitions
      FROM public.statistical_unit_facet_dirty_partitions AS dp;

    IF v_dirty_partitions IS NULL OR array_length(v_dirty_partitions, 1) IS NULL THEN
        ---------------------------------------------------------------
        -- Full refresh: TRUNCATE + INSERT (original path, unchanged)
        ---------------------------------------------------------------
        TRUNCATE public.statistical_unit_facet;

        INSERT INTO public.statistical_unit_facet
            (valid_from, valid_to, valid_until, unit_type,
             physical_region_path, primary_activity_category_path,
             sector_path, legal_form_id, physical_country_id, status_id,
             count, stats_summary)
        SELECT s.valid_from, s.valid_to, s.valid_until, s.unit_type,
               s.physical_region_path, s.primary_activity_category_path,
               s.sector_path, s.legal_form_id, s.physical_country_id, s.status_id,
               SUM(s.count)::BIGINT,
               jsonb_stats_merge_agg(s.stats_summary)
          FROM public.statistical_unit_facet_staging AS s
         GROUP BY s.valid_from, s.valid_to, s.valid_until, s.unit_type,
                  s.physical_region_path, s.primary_activity_category_path,
                  s.sector_path, s.legal_form_id, s.physical_country_id, s.status_id;
        GET DIAGNOSTICS v_row_count := ROW_COUNT;

        p_info := jsonb_build_object('mode', 'full', 'rows_reduced', v_row_count);
    ELSIF array_length(v_dirty_partitions, 1) <= 128 THEN
        ---------------------------------------------------------------
        -- Path B: Scoped MERGE (few dirty partitions).
        -- Uses row-value IN with ::text cast for Hash Join (3.8s verified).
        -- Only re-aggregates dim combos from dirty partitions + snapshot.
        ---------------------------------------------------------------

        -- Scoped aggregate using row-value IN (::text cast = Hash Join)
        IF to_regclass('pg_temp._scoped_agg') IS NOT NULL THEN
            DROP TABLE _scoped_agg;
        END IF;
        CREATE TEMP TABLE _scoped_agg ON COMMIT DROP AS
        SELECT s.valid_from, s.valid_to, s.valid_until, s.unit_type,
               s.physical_region_path, s.primary_activity_category_path,
               s.sector_path, s.legal_form_id, s.physical_country_id, s.status_id,
               SUM(s.count)::BIGINT AS count,
               jsonb_stats_merge_agg(s.stats_summary) AS stats_summary
        FROM public.statistical_unit_facet_staging AS s
        WHERE (s.valid_from, s.valid_to,
               COALESCE(s.valid_until, 'infinity'::date), s.unit_type,
               COALESCE(s.physical_region_path::text, ''),
               COALESCE(s.primary_activity_category_path::text, ''),
               COALESCE(s.sector_path::text, ''),
               COALESCE(s.legal_form_id, -1),
               COALESCE(s.physical_country_id, -1),
               COALESCE(s.status_id, -1))
            IN (
                -- Current staging dims for dirty partitions (new/changed)
                SELECT d.valid_from, d.valid_to,
                       COALESCE(d.valid_until, 'infinity'::date), d.unit_type,
                       COALESCE(d.physical_region_path::text, ''),
                       COALESCE(d.primary_activity_category_path::text, ''),
                       COALESCE(d.sector_path::text, ''),
                       COALESCE(d.legal_form_id, -1),
                       COALESCE(d.physical_country_id, -1),
                       COALESCE(d.status_id, -1)
                FROM public.statistical_unit_facet_staging AS d
                WHERE d.partition_seq = ANY(v_dirty_partitions)
                UNION
                -- Pre-dirty snapshot (disappeared combos)
                SELECT p.valid_from, p.valid_to,
                       COALESCE(p.valid_until, 'infinity'::date), p.unit_type,
                       COALESCE(p.physical_region_path::text, ''),
                       COALESCE(p.primary_activity_category_path::text, ''),
                       COALESCE(p.sector_path::text, ''),
                       COALESCE(p.legal_form_id, -1),
                       COALESCE(p.physical_country_id, -1),
                       COALESCE(p.status_id, -1)
                FROM public.statistical_unit_facet_pre_dirty_dims AS p
            )
        GROUP BY s.valid_from, s.valid_to, s.valid_until, s.unit_type,
                 s.physical_region_path, s.primary_activity_category_path,
                 s.sector_path, s.legal_form_id, s.physical_country_id, s.status_id;

        -- Scoped MERGE into final table
        MERGE INTO public.statistical_unit_facet AS target
        USING _scoped_agg AS source
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
                         source.count, source.stats_summary);
        GET DIAGNOSTICS v_row_count := ROW_COUNT;

        -- DELETE stale combos (in snapshot but not in scoped aggregate)
        DELETE FROM public.statistical_unit_facet AS f
        WHERE (f.valid_from, f.valid_to,
               COALESCE(f.valid_until, 'infinity'::date), f.unit_type,
               COALESCE(f.physical_region_path::text, ''),
               COALESCE(f.primary_activity_category_path::text, ''),
               COALESCE(f.sector_path::text, ''),
               COALESCE(f.legal_form_id, -1),
               COALESCE(f.physical_country_id, -1),
               COALESCE(f.status_id, -1))
            IN (
                SELECT p.valid_from, p.valid_to,
                       COALESCE(p.valid_until, 'infinity'::date), p.unit_type,
                       COALESCE(p.physical_region_path::text, ''),
                       COALESCE(p.primary_activity_category_path::text, ''),
                       COALESCE(p.sector_path::text, ''),
                       COALESCE(p.legal_form_id, -1),
                       COALESCE(p.physical_country_id, -1),
                       COALESCE(p.status_id, -1)
                FROM public.statistical_unit_facet_pre_dirty_dims AS p
            )
            AND NOT EXISTS (
                SELECT 1 FROM _scoped_agg AS a
                WHERE a.valid_from = f.valid_from
                  AND a.valid_to = f.valid_to
                  AND COALESCE(a.valid_until, 'infinity'::date) = COALESCE(f.valid_until, 'infinity'::date)
                  AND a.unit_type = f.unit_type
                  AND COALESCE(a.physical_region_path::text, '') = COALESCE(f.physical_region_path::text, '')
                  AND COALESCE(a.primary_activity_category_path::text, '') = COALESCE(f.primary_activity_category_path::text, '')
                  AND COALESCE(a.sector_path::text, '') = COALESCE(f.sector_path::text, '')
                  AND COALESCE(a.legal_form_id, -1) = COALESCE(f.legal_form_id, -1)
                  AND COALESCE(a.physical_country_id, -1) = COALESCE(f.physical_country_id, -1)
                  AND COALESCE(a.status_id, -1) = COALESCE(f.status_id, -1)
            );
        GET DIAGNOSTICS v_delete_count := ROW_COUNT;

        p_info := jsonb_build_object(
            'mode', 'scoped',
            'dirty_partitions', to_jsonb(v_dirty_partitions),
            'rows_merged', v_row_count,
            'rows_deleted', v_delete_count);
    ELSE
        ---------------------------------------------------------------
        -- Path C: Full MERGE (many dirty partitions > 128).
        -- Full aggregate is faster than scoped when most partitions dirty.
        ---------------------------------------------------------------
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
            'mode', 'incremental',
            'dirty_partitions', to_jsonb(v_dirty_partitions),
            'rows_merged', v_row_count);
    END IF;
END;
$statistical_unit_facet_reduce$;


----------------------------------------------------------------------
-- 5. statistical_history_facet_reduce: scoped MERGE using snapshot
----------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE worker.statistical_history_facet_reduce(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $statistical_history_facet_reduce$
DECLARE
    v_dirty_partitions int[];
    v_row_count bigint;
    v_delete_count bigint;
BEGIN
    -- Read dirty partitions before truncating them at the end.
    SELECT array_agg(dp.partition_seq)
      INTO v_dirty_partitions
      FROM public.statistical_unit_facet_dirty_partitions AS dp;

    IF v_dirty_partitions IS NULL OR array_length(v_dirty_partitions, 1) IS NULL THEN
        ---------------------------------------------------------------
        -- Full refresh: drop indexes, TRUNCATE + INSERT, rebuild indexes
        ---------------------------------------------------------------
        DROP INDEX IF EXISTS public.idx_statistical_history_facet_year;
        DROP INDEX IF EXISTS public.idx_statistical_history_facet_month;
        DROP INDEX IF EXISTS public.idx_statistical_history_facet_unit_type;
        DROP INDEX IF EXISTS public.idx_statistical_history_facet_primary_activity_category_path;
        DROP INDEX IF EXISTS public.idx_gist_statistical_history_facet_primary_activity_category_pa;
        DROP INDEX IF EXISTS public.idx_statistical_history_facet_secondary_activity_category_path;
        DROP INDEX IF EXISTS public.idx_gist_statistical_history_facet_secondary_activity_category_;
        DROP INDEX IF EXISTS public.idx_statistical_history_facet_sector_path;
        DROP INDEX IF EXISTS public.idx_gist_statistical_history_facet_sector_path;
        DROP INDEX IF EXISTS public.idx_statistical_history_facet_legal_form_id;
        DROP INDEX IF EXISTS public.idx_statistical_history_facet_physical_region_path;
        DROP INDEX IF EXISTS public.idx_gist_statistical_history_facet_physical_region_path;
        DROP INDEX IF EXISTS public.idx_statistical_history_facet_physical_country_id;
        DROP INDEX IF EXISTS public.idx_statistical_history_facet_stats_summary;
        DROP INDEX IF EXISTS public.statistical_history_facet_month_key;
        DROP INDEX IF EXISTS public.statistical_history_facet_year_key;

        TRUNCATE public.statistical_history_facet;

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
        GET DIAGNOSTICS v_row_count := ROW_COUNT;

        CREATE UNIQUE INDEX statistical_history_facet_month_key
            ON public.statistical_history_facet (resolution, year, month, unit_type,
                primary_activity_category_path, secondary_activity_category_path,
                sector_path, legal_form_id, physical_region_path, physical_country_id)
            WHERE resolution = 'year-month'::public.history_resolution;
        CREATE UNIQUE INDEX statistical_history_facet_year_key
            ON public.statistical_history_facet (year, month, unit_type,
                primary_activity_category_path, secondary_activity_category_path,
                sector_path, legal_form_id, physical_region_path, physical_country_id)
            WHERE resolution = 'year'::public.history_resolution;
        CREATE INDEX idx_statistical_history_facet_year ON public.statistical_history_facet (year);
        CREATE INDEX idx_statistical_history_facet_month ON public.statistical_history_facet (month);
        CREATE INDEX idx_statistical_history_facet_unit_type ON public.statistical_history_facet (unit_type);
        CREATE INDEX idx_statistical_history_facet_primary_activity_category_path ON public.statistical_history_facet (primary_activity_category_path);
        CREATE INDEX idx_gist_statistical_history_facet_primary_activity_category_pa ON public.statistical_history_facet USING GIST (primary_activity_category_path);
        CREATE INDEX idx_statistical_history_facet_secondary_activity_category_path ON public.statistical_history_facet (secondary_activity_category_path);
        CREATE INDEX idx_gist_statistical_history_facet_secondary_activity_category_ ON public.statistical_history_facet USING GIST (secondary_activity_category_path);
        CREATE INDEX idx_statistical_history_facet_sector_path ON public.statistical_history_facet (sector_path);
        CREATE INDEX idx_gist_statistical_history_facet_sector_path ON public.statistical_history_facet USING GIST (sector_path);
        CREATE INDEX idx_statistical_history_facet_legal_form_id ON public.statistical_history_facet (legal_form_id);
        CREATE INDEX idx_statistical_history_facet_physical_region_path ON public.statistical_history_facet (physical_region_path);
        CREATE INDEX idx_gist_statistical_history_facet_physical_region_path ON public.statistical_history_facet USING GIST (physical_region_path);
        CREATE INDEX idx_statistical_history_facet_physical_country_id ON public.statistical_history_facet (physical_country_id);
        CREATE INDEX idx_statistical_history_facet_stats_summary ON public.statistical_history_facet USING GIN (stats_summary jsonb_path_ops);

        p_info := jsonb_build_object('mode', 'full', 'rows_reduced', v_row_count);
    ELSIF array_length(v_dirty_partitions, 1) <= 128 THEN
        ---------------------------------------------------------------
        -- Path B: Scoped MERGE (few dirty partitions).
        -- Uses row-value IN with ::text cast for Hash Join.
        ---------------------------------------------------------------

        -- Scoped aggregate using row-value IN (::text cast = Hash Join)
        IF to_regclass('pg_temp._scoped_history_agg') IS NOT NULL THEN
            DROP TABLE _scoped_history_agg;
        END IF;
        CREATE TEMP TABLE _scoped_history_agg ON COMMIT DROP AS
        SELECT
            s.resolution, s.year, s.month, s.unit_type,
            s.primary_activity_category_path, s.secondary_activity_category_path,
            s.sector_path, s.legal_form_id, s.physical_region_path,
            s.physical_country_id, s.unit_size_id, s.status_id,
            SUM(s.exists_count)::integer AS exists_count,
            SUM(s.exists_change)::integer AS exists_change,
            SUM(s.exists_added_count)::integer AS exists_added_count,
            SUM(s.exists_removed_count)::integer AS exists_removed_count,
            SUM(s.countable_count)::integer AS countable_count,
            SUM(s.countable_change)::integer AS countable_change,
            SUM(s.countable_added_count)::integer AS countable_added_count,
            SUM(s.countable_removed_count)::integer AS countable_removed_count,
            SUM(s.births)::integer AS births,
            SUM(s.deaths)::integer AS deaths,
            SUM(s.name_change_count)::integer AS name_change_count,
            SUM(s.primary_activity_category_change_count)::integer AS primary_activity_category_change_count,
            SUM(s.secondary_activity_category_change_count)::integer AS secondary_activity_category_change_count,
            SUM(s.sector_change_count)::integer AS sector_change_count,
            SUM(s.legal_form_change_count)::integer AS legal_form_change_count,
            SUM(s.physical_region_change_count)::integer AS physical_region_change_count,
            SUM(s.physical_country_change_count)::integer AS physical_country_change_count,
            SUM(s.physical_address_change_count)::integer AS physical_address_change_count,
            SUM(s.unit_size_change_count)::integer AS unit_size_change_count,
            SUM(s.status_change_count)::integer AS status_change_count,
            jsonb_stats_merge_agg(s.stats_summary) AS stats_summary
        FROM public.statistical_history_facet_partitions AS s
        WHERE (s.resolution::text, s.year, COALESCE(s.month, -1), s.unit_type::text,
               COALESCE(s.primary_activity_category_path::text, ''),
               COALESCE(s.secondary_activity_category_path::text, ''),
               COALESCE(s.sector_path::text, ''),
               COALESCE(s.legal_form_id, -1),
               COALESCE(s.physical_region_path::text, ''),
               COALESCE(s.physical_country_id, -1),
               COALESCE(s.unit_size_id, -1),
               COALESCE(s.status_id, -1))
            IN (
                SELECT d.resolution::text, d.year, COALESCE(d.month, -1), d.unit_type::text,
                       COALESCE(d.primary_activity_category_path::text, ''),
                       COALESCE(d.secondary_activity_category_path::text, ''),
                       COALESCE(d.sector_path::text, ''),
                       COALESCE(d.legal_form_id, -1),
                       COALESCE(d.physical_region_path::text, ''),
                       COALESCE(d.physical_country_id, -1),
                       COALESCE(d.unit_size_id, -1),
                       COALESCE(d.status_id, -1)
                FROM public.statistical_history_facet_partitions AS d
                WHERE d.partition_seq = ANY(v_dirty_partitions)
                UNION
                SELECT p.resolution::text, p.year, COALESCE(p.month, -1), p.unit_type::text,
                       COALESCE(p.primary_activity_category_path::text, ''),
                       COALESCE(p.secondary_activity_category_path::text, ''),
                       COALESCE(p.sector_path::text, ''),
                       COALESCE(p.legal_form_id, -1),
                       COALESCE(p.physical_region_path::text, ''),
                       COALESCE(p.physical_country_id, -1),
                       COALESCE(p.unit_size_id, -1),
                       COALESCE(p.status_id, -1)
                FROM public.statistical_history_facet_pre_dirty_dims AS p
            )
        GROUP BY s.resolution, s.year, s.month, s.unit_type,
                 s.primary_activity_category_path, s.secondary_activity_category_path,
                 s.sector_path, s.legal_form_id, s.physical_region_path,
                 s.physical_country_id, s.unit_size_id, s.status_id;

        -- Scoped MERGE
        MERGE INTO public.statistical_history_facet AS target
        USING _scoped_history_agg AS source
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
             OR target.exists_change <> source.exists_change
             OR target.exists_added_count <> source.exists_added_count
             OR target.exists_removed_count <> source.exists_removed_count
             OR target.countable_count <> source.countable_count
             OR target.countable_change <> source.countable_change
             OR target.countable_added_count <> source.countable_added_count
             OR target.countable_removed_count <> source.countable_removed_count
             OR target.births <> source.births
             OR target.deaths <> source.deaths
             OR target.name_change_count <> source.name_change_count
             OR target.primary_activity_category_change_count <> source.primary_activity_category_change_count
             OR target.secondary_activity_category_change_count <> source.secondary_activity_category_change_count
             OR target.sector_change_count <> source.sector_change_count
             OR target.legal_form_change_count <> source.legal_form_change_count
             OR target.physical_region_change_count <> source.physical_region_change_count
             OR target.physical_country_change_count <> source.physical_country_change_count
             OR target.physical_address_change_count <> source.physical_address_change_count
             OR target.unit_size_change_count <> source.unit_size_change_count
             OR target.status_change_count <> source.status_change_count
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
                source.stats_summary);
        GET DIAGNOSTICS v_row_count := ROW_COUNT;

        -- DELETE stale combos (in snapshot but not in scoped aggregate)
        DELETE FROM public.statistical_history_facet AS f
        WHERE (f.resolution::text, f.year, COALESCE(f.month, -1), f.unit_type::text,
               COALESCE(f.primary_activity_category_path::text, ''),
               COALESCE(f.secondary_activity_category_path::text, ''),
               COALESCE(f.sector_path::text, ''),
               COALESCE(f.legal_form_id, -1),
               COALESCE(f.physical_region_path::text, ''),
               COALESCE(f.physical_country_id, -1),
               COALESCE(f.unit_size_id, -1),
               COALESCE(f.status_id, -1))
            IN (
                SELECT p.resolution::text, p.year, COALESCE(p.month, -1), p.unit_type::text,
                       COALESCE(p.primary_activity_category_path::text, ''),
                       COALESCE(p.secondary_activity_category_path::text, ''),
                       COALESCE(p.sector_path::text, ''),
                       COALESCE(p.legal_form_id, -1),
                       COALESCE(p.physical_region_path::text, ''),
                       COALESCE(p.physical_country_id, -1),
                       COALESCE(p.unit_size_id, -1),
                       COALESCE(p.status_id, -1)
                FROM public.statistical_history_facet_pre_dirty_dims AS p
            )
            AND NOT EXISTS (
                SELECT 1 FROM _scoped_history_agg AS a
                WHERE a.resolution = f.resolution
                  AND a.year = f.year
                  AND COALESCE(a.month, -1) = COALESCE(f.month, -1)
                  AND a.unit_type = f.unit_type
                  AND COALESCE(a.primary_activity_category_path::text, '') = COALESCE(f.primary_activity_category_path::text, '')
                  AND COALESCE(a.secondary_activity_category_path::text, '') = COALESCE(f.secondary_activity_category_path::text, '')
                  AND COALESCE(a.sector_path::text, '') = COALESCE(f.sector_path::text, '')
                  AND COALESCE(a.legal_form_id, -1) = COALESCE(f.legal_form_id, -1)
                  AND COALESCE(a.physical_region_path::text, '') = COALESCE(f.physical_region_path::text, '')
                  AND COALESCE(a.physical_country_id, -1) = COALESCE(f.physical_country_id, -1)
                  AND COALESCE(a.unit_size_id, -1) = COALESCE(f.unit_size_id, -1)
                  AND COALESCE(a.status_id, -1) = COALESCE(f.status_id, -1)
            );
        GET DIAGNOSTICS v_delete_count := ROW_COUNT;

        p_info := jsonb_build_object(
            'mode', 'scoped',
            'dirty_partitions', to_jsonb(v_dirty_partitions),
            'rows_merged', v_row_count,
            'rows_deleted', v_delete_count);
    ELSE
        ---------------------------------------------------------------
        -- Path C: Full MERGE (many dirty partitions > 128).
        -- Skip index drop/rebuild since MERGE preserves indexes.
        ---------------------------------------------------------------
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
            'mode', 'incremental',
            'dirty_partitions', to_jsonb(v_dirty_partitions),
            'rows_merged', v_row_count);
    END IF;

    -- Clean up dirty partitions at the very end, after all consumers have read them
    TRUNCATE public.statistical_unit_facet_dirty_partitions;

    PERFORM pg_notify('worker_status',
        json_build_object('type', 'is_deriving_reports', 'status', false)::text);
END;
$statistical_history_facet_reduce$;

END;
