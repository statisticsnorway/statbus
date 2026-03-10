-- Migration 20260309201135: remove_dead_derive_statistical_unit_impl_and_continue
--
-- Removes dead code from the worker schema:
--
-- 1. worker.derive_statistical_unit_impl() — the old wave-based approach that
--    processed batches in waves with ANALYZE sync points between them.
--    Replaced by the current batch-spawning model in derive_statistical_unit()
--    which spawns all batches at once as children of the parent task.
--
-- 2. worker.derive_statistical_unit_continue(jsonb) — the continuation procedure
--    that was called between waves to resume processing with the next batch offset.
--    Only called by _impl, and _impl only called by _continue — a dead cycle.
--
-- 3. public.get_enterprise_closed_groups() — computes transitive closure over ALL
--    enterprises via recursive CTE. Was only called by the old
--    get_closed_group_batches (replaced in migration 20260309195139).
--    The new get_closed_group_batches uses bridge detection + parallel hash
--    joins instead, and handles the bridge case inline with a fast temp table
--    approach rather than delegating to this slow function.
--
-- Evidence of dead code:
--   - Zero rows in worker.tasks with command = 'derive_statistical_unit_impl'
--     or 'derive_statistical_unit_continue'
--   - The Crystal worker code (cli/src/worker.cr) has no reference to either
--   - _impl and _continue only reference each other (dead cycle)
--   - get_enterprise_closed_groups has no callers after migration 20260309195139
--
-- Also removes the command_registry entry for _continue, and the
-- batches_per_wave column which was only used by _impl's wave-based processing.
--
-- Finally, replaces the bridge fallback in get_closed_group_batches to use a
-- fast temp table approach (~3.8s) instead of the now-removed
-- get_enterprise_closed_groups() (which did recursive transitive closure over
-- all 1.1M+ enterprises).
BEGIN;

-- Remove command_registry entry (must come before dropping the procedure)
DELETE FROM worker.command_registry WHERE command = 'derive_statistical_unit_continue';

-- Remove the batches_per_wave column (only used by _impl)
ALTER TABLE worker.command_registry DROP COLUMN IF EXISTS batches_per_wave;

-- Drop the dead functions/procedures
DROP FUNCTION IF EXISTS worker.derive_statistical_unit_impl(
    int4multirange, int4multirange, int4multirange, date, date, bigint, integer
);
DROP PROCEDURE IF EXISTS worker.derive_statistical_unit_continue(jsonb);
DROP FUNCTION IF EXISTS public.get_enterprise_closed_groups();

-- Replace get_closed_group_batches to remove dependency on get_enterprise_closed_groups.
-- The bridge fallback now uses a fast temp table approach: compute connected
-- components only over the small set of bridged enterprises, then merge
-- group assignments into the main hash join query via COALESCE.
DROP FUNCTION IF EXISTS public.get_closed_group_batches(integer, int4multirange, int4multirange, int4multirange, integer, integer);

CREATE FUNCTION public.get_closed_group_batches(
    p_target_batch_size integer DEFAULT 1000,
    p_establishment_id_ranges int4multirange DEFAULT NULL,
    p_legal_unit_id_ranges int4multirange DEFAULT NULL,
    p_enterprise_id_ranges int4multirange DEFAULT NULL,
    p_offset integer DEFAULT 0,
    p_limit integer DEFAULT NULL
)
RETURNS TABLE(
    batch_seq integer,
    group_ids integer[],
    enterprise_ids integer[],
    legal_unit_ids integer[],
    establishment_ids integer[],
    total_unit_count integer,
    has_more boolean
)
LANGUAGE plpgsql
AS $get_closed_group_batches$
DECLARE
    v_current_batch_seq INT := 1;
    v_current_batch_size INT := 0;
    v_group RECORD;
    v_filter_active BOOLEAN;
    v_batches_returned INT := 0;
    v_skipped INT := 0;
    v_has_more BOOLEAN := FALSE;
    v_has_bridges BOOLEAN;
