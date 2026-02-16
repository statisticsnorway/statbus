-- Migration 20260215152154: inline_statistical_unit_facet_partitions
--
-- Move partition data from UNLOGGED staging table into the main statistical_unit_facet
-- table as inline partition entries (partition_seq IS NOT NULL). Root entries (partition_seq
-- IS NULL) are recalculated by summing across partition entries in the reduce step.
--
-- Benefits:
-- - Logged writes (crash-safe, no data loss)
-- - No integrity check needed (no UNLOGGED table)
-- - Unified table, no staging table to manage
-- - Backup/restore captures partition entries → first cycle after restore is incremental
BEGIN;

-- =====================================================================
-- 1. Add partition_seq column and drop old indexes
-- =====================================================================
ALTER TABLE public.statistical_unit_facet ADD COLUMN partition_seq integer;

-- Drop old non-partial indexes BEFORE inserting partition data
-- (old unique index would reject staging rows that share facet keys with root rows)
DROP INDEX IF EXISTS public.statistical_unit_facet_key;
DROP INDEX IF EXISTS public.statistical_unit_facet_legal_form_id_btree;
DROP INDEX IF EXISTS public.statistical_unit_facet_physical_country_id_btree;
DROP INDEX IF EXISTS public.statistical_unit_facet_physical_region_path_btree;
DROP INDEX IF EXISTS public.statistical_unit_facet_physical_region_path_gist;
DROP INDEX IF EXISTS public.statistical_unit_facet_primary_activity_category_path_btree;
DROP INDEX IF EXISTS public.statistical_unit_facet_primary_activity_category_path_gist;
DROP INDEX IF EXISTS public.statistical_unit_facet_sector_path_btree;
DROP INDEX IF EXISTS public.statistical_unit_facet_sector_path_gist;
DROP INDEX IF EXISTS public.statistical_unit_facet_unit_type;
DROP INDEX IF EXISTS public.statistical_unit_facet_valid_from;
DROP INDEX IF EXISTS public.statistical_unit_facet_valid_until;

-- =====================================================================
-- 2. Copy partition data from staging into main table
-- =====================================================================
INSERT INTO public.statistical_unit_facet (
    partition_seq, valid_from, valid_to, valid_until, unit_type,
    physical_region_path, primary_activity_category_path,
    sector_path, legal_form_id, physical_country_id, status_id,
    count, stats_summary
)
SELECT
    s.partition_seq, s.valid_from, s.valid_to, s.valid_until, s.unit_type,
    s.physical_region_path, s.primary_activity_category_path,
    s.sector_path, s.legal_form_id, s.physical_country_id, s.status_id,
    s.count, s.stats_summary
FROM public.statistical_unit_facet_staging AS s;

-- =====================================================================
-- 3. Create new partial indexes
-- =====================================================================

-- Root entry unique constraint
CREATE UNIQUE INDEX statistical_unit_facet_key
    ON public.statistical_unit_facet (valid_from, valid_to, valid_until, unit_type,
        physical_region_path, primary_activity_category_path,
        sector_path, legal_form_id, physical_country_id, status_id)
    NULLS NOT DISTINCT
    WHERE partition_seq IS NULL;

-- Partition entry unique constraint
CREATE UNIQUE INDEX statistical_unit_facet_partition_key
    ON public.statistical_unit_facet (partition_seq, valid_from, valid_to, valid_until, unit_type,
        physical_region_path, primary_activity_category_path,
        sector_path, legal_form_id, physical_country_id, status_id)
    NULLS NOT DISTINCT
    WHERE partition_seq IS NOT NULL;

-- Performance indexes (root entries only)
CREATE INDEX statistical_unit_facet_legal_form_id_btree
    ON public.statistical_unit_facet (legal_form_id) WHERE partition_seq IS NULL;
CREATE INDEX statistical_unit_facet_physical_country_id_btree
    ON public.statistical_unit_facet (physical_country_id) WHERE partition_seq IS NULL;
CREATE INDEX statistical_unit_facet_physical_region_path_btree
    ON public.statistical_unit_facet (physical_region_path) WHERE partition_seq IS NULL;
CREATE INDEX statistical_unit_facet_physical_region_path_gist
    ON public.statistical_unit_facet USING gist (physical_region_path) WHERE partition_seq IS NULL;
CREATE INDEX statistical_unit_facet_primary_activity_category_path_btree
    ON public.statistical_unit_facet (primary_activity_category_path) WHERE partition_seq IS NULL;
CREATE INDEX statistical_unit_facet_primary_activity_category_path_gist
    ON public.statistical_unit_facet USING gist (primary_activity_category_path) WHERE partition_seq IS NULL;
CREATE INDEX statistical_unit_facet_sector_path_btree
    ON public.statistical_unit_facet (sector_path) WHERE partition_seq IS NULL;
CREATE INDEX statistical_unit_facet_sector_path_gist
    ON public.statistical_unit_facet USING gist (sector_path) WHERE partition_seq IS NULL;
CREATE INDEX statistical_unit_facet_unit_type
    ON public.statistical_unit_facet (unit_type) WHERE partition_seq IS NULL;
CREATE INDEX statistical_unit_facet_valid_from
    ON public.statistical_unit_facet (valid_from) WHERE partition_seq IS NULL;
