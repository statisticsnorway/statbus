-- Migration 20260210193343: partition_statistical_unit_facet
--
-- Optimizes statistical_unit_facet derivation via partitioned map-reduce:
-- - 128 hash partitions for concurrent partial recomputation
-- - Dirty partition tracking for targeted refreshes (single unit → 1 partition)
-- - Native PG LIST partitioning for per-partition index isolation
-- - Crash recovery via integrity check before partial refresh
BEGIN;

-- =====================================================================
-- 1. Helper functions: compute report partition sequence number
-- =====================================================================

-- Overload for text unit_type (used in dirty partition tracking from derive_statistical_unit)
CREATE FUNCTION public.report_partition_seq(
    p_unit_type text, p_unit_id int, p_num_partitions int DEFAULT 128
) RETURNS int
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $report_partition_seq$
    SELECT abs(hashtext(p_unit_type || ':' || p_unit_id::text)) % p_num_partitions;
$report_partition_seq$;

-- Overload for enum unit_type (used in GENERATED ALWAYS columns)
-- Declared IMMUTABLE so PG allows it in generated columns.
-- The enum→text cast is technically STABLE, but the hash result is deterministic
-- for the lifetime of the enum type, which never changes.
CREATE FUNCTION public.report_partition_seq(
    p_unit_type public.statistical_unit_type, p_unit_id int, p_num_partitions int DEFAULT 128
) RETURNS int
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $report_partition_seq$
    SELECT abs(hashtext(p_unit_type::text || ':' || p_unit_id::text)) % p_num_partitions;
$report_partition_seq$;

-- =====================================================================
-- 2. Add report_partition_seq stored column to statistical_unit & staging
-- =====================================================================
ALTER TABLE public.statistical_unit ADD COLUMN report_partition_seq INT
    GENERATED ALWAYS AS (public.report_partition_seq(unit_type, unit_id)) STORED;

CREATE INDEX idx_statistical_unit_report_partition_seq
    ON public.statistical_unit (report_partition_seq);

ALTER TABLE public.statistical_unit_staging ADD COLUMN report_partition_seq INT
    GENERATED ALWAYS AS (public.report_partition_seq(unit_type, unit_id)) STORED;

-- =====================================================================
-- 3. Dirty partition tracking table (UNLOGGED — derived data)
-- =====================================================================
CREATE UNLOGGED TABLE public.statistical_unit_facet_dirty_partitions (
    partition_seq INT PRIMARY KEY
);

-- =====================================================================
-- 4. Partition intermediate table (UNLOGGED, logical partitions via partition_seq)
-- =====================================================================
-- Plain UNLOGGED table with logical partitioning by partition_seq column.
-- No physical PG partitioning — avoids 128 child tables in the schema.
-- Concurrent children write to different partition_seq values with no key conflicts.
CREATE UNLOGGED TABLE public.statistical_unit_facet_staging (
    partition_seq INT NOT NULL,
    valid_from DATE,
    valid_to DATE,
    valid_until DATE,
    unit_type public.statistical_unit_type,
    physical_region_path ltree,
    primary_activity_category_path ltree,
    sector_path ltree,
    legal_form_id INT,
    physical_country_id INT,
    status_id INT,
    count INT NOT NULL,
    stats_summary JSONB,
    UNIQUE NULLS NOT DISTINCT (partition_seq, valid_from, valid_to, valid_until, unit_type,
            physical_region_path, primary_activity_category_path, sector_path,
            legal_form_id, physical_country_id, status_id)
);

CREATE INDEX idx_statistical_unit_facet_staging_partition_seq
    ON public.statistical_unit_facet_staging (partition_seq);

-- =====================================================================
-- 5. New command registry entries
-- =====================================================================
INSERT INTO worker.command_registry (command, handler_procedure, description, queue)
VALUES
    ('derive_statistical_unit_facet_partition',
     'worker.derive_statistical_unit_facet_partition',
     'Recompute statistical_unit_facet for a single hash partition (parallel-safe, child task)',
     'analytics'),
    ('statistical_unit_facet_reduce',
     'worker.statistical_unit_facet_reduce',
     'Aggregate partitioned facets into final statistical_unit_facet table',
     'analytics');