BEGIN
    v_filter_active := (p_establishment_id_ranges IS NOT NULL
                       OR p_legal_unit_id_ranges IS NOT NULL
                       OR p_enterprise_id_ranges IS NOT NULL);

    -- Use temp table to accumulate IDs for batching (O(n) vs O(n²) array concat)
    IF to_regclass('pg_temp._batch_accumulator') IS NOT NULL THEN DROP TABLE _batch_accumulator; END IF;
    CREATE TEMP TABLE _batch_accumulator (
        group_id INT,
        enterprise_id INT,
        legal_unit_id INT,
        establishment_id INT
    ) ON COMMIT DROP;

    -- Bridge detection: check if any LU has different enterprise_ids across
    -- time periods. This is the ONLY source of enterprise connectivity.
    -- A single pass over legal_unit (~0.5s for 1.1M rows).
    SELECT EXISTS(
        SELECT 1
        FROM public.legal_unit
        WHERE enterprise_id IS NOT NULL
        GROUP BY id
        HAVING MIN(enterprise_id) <> MAX(enterprise_id)
        LIMIT 1
    ) INTO v_has_bridges;

    IF v_has_bridges THEN
        -- Rare case: bridges exist. Compute connected components only over the
        -- small set of bridged enterprises (not the full 1M+ set), then merge
        -- group assignments into the main hash join query.
        IF to_regclass('pg_temp._bridge_groups') IS NOT NULL THEN DROP TABLE _bridge_groups; END IF;
        CREATE TEMP TABLE _bridge_groups (
            enterprise_id INT PRIMARY KEY,
            group_id INT NOT NULL
        ) ON COMMIT DROP;

        INSERT INTO _bridge_groups (enterprise_id, group_id)
        WITH RECURSIVE
        -- Self-join to enumerate ALL pairs of enterprise_ids per LU.
        -- MIN/MAX would lose intermediate values when a LU connects 3+ enterprises.
        bridge_edges AS (
            SELECT DISTINCT a.enterprise_id AS en_a, b.enterprise_id AS en_b
            FROM public.legal_unit AS a
            JOIN public.legal_unit AS b ON a.id = b.id
            WHERE a.enterprise_id IS NOT NULL AND b.enterprise_id IS NOT NULL
              AND a.enterprise_id < b.enterprise_id
        ),
        all_edges AS (
            SELECT en_a, en_b FROM bridge_edges
            UNION
            SELECT en_b, en_a FROM bridge_edges
        ),
        closure(from_en, to_en) AS (
            SELECT en_a, en_b FROM all_edges
            UNION
            SELECT c.from_en, e.en_b
            FROM closure AS c
            JOIN all_edges AS e ON c.to_en = e.en_a
        )
        SELECT from_en AS enterprise_id, MIN(to_en) AS group_id
        FROM closure
        GROUP BY from_en;

        -- Main query with bridge group remapping via COALESCE
        FOR v_group IN
            SELECT
                COALESCE(bg.group_id, en.id) AS group_id,
                array_agg(DISTINCT en.id ORDER BY en.id) AS enterprise_ids,
                array_agg(DISTINCT lu.id ORDER BY lu.id)
                    FILTER (WHERE lu.id IS NOT NULL) AS legal_unit_ids,
                array_agg(DISTINCT es.id ORDER BY es.id)
                    FILTER (WHERE es.id IS NOT NULL) AS establishment_ids,
                (COUNT(DISTINCT en.id) + COUNT(DISTINCT lu.id) + COUNT(DISTINCT es.id))::INT AS total_unit_count
            FROM public.enterprise AS en
            LEFT JOIN _bridge_groups AS bg ON bg.enterprise_id = en.id
            LEFT JOIN public.legal_unit AS lu ON lu.enterprise_id = en.id
            LEFT JOIN public.establishment AS es
                ON es.legal_unit_id = lu.id OR es.enterprise_id = en.id
            WHERE NOT v_filter_active
               OR en.id <@ COALESCE(p_enterprise_id_ranges, '{}'::int4multirange)
               OR lu.id <@ COALESCE(p_legal_unit_id_ranges, '{}'::int4multirange)
               OR es.id <@ COALESCE(p_establishment_id_ranges, '{}'::int4multirange)
            GROUP BY COALESCE(bg.group_id, en.id)
            ORDER BY total_unit_count DESC, group_id
        LOOP
            IF v_current_batch_size > 0
               AND v_current_batch_size + v_group.total_unit_count > p_target_batch_size
            THEN
                IF p_limit IS NOT NULL AND v_batches_returned >= p_limit THEN
                    v_has_more := TRUE;
                    EXIT;
                END IF;
                IF v_skipped < p_offset THEN
                    v_skipped := v_skipped + 1;
                    v_current_batch_seq := v_current_batch_seq + 1;
                    v_current_batch_size := 0;
                    TRUNCATE _batch_accumulator;
                ELSE
                    SELECT v_current_batch_seq,
                        array_agg(DISTINCT ba.group_id ORDER BY ba.group_id) FILTER (WHERE ba.group_id IS NOT NULL),
                        array_agg(DISTINCT ba.enterprise_id ORDER BY ba.enterprise_id) FILTER (WHERE ba.enterprise_id IS NOT NULL),
                        array_agg(DISTINCT ba.legal_unit_id ORDER BY ba.legal_unit_id) FILTER (WHERE ba.legal_unit_id IS NOT NULL),
                        array_agg(DISTINCT ba.establishment_id ORDER BY ba.establishment_id) FILTER (WHERE ba.establishment_id IS NOT NULL),
                        v_current_batch_size, FALSE
                    INTO batch_seq, group_ids, enterprise_ids, legal_unit_ids, establishment_ids, total_unit_count, has_more
                    FROM _batch_accumulator ba;
                    RETURN NEXT;
                    v_batches_returned := v_batches_returned + 1;
                    v_current_batch_seq := v_current_batch_seq + 1;
                    v_current_batch_size := 0;
                    TRUNCATE _batch_accumulator;
                END IF;
            END IF;
            INSERT INTO _batch_accumulator (group_id) VALUES (v_group.group_id);
            INSERT INTO _batch_accumulator (enterprise_id) SELECT UNNEST(v_group.enterprise_ids);
            INSERT INTO _batch_accumulator (legal_unit_id) SELECT UNNEST(COALESCE(v_group.legal_unit_ids, ARRAY[]::INT[]));
            INSERT INTO _batch_accumulator (establishment_id) SELECT UNNEST(COALESCE(v_group.establishment_ids, ARRAY[]::INT[]));
            v_current_batch_size := v_current_batch_size + v_group.total_unit_count;
        END LOOP;
    ELSE
        -- Common case: no bridges. Every enterprise is its own group.
        -- Use a single parallel hash join query — ~2.3s for 1.1M enterprises.
        -- group_id = enterprise_id since there are no connected components.
        FOR v_group IN
            SELECT
                en.id AS group_id,
                ARRAY[en.id] AS enterprise_ids,
                array_agg(DISTINCT lu.id ORDER BY lu.id)
                    FILTER (WHERE lu.id IS NOT NULL) AS legal_unit_ids,
                array_agg(DISTINCT es.id ORDER BY es.id)
                    FILTER (WHERE es.id IS NOT NULL) AS establishment_ids,
                (1 + COUNT(DISTINCT lu.id) + COUNT(DISTINCT es.id))::INT AS total_unit_count
            FROM public.enterprise AS en
            LEFT JOIN public.legal_unit AS lu ON lu.enterprise_id = en.id
            LEFT JOIN public.establishment AS es
                ON es.legal_unit_id = lu.id OR es.enterprise_id = en.id
            WHERE NOT v_filter_active
               OR en.id <@ COALESCE(p_enterprise_id_ranges, '{}'::int4multirange)
               OR lu.id <@ COALESCE(p_legal_unit_id_ranges, '{}'::int4multirange)
               OR es.id <@ COALESCE(p_establishment_id_ranges, '{}'::int4multirange)
            GROUP BY en.id
            ORDER BY total_unit_count DESC, en.id
        LOOP
            IF v_current_batch_size > 0
               AND v_current_batch_size + v_group.total_unit_count > p_target_batch_size
            THEN
                IF p_limit IS NOT NULL AND v_batches_returned >= p_limit THEN
                    v_has_more := TRUE;
                    EXIT;
                END IF;
                IF v_skipped < p_offset THEN
                    v_skipped := v_skipped + 1;
                    v_current_batch_seq := v_current_batch_seq + 1;
                    v_current_batch_size := 0;
                    TRUNCATE _batch_accumulator;
                ELSE
                    SELECT v_current_batch_seq,
                        array_agg(DISTINCT ba.group_id ORDER BY ba.group_id) FILTER (WHERE ba.group_id IS NOT NULL),
                        array_agg(DISTINCT ba.enterprise_id ORDER BY ba.enterprise_id) FILTER (WHERE ba.enterprise_id IS NOT NULL),
                        array_agg(DISTINCT ba.legal_unit_id ORDER BY ba.legal_unit_id) FILTER (WHERE ba.legal_unit_id IS NOT NULL),
                        array_agg(DISTINCT ba.establishment_id ORDER BY ba.establishment_id) FILTER (WHERE ba.establishment_id IS NOT NULL),
                        v_current_batch_size, FALSE
                    INTO batch_seq, group_ids, enterprise_ids, legal_unit_ids, establishment_ids, total_unit_count, has_more
                    FROM _batch_accumulator ba;
                    RETURN NEXT;
                    v_batches_returned := v_batches_returned + 1;
                    v_current_batch_seq := v_current_batch_seq + 1;
                    v_current_batch_size := 0;
                    TRUNCATE _batch_accumulator;
                END IF;
            END IF;
            INSERT INTO _batch_accumulator (group_id) VALUES (v_group.group_id);
            INSERT INTO _batch_accumulator (enterprise_id) SELECT UNNEST(v_group.enterprise_ids);
            INSERT INTO _batch_accumulator (legal_unit_id) SELECT UNNEST(COALESCE(v_group.legal_unit_ids, ARRAY[]::INT[]));
            INSERT INTO _batch_accumulator (establishment_id) SELECT UNNEST(COALESCE(v_group.establishment_ids, ARRAY[]::INT[]));
            v_current_batch_size := v_current_batch_size + v_group.total_unit_count;
        END LOOP;
    END IF;

    -- Emit final batch
    IF v_current_batch_size > 0 AND NOT v_has_more THEN
        IF p_limit IS NOT NULL AND v_batches_returned >= p_limit THEN
            v_has_more := TRUE;
        ELSIF v_skipped < p_offset THEN
            v_has_more := FALSE;
        ELSE
            SELECT v_current_batch_seq,
                array_agg(DISTINCT ba.group_id ORDER BY ba.group_id) FILTER (WHERE ba.group_id IS NOT NULL),
                array_agg(DISTINCT ba.enterprise_id ORDER BY ba.enterprise_id) FILTER (WHERE ba.enterprise_id IS NOT NULL),
                array_agg(DISTINCT ba.legal_unit_id ORDER BY ba.legal_unit_id) FILTER (WHERE ba.legal_unit_id IS NOT NULL),
                array_agg(DISTINCT ba.establishment_id ORDER BY ba.establishment_id) FILTER (WHERE ba.establishment_id IS NOT NULL),
                v_current_batch_size, FALSE
            INTO batch_seq, group_ids, enterprise_ids, legal_unit_ids, establishment_ids, total_unit_count, has_more
            FROM _batch_accumulator ba;
            RETURN NEXT;
        END IF;
    END IF;
END;
$get_closed_group_batches$;

END;
