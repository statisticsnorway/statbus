-- Down Migration 20260215152154: inline_statistical_unit_facet_partitions
BEGIN;

-- =====================================================================
-- 1. Recreate staging table (UNLOGGED)
-- =====================================================================
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
-- 2. Copy partition entries back to staging
-- =====================================================================
INSERT INTO public.statistical_unit_facet_staging (
    partition_seq, valid_from, valid_to, valid_until, unit_type,
    physical_region_path, primary_activity_category_path,
    sector_path, legal_form_id, physical_country_id, status_id,
    count, stats_summary
)
SELECT
    partition_seq, valid_from, valid_to, valid_until, unit_type,
    physical_region_path, primary_activity_category_path,
    sector_path, legal_form_id, physical_country_id, status_id,
    count::integer, stats_summary
FROM public.statistical_unit_facet
WHERE partition_seq IS NOT NULL;

-- Delete partition entries from main table
DELETE FROM public.statistical_unit_facet WHERE partition_seq IS NOT NULL;

-- =====================================================================
-- 3. Restore original derive_statistical_unit_facet_partition (writes to staging)
-- =====================================================================
CREATE OR REPLACE PROCEDURE worker.derive_statistical_unit_facet_partition(IN payload jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
AS $derive_statistical_unit_facet_partition$
DECLARE
    v_partition_seq INT := (payload->>'partition_seq')::int;
BEGIN
    RAISE DEBUG 'derive_statistical_unit_facet_partition: partition_seq=%', v_partition_seq;

    DELETE FROM public.statistical_unit_facet_staging
    WHERE partition_seq = v_partition_seq;

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
-- 4. Restore original statistical_unit_facet_reduce (from staging)
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

    IF payload->'dirty_partitions' IS NOT NULL AND payload->'dirty_partitions' != 'null'::jsonb THEN
        SELECT array_agg(val::int)
        INTO v_dirty_partitions
        FROM jsonb_array_elements_text(payload->'dirty_partitions') AS val;
    END IF;

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

    IF v_dirty_partitions IS NOT NULL THEN
        DELETE FROM public.statistical_unit_facet_dirty_partitions
        WHERE partition_seq = ANY(v_dirty_partitions);
    ELSE
        TRUNCATE public.statistical_unit_facet_dirty_partitions;
    END IF;

    PERFORM worker.enqueue_derive_statistical_history_facet(
        p_valid_from => v_valid_from,
        p_valid_until => v_valid_until
    );

    RAISE DEBUG 'statistical_unit_facet_reduce: done, enqueued derive_statistical_history_facet';
END;
$statistical_unit_facet_reduce$;

-- =====================================================================
-- 5. Restore original derive_statistical_unit_facet (with staging integrity check)
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

    PERFORM worker.enqueue_statistical_unit_facet_reduce(
        p_valid_from => v_valid_from,
        p_valid_until => v_valid_until,
        p_dirty_partitions => v_dirty_partitions
    );

    IF v_dirty_partitions IS NULL THEN
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
-- 6. Restore original indexes (not partial)
-- =====================================================================
DROP INDEX IF EXISTS public.statistical_unit_facet_key;
DROP INDEX IF EXISTS public.statistical_unit_facet_partition_key;
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
DROP INDEX IF EXISTS public.idx_statistical_unit_facet_partition_seq;

CREATE UNIQUE INDEX statistical_unit_facet_key
    ON public.statistical_unit_facet (valid_from, valid_to, valid_until, unit_type,
        physical_region_path, primary_activity_category_path,
        sector_path, legal_form_id, physical_country_id, status_id)
    NULLS NOT DISTINCT;
CREATE INDEX statistical_unit_facet_legal_form_id_btree
    ON public.statistical_unit_facet (legal_form_id);
CREATE INDEX statistical_unit_facet_physical_country_id_btree
    ON public.statistical_unit_facet (physical_country_id);
CREATE INDEX statistical_unit_facet_physical_region_path_btree
    ON public.statistical_unit_facet (physical_region_path);
CREATE INDEX statistical_unit_facet_physical_region_path_gist
    ON public.statistical_unit_facet USING gist (physical_region_path);
CREATE INDEX statistical_unit_facet_primary_activity_category_path_btree
    ON public.statistical_unit_facet (primary_activity_category_path);
CREATE INDEX statistical_unit_facet_primary_activity_category_path_gist
    ON public.statistical_unit_facet USING gist (primary_activity_category_path);
CREATE INDEX statistical_unit_facet_sector_path_btree
    ON public.statistical_unit_facet (sector_path);
CREATE INDEX statistical_unit_facet_sector_path_gist
    ON public.statistical_unit_facet USING gist (sector_path);
CREATE INDEX statistical_unit_facet_unit_type
    ON public.statistical_unit_facet (unit_type);
CREATE INDEX statistical_unit_facet_valid_from
    ON public.statistical_unit_facet (valid_from);
CREATE INDEX statistical_unit_facet_valid_until
    ON public.statistical_unit_facet (valid_until);

-- =====================================================================
-- 7. Restore original RLS (no partition_seq filter)
-- =====================================================================
DROP POLICY IF EXISTS statistical_unit_facet_authenticated_read ON public.statistical_unit_facet;
DROP POLICY IF EXISTS statistical_unit_facet_regular_user_read ON public.statistical_unit_facet;
CREATE POLICY statistical_unit_facet_authenticated_read ON public.statistical_unit_facet
    FOR SELECT TO authenticated USING (true);
CREATE POLICY statistical_unit_facet_regular_user_read ON public.statistical_unit_facet
    FOR SELECT TO regular_user USING (true);

-- =====================================================================
-- 8. Remove partition_seq column
-- =====================================================================
ALTER TABLE public.statistical_unit_facet DROP COLUMN partition_seq;

END;