CREATE INDEX statistical_unit_facet_valid_until
    ON public.statistical_unit_facet (valid_until) WHERE partition_seq IS NULL;

-- Partition cleanup index
CREATE INDEX idx_statistical_unit_facet_partition_seq
    ON public.statistical_unit_facet (partition_seq) WHERE partition_seq IS NOT NULL;

-- =====================================================================
-- 4. Update RLS policies to hide partition entries
-- =====================================================================
DROP POLICY IF EXISTS statistical_unit_facet_authenticated_read ON public.statistical_unit_facet;
DROP POLICY IF EXISTS statistical_unit_facet_regular_user_read ON public.statistical_unit_facet;

CREATE POLICY statistical_unit_facet_authenticated_read ON public.statistical_unit_facet
    FOR SELECT TO authenticated USING (partition_seq IS NULL);
CREATE POLICY statistical_unit_facet_regular_user_read ON public.statistical_unit_facet
    FOR SELECT TO regular_user USING (partition_seq IS NULL);

-- =====================================================================
-- 5. Update derive_statistical_unit_facet_partition: write to main table
-- =====================================================================
CREATE OR REPLACE PROCEDURE worker.derive_statistical_unit_facet_partition(IN payload jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
AS $derive_statistical_unit_facet_partition$
DECLARE
    v_partition_seq INT := (payload->>'partition_seq')::int;
BEGIN
    RAISE DEBUG 'derive_statistical_unit_facet_partition: partition_seq=%', v_partition_seq;

    -- Delete existing partition entries for this partition
    DELETE FROM public.statistical_unit_facet
    WHERE partition_seq = v_partition_seq;

    -- Recompute facets for this partition's units
    INSERT INTO public.statistical_unit_facet (
        partition_seq, valid_from, valid_to, valid_until, unit_type,
        physical_region_path, primary_activity_category_path,
        sector_path, legal_form_id, physical_country_id, status_id,
        count, stats_summary
    )
    SELECT v_partition_seq,
           su.valid_from, su.valid_to, su.valid_until, su.unit_type,
           su.physical_region_path, su.primary_activity_category_path,
           su.sector_path, su.legal_form_id, su.physical_country_id, su.status_id,
           COUNT(*)::BIGINT,
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
-- 6. Update statistical_unit_facet_reduce: aggregate inline
-- =====================================================================
CREATE OR REPLACE PROCEDURE worker.statistical_unit_facet_reduce(IN payload jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
AS $statistical_unit_facet_reduce$
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

    -- Delete existing root entries
    DELETE FROM public.statistical_unit_facet WHERE partition_seq IS NULL;

    -- Recalculate root entries by summing across all partition entries
    INSERT INTO public.statistical_unit_facet (
        partition_seq, valid_from, valid_to, valid_until, unit_type,
        physical_region_path, primary_activity_category_path,
        sector_path, legal_form_id, physical_country_id, status_id,
        count, stats_summary
    )
    SELECT
        NULL,  -- root entry
        valid_from, valid_to, valid_until, unit_type,
        physical_region_path, primary_activity_category_path,
        sector_path, legal_form_id, physical_country_id, status_id,
        SUM(count)::BIGINT,
        jsonb_stats_summary_merge_agg(stats_summary)
    FROM public.statistical_unit_facet
    WHERE partition_seq IS NOT NULL
    GROUP BY valid_from, valid_to, valid_until, unit_type,
             physical_region_path, primary_activity_category_path,
             sector_path, legal_form_id, physical_country_id, status_id;

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
$statistical_unit_facet_reduce$;

-- =====================================================================
-- 7. Update derive_statistical_unit_facet: no staging integrity check
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
    v_child_count INT := 0;
    v_i INT;
BEGIN
    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY id DESC LIMIT 1;

    RAISE DEBUG 'derive_statistical_unit_facet: task_id=%, valid_from=%, valid_until=%',
                 v_task_id, v_valid_from, v_valid_until;

    -- Snapshot dirty partitions
    SELECT array_agg(partition_seq ORDER BY partition_seq) INTO v_dirty_partitions
    FROM public.statistical_unit_facet_dirty_partitions;

    -- If no partition entries exist yet, force full refresh
    IF NOT EXISTS (SELECT 1 FROM public.statistical_unit_facet WHERE partition_seq IS NOT NULL LIMIT 1) THEN
        v_dirty_partitions := NULL;
        RAISE DEBUG 'derive_statistical_unit_facet: No partition entries exist, forcing full refresh';
    END IF;

    -- Enqueue reduce uncle task with dirty partitions snapshot
    PERFORM worker.enqueue_statistical_unit_facet_reduce(
        p_valid_from => v_valid_from,
        p_valid_until => v_valid_until,
        p_dirty_partitions => v_dirty_partitions
    );

    -- Spawn partition children
    IF v_dirty_partitions IS NULL THEN
        RAISE DEBUG 'derive_statistical_unit_facet: Full refresh — spawning all partition children';
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
END;
$derive_statistical_unit_facet$;

-- =====================================================================
-- 8. Drop staging table (data now inline)
-- =====================================================================
DROP TABLE IF EXISTS public.statistical_unit_facet_staging;

END;