-- =====================================================================
-- 6. Deduplication indexes for new commands
-- =====================================================================
CREATE UNIQUE INDEX idx_tasks_derive_statistical_unit_facet_partition_dedup
    ON worker.tasks (command, ((payload->>'partition_seq')::int))
    WHERE command = 'derive_statistical_unit_facet_partition' AND state = 'pending';

CREATE UNIQUE INDEX idx_tasks_statistical_unit_facet_reduce_dedup
    ON worker.tasks (command)
    WHERE command = 'statistical_unit_facet_reduce' AND state = 'pending';

-- =====================================================================
-- 7. Enqueue function for reduce (with deduplication)
-- =====================================================================
CREATE FUNCTION worker.enqueue_statistical_unit_facet_reduce(
    p_valid_from date DEFAULT NULL, p_valid_until date DEFAULT NULL
) RETURNS bigint
LANGUAGE plpgsql
AS $enqueue_statistical_unit_facet_reduce$
DECLARE
    v_task_id BIGINT;
    v_valid_from DATE := COALESCE(p_valid_from, '-infinity'::DATE);
    v_valid_until DATE := COALESCE(p_valid_until, 'infinity'::DATE);
BEGIN
    INSERT INTO worker.tasks AS t (command, payload)
    VALUES ('statistical_unit_facet_reduce', jsonb_build_object(
        'command', 'statistical_unit_facet_reduce',
        'valid_from', v_valid_from,
        'valid_until', v_valid_until
    ))
    ON CONFLICT (command)
    WHERE command = 'statistical_unit_facet_reduce' AND state = 'pending'::worker.task_state
    DO UPDATE SET
        payload = jsonb_build_object(
            'command', 'statistical_unit_facet_reduce',
            'valid_from', LEAST((t.payload->>'valid_from')::date, (EXCLUDED.payload->>'valid_from')::date),
            'valid_until', GREATEST((t.payload->>'valid_until')::date, (EXCLUDED.payload->>'valid_until')::date)
        ),
        state = 'pending'::worker.task_state
    RETURNING id INTO v_task_id;

    RETURN v_task_id;
END;
$enqueue_statistical_unit_facet_reduce$;

-- =====================================================================
-- 8. Partition child procedure: recompute facets for one partition
-- =====================================================================
CREATE PROCEDURE worker.derive_statistical_unit_facet_partition(IN payload jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
AS $derive_statistical_unit_facet_partition$
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
           jsonb_stats_summary_merge_agg(su.stats_summary)
    FROM public.statistical_unit AS su
    WHERE su.used_for_counting
      AND su.report_partition_seq = v_partition_seq
    GROUP BY su.valid_from, su.valid_to, su.valid_until, su.unit_type,
             su.physical_region_path, su.primary_activity_category_path,
             su.sector_path, su.legal_form_id, su.physical_country_id, su.status_id;

    RAISE DEBUG 'derive_statistical_unit_facet_partition: partition_seq=% done', v_partition_seq;
END;
$derive_statistical_unit_facet_partition$;

-- =====================================================================
-- 9. Reduce procedure: aggregate partitions → final facet table
-- =====================================================================
CREATE PROCEDURE worker.statistical_unit_facet_reduce(IN payload jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
AS $statistical_unit_facet_reduce$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
BEGIN
    RAISE DEBUG 'statistical_unit_facet_reduce: valid_from=%, valid_until=%', v_valid_from, v_valid_until;

    -- Full re-derive from partition table
    -- The partition table holds pre-aggregated facets per partition;
    -- we SUM counts and merge stats_summary across all partitions.
    DELETE FROM public.statistical_unit_facet;

    INSERT INTO public.statistical_unit_facet
    SELECT sufp.valid_from, sufp.valid_to, sufp.valid_until, sufp.unit_type,
           sufp.physical_region_path, sufp.primary_activity_category_path,
           sufp.sector_path, sufp.legal_form_id, sufp.physical_country_id, sufp.status_id,
           SUM(sufp.count)::BIGINT,
           jsonb_stats_summary_merge_agg(sufp.stats_summary)
    FROM public.statistical_unit_facet_staging AS sufp
    GROUP BY sufp.valid_from, sufp.valid_to, sufp.valid_until, sufp.unit_type,
             sufp.physical_region_path, sufp.primary_activity_category_path,
             sufp.sector_path, sufp.legal_form_id, sufp.physical_country_id, sufp.status_id;

    -- Clear dirty tracking
    TRUNCATE public.statistical_unit_facet_dirty_partitions;

    -- Enqueue next phase: derive_statistical_history_facet
    PERFORM worker.enqueue_derive_statistical_history_facet(
        p_valid_from => v_valid_from,
        p_valid_until => v_valid_until
    );

    RAISE DEBUG 'statistical_unit_facet_reduce: done, enqueued derive_statistical_history_facet';
END;
$statistical_unit_facet_reduce$;

-- =====================================================================
-- 10. Modified derive_statistical_unit: add dirty partition tracking
-- =====================================================================
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
    v_uncle_priority BIGINT;
    v_orphan_enterprise_ids INT[];
    v_orphan_legal_unit_ids INT[];
    v_orphan_establishment_ids INT[];
BEGIN
    v_is_full_refresh := (p_establishment_id_ranges IS NULL
                         AND p_legal_unit_id_ranges IS NULL
                         AND p_enterprise_id_ranges IS NULL);

    -- Clean staging from any interrupted previous run
    TRUNCATE public.statistical_unit_staging;

    -- Priority for children: same as current task (will run next due to structured concurrency)
    v_child_priority := nextval('public.worker_task_priority_seq');
    -- Priority for uncle (derive_reports): lower priority (higher number), runs after parent completes
    v_uncle_priority := nextval('public.worker_task_priority_seq');

    IF v_is_full_refresh THEN
        -- Full refresh: spawn batch children (no orphan cleanup needed - covers everything)
        -- No dirty partition tracking needed: full refresh recomputes all 128 partitions
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
        -- DIRTY PARTITION TRACKING: Mark which facet partitions need recomputing
        -- =====================================================================
        INSERT INTO public.statistical_unit_facet_dirty_partitions (partition_seq)
        SELECT DISTINCT public.report_partition_seq(t.unit_type, t.unit_id)
        FROM (
            SELECT 'enterprise'::text AS unit_type, unnest(v_enterprise_ids) AS unit_id
            UNION ALL
            SELECT 'legal_unit', unnest(v_legal_unit_ids)
            UNION ALL
            SELECT 'establishment', unnest(v_establishment_ids)
        ) AS t
        WHERE t.unit_id IS NOT NULL
        ON CONFLICT DO NOTHING;

        RAISE DEBUG 'derive_statistical_unit: Tracked dirty facet partitions for % enterprise, % legal_unit, % establishment IDs',
            COALESCE(array_length(v_enterprise_ids, 1), 0),
            COALESCE(array_length(v_legal_unit_ids, 1), 0),
            COALESCE(array_length(v_establishment_ids, 1), 0);

        -- =====================================================================
        -- BATCHING: Only existing entities, partitioned with no overlap
        -- =====================================================================
        FOR v_batch IN
            SELECT * FROM public.get_closed_group_batches(
                p_target_batch_size := 1000,
                p_establishment_ids := NULLIF(v_establishment_ids, '{}'),
                p_legal_unit_ids := NULLIF(v_legal_unit_ids, '{}'),
                p_enterprise_ids := NULLIF(v_enterprise_ids, '{}')
            )
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

-- =====================================================================
-- 11. Modified derive_statistical_unit_facet: spawn partition children
-- =====================================================================
CREATE OR REPLACE PROCEDURE worker.derive_statistical_unit_facet(IN payload jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
AS $derive_statistical_unit_facet$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
    v_task_id bigint;
    v_dirty_partitions INT[];
    v_populated_partitions INT;
    v_expected_partitions INT;
    v_child_count INT := 0;
    v_i INT;
BEGIN
    -- Get own task_id for spawning children
    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY id DESC LIMIT 1;

    RAISE DEBUG 'derive_statistical_unit_facet: task_id=%, valid_from=%, valid_until=%',
                 v_task_id, v_valid_from, v_valid_until;

    -- =====================================================================
    -- INTEGRITY CHECK: Ensure partition table is fully populated.
    -- UNLOGGED table loses data on crash; also handles first-run case.
    -- If partition table is incomplete, force a full refresh.
    -- =====================================================================
    SELECT COUNT(DISTINCT partition_seq) INTO v_populated_partitions
    FROM public.statistical_unit_facet_staging;

    SELECT COUNT(DISTINCT report_partition_seq) INTO v_expected_partitions
    FROM public.statistical_unit
    WHERE used_for_counting;

    -- Read dirty partitions
    SELECT array_agg(partition_seq ORDER BY partition_seq) INTO v_dirty_partitions
    FROM public.statistical_unit_facet_dirty_partitions;

    IF v_populated_partitions < v_expected_partitions THEN
        -- Partition table lost data (crash or first run) → force full refresh
        v_dirty_partitions := NULL;
        RAISE DEBUG 'derive_statistical_unit_facet: Staging has %/% expected partitions populated, forcing full refresh',
            v_populated_partitions, v_expected_partitions;
    END IF;

    -- Enqueue reduce task (runs after this parent's children complete, as top-level)
    PERFORM worker.enqueue_statistical_unit_facet_reduce(
        p_valid_from => v_valid_from,
        p_valid_until => v_valid_until
    );

    -- Spawn partition children
    IF v_dirty_partitions IS NULL THEN
        -- Full refresh: only partitions that have data
        RAISE DEBUG 'derive_statistical_unit_facet: Full refresh — spawning % partition children (populated)',
            v_expected_partitions;
        FOR v_i IN
            SELECT DISTINCT report_partition_seq
            FROM public.statistical_unit
            WHERE used_for_counting
            ORDER BY report_partition_seq
        LOOP
            PERFORM worker.spawn(
                p_command := 'derive_statistical_unit_facet_partition',
                p_payload := jsonb_build_object(
                    'command', 'derive_statistical_unit_facet_partition',
                    'partition_seq', v_i
                ),
                p_parent_id := v_task_id
            );
            v_child_count := v_child_count + 1;
        END LOOP;
    ELSE
        -- Partial refresh: only dirty partitions
        RAISE DEBUG 'derive_statistical_unit_facet: Partial refresh — spawning % dirty partition children',
            array_length(v_dirty_partitions, 1);
        FOREACH v_i IN ARRAY v_dirty_partitions LOOP
            PERFORM worker.spawn(
                p_command := 'derive_statistical_unit_facet_partition',
                p_payload := jsonb_build_object(
                    'command', 'derive_statistical_unit_facet_partition',
                    'partition_seq', v_i
                ),
                p_parent_id := v_task_id
            );
            v_child_count := v_child_count + 1;
        END LOOP;
    END IF;

    RAISE DEBUG 'derive_statistical_unit_facet: Spawned % partition children', v_child_count;
    -- Returns → process_tasks detects children → state='waiting'
    -- After all children complete, parent auto-completes, then reduce runs as next top-level task
END;
$derive_statistical_unit_facet$;

-- =====================================================================
-- 12. Fix relevant_statistical_units: add report_partition_seq
--     This function RETURNS SETOF statistical_unit, so its SELECT must
--     include all columns of the table, including the new generated column.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.relevant_statistical_units(unit_type statistical_unit_type, unit_id integer, valid_on date DEFAULT CURRENT_DATE)
 RETURNS SETOF statistical_unit
 LANGUAGE sql
 STABLE
AS $relevant_statistical_units$
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
         , invalid_codes
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
$relevant_statistical_units$;

-- =====================================================================
-- 13. Fix get_statistical_unit_data_partial: add report_partition_seq
--     This function RETURNS SETOF statistical_unit, so its SELECT must
--     include all columns of the table, including the new generated column.
-- =====================================================================
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
            public.report_partition_seq(t.unit_type, t.unit_id) AS report_partition_seq
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
            public.report_partition_seq(t.unit_type, t.unit_id) AS report_partition_seq
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
            public.report_partition_seq(t.unit_type, t.unit_id) AS report_partition_seq
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

END;
