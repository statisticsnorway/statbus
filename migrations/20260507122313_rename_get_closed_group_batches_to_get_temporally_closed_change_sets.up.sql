-- Migration 20260507122313: rename get_closed_group_batches to get_temporally_closed_change_sets
--
-- "closed group" overloaded with `power_group` (the corporate-control concept);
-- "batches" overloaded with import-job batches and worker task batches.
-- The new name spells out what the function actually does: produces sets of
-- changes to apply, where each set is the temporal closure of a connected
-- component (closure under "shares a legal_unit.id with another enterprise"
-- → bridge-detected groups).
--
-- Internal rename inside the function:
--   p_target_batch_size              → p_target_change_set_size
--   batch_seq (OUT col)              → change_set_seq
--   v_current_batch_seq              → v_current_change_set_seq
--   v_current_batch_size             → v_current_change_set_size
--   v_batches_returned               → v_change_sets_returned
--   _batch_accumulator (temp table)  → _change_set_accumulator
--
-- In `worker.derive_statistical_unit` (sole caller):
--   _batches (temp table)            → _change_sets
--   v_batch.batch_seq references     → v_batch.change_set_seq
--   call site                        → public.get_temporally_closed_change_sets
--
-- Deliberately preserved (downstream contract surface — worker payload):
--   v_batch local variable name (also used for power_group batches in the
--     same procedure body — power-group really IS a batch of pg_ids)
--   'batch_seq' jsonb payload key (consumed by worker.statistical_unit_refresh_batch)
--   'batch_count' summary key, v_batch_count counter
--
-- Migration shape: replace caller, replace function body under new name, then
-- DROP the old function name. All in one transaction.

BEGIN;

----------------------------------------------------------------------
-- 1. New function: public.get_temporally_closed_change_sets
----------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_temporally_closed_change_sets(p_target_change_set_size integer DEFAULT 1000, p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange, p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange, p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange, p_offset integer DEFAULT 0, p_limit integer DEFAULT NULL::integer)
 RETURNS TABLE(change_set_seq integer, group_ids integer[], enterprise_ids integer[], legal_unit_ids integer[], establishment_ids integer[], total_unit_count integer, has_more boolean)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_current_change_set_seq INT := 1;
    v_current_change_set_size INT := 0;
    v_group RECORD;
    v_filter_active BOOLEAN;
    v_change_sets_returned INT := 0;
    v_skipped INT := 0;
    v_has_more BOOLEAN := FALSE;
    v_has_bridges BOOLEAN;
BEGIN
    v_filter_active := (p_establishment_id_ranges IS NOT NULL
                       OR p_legal_unit_id_ranges IS NOT NULL
                       OR p_enterprise_id_ranges IS NOT NULL);

    -- Use temp table to accumulate IDs for change-set assembly (O(n) vs O(n²) array concat)
    IF to_regclass('pg_temp._change_set_accumulator') IS NOT NULL THEN DROP TABLE _change_set_accumulator; END IF;
    CREATE TEMP TABLE _change_set_accumulator (
        group_id INT,
        enterprise_id INT,
        legal_unit_id INT,
        establishment_id INT
    ) ON COMMIT DROP;

    IF v_filter_active THEN
        ---------------------------------------------------------------
        -- FILTERED PATH: Start from known IDs, expand outward.
        -- Uses index lookups instead of full table joins.
        ---------------------------------------------------------------

        -- Step 1: Collect affected enterprise IDs
        IF to_regclass('pg_temp._affected_enterprises') IS NOT NULL THEN DROP TABLE _affected_enterprises; END IF;
        CREATE TEMP TABLE _affected_enterprises (enterprise_id INT PRIMARY KEY) ON COMMIT DROP;

        -- From enterprise ranges directly
        IF p_enterprise_id_ranges IS NOT NULL THEN
            INSERT INTO _affected_enterprises (enterprise_id)
            SELECT generate_series(lower(r), upper(r)-1)
            FROM unnest(p_enterprise_id_ranges) AS t(r)
            ON CONFLICT DO NOTHING;
        END IF;

        -- From LU ranges → look up enterprise_id via index
        IF p_legal_unit_id_ranges IS NOT NULL THEN
            INSERT INTO _affected_enterprises (enterprise_id)
            SELECT DISTINCT lu.enterprise_id
            FROM public.legal_unit AS lu
            WHERE lu.id <@ p_legal_unit_id_ranges
              AND lu.enterprise_id IS NOT NULL
            ON CONFLICT DO NOTHING;
        END IF;

        -- From establishment ranges → resolve via LU or direct enterprise link
        IF p_establishment_id_ranges IS NOT NULL THEN
            INSERT INTO _affected_enterprises (enterprise_id)
            SELECT DISTINCT COALESCE(lu.enterprise_id, es.enterprise_id)
            FROM public.establishment AS es
            LEFT JOIN public.legal_unit AS lu ON lu.id = es.legal_unit_id
            WHERE es.id <@ p_establishment_id_ranges
              AND COALESCE(lu.enterprise_id, es.enterprise_id) IS NOT NULL
            ON CONFLICT DO NOTHING;
        END IF;

        -- Step 2: Scoped bridge detection (only check affected enterprises)
        SELECT EXISTS(
            SELECT 1
            FROM public.legal_unit AS lu
            WHERE lu.enterprise_id IN (SELECT ae.enterprise_id FROM _affected_enterprises AS ae)
            GROUP BY lu.id
            HAVING MIN(lu.enterprise_id) <> MAX(lu.enterprise_id)
            LIMIT 1
        ) INTO v_has_bridges;

        IF v_has_bridges THEN
            -- Expand _affected_enterprises to include connected enterprises via bridges
            INSERT INTO _affected_enterprises (enterprise_id)
            WITH RECURSIVE
            reachable(enterprise_id) AS (
                SELECT DISTINCT b.enterprise_id
                FROM public.legal_unit AS a
                JOIN public.legal_unit AS b ON b.id = a.id
                WHERE a.enterprise_id IN (SELECT ae.enterprise_id FROM _affected_enterprises AS ae)
                  AND b.enterprise_id IS NOT NULL
                  AND b.enterprise_id NOT IN (SELECT ae.enterprise_id FROM _affected_enterprises AS ae)
                UNION
                SELECT DISTINCT b2.enterprise_id
                FROM reachable AS r
                JOIN public.legal_unit AS a2 ON a2.enterprise_id = r.enterprise_id
                JOIN public.legal_unit AS b2 ON b2.id = a2.id
                WHERE b2.enterprise_id IS NOT NULL
                  AND b2.enterprise_id <> a2.enterprise_id
            )
            SELECT enterprise_id FROM reachable
            ON CONFLICT DO NOTHING;

            -- Compute bridge groups scoped to affected enterprises
            IF to_regclass('pg_temp._bridge_groups') IS NOT NULL THEN DROP TABLE _bridge_groups; END IF;
            CREATE TEMP TABLE _bridge_groups (
                enterprise_id INT PRIMARY KEY,
                group_id INT NOT NULL
            ) ON COMMIT DROP;

            INSERT INTO _bridge_groups (enterprise_id, group_id)
            WITH RECURSIVE
            bridge_edges AS (
                SELECT DISTINCT a.enterprise_id AS en_a, b.enterprise_id AS en_b
                FROM public.legal_unit AS a
                JOIN public.legal_unit AS b ON a.id = b.id
                WHERE a.enterprise_id IN (SELECT ae.enterprise_id FROM _affected_enterprises AS ae)
                  AND b.enterprise_id IS NOT NULL
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

            -- Scoped group query with bridge groups
            FOR v_group IN
                SELECT
                    COALESCE(bg.group_id, en.id) AS group_id,
                    array_agg(DISTINCT en.id ORDER BY en.id) AS enterprise_ids,
                    array_agg(DISTINCT lu.id ORDER BY lu.id)
                        FILTER (WHERE lu.id IS NOT NULL) AS legal_unit_ids,
                    array_agg(DISTINCT es.id ORDER BY es.id)
                        FILTER (WHERE es.id IS NOT NULL) AS establishment_ids,
                    (COUNT(DISTINCT en.id) + COUNT(DISTINCT lu.id) + COUNT(DISTINCT es.id))::INT AS total_unit_count
                FROM _affected_enterprises AS ae
                JOIN public.enterprise AS en ON en.id = ae.enterprise_id
                LEFT JOIN _bridge_groups AS bg ON bg.enterprise_id = en.id
                LEFT JOIN public.legal_unit AS lu ON lu.enterprise_id = en.id
                LEFT JOIN public.establishment AS es
                    ON es.legal_unit_id = lu.id OR es.enterprise_id = en.id
                GROUP BY COALESCE(bg.group_id, en.id)
                ORDER BY total_unit_count DESC, group_id
            LOOP
                IF v_current_change_set_size > 0
                   AND v_current_change_set_size + v_group.total_unit_count > p_target_change_set_size
                THEN
                    IF p_limit IS NOT NULL AND v_change_sets_returned >= p_limit THEN
                        v_has_more := TRUE;
                        EXIT;
                    END IF;
                    IF v_skipped < p_offset THEN
                        v_skipped := v_skipped + 1;
                        v_current_change_set_seq := v_current_change_set_seq + 1;
                        v_current_change_set_size := 0;
                        TRUNCATE _change_set_accumulator;
                    ELSE
                        SELECT v_current_change_set_seq,
                            array_agg(DISTINCT ba.group_id ORDER BY ba.group_id) FILTER (WHERE ba.group_id IS NOT NULL),
                            array_agg(DISTINCT ba.enterprise_id ORDER BY ba.enterprise_id) FILTER (WHERE ba.enterprise_id IS NOT NULL),
                            array_agg(DISTINCT ba.legal_unit_id ORDER BY ba.legal_unit_id) FILTER (WHERE ba.legal_unit_id IS NOT NULL),
                            array_agg(DISTINCT ba.establishment_id ORDER BY ba.establishment_id) FILTER (WHERE ba.establishment_id IS NOT NULL),
                            v_current_change_set_size, FALSE
                        INTO change_set_seq, group_ids, enterprise_ids, legal_unit_ids, establishment_ids, total_unit_count, has_more
                        FROM _change_set_accumulator ba;
                        RETURN NEXT;
                        v_change_sets_returned := v_change_sets_returned + 1;
                        v_current_change_set_seq := v_current_change_set_seq + 1;
                        v_current_change_set_size := 0;
                        TRUNCATE _change_set_accumulator;
                    END IF;
                END IF;
                INSERT INTO _change_set_accumulator (group_id) VALUES (v_group.group_id);
                INSERT INTO _change_set_accumulator (enterprise_id) SELECT UNNEST(v_group.enterprise_ids);
                INSERT INTO _change_set_accumulator (legal_unit_id) SELECT UNNEST(COALESCE(v_group.legal_unit_ids, ARRAY[]::INT[]));
                INSERT INTO _change_set_accumulator (establishment_id) SELECT UNNEST(COALESCE(v_group.establishment_ids, ARRAY[]::INT[]));
                v_current_change_set_size := v_current_change_set_size + v_group.total_unit_count;
            END LOOP;
        ELSE
            -- No bridges, filtered: scoped group query
            FOR v_group IN
                SELECT
                    en.id AS group_id,
                    ARRAY[en.id] AS enterprise_ids,
                    array_agg(DISTINCT lu.id ORDER BY lu.id)
                        FILTER (WHERE lu.id IS NOT NULL) AS legal_unit_ids,
                    array_agg(DISTINCT es.id ORDER BY es.id)
                        FILTER (WHERE es.id IS NOT NULL) AS establishment_ids,
                    (1 + COUNT(DISTINCT lu.id) + COUNT(DISTINCT es.id))::INT AS total_unit_count
                FROM _affected_enterprises AS ae
                JOIN public.enterprise AS en ON en.id = ae.enterprise_id
                LEFT JOIN public.legal_unit AS lu ON lu.enterprise_id = en.id
                LEFT JOIN public.establishment AS es
                    ON es.legal_unit_id = lu.id OR es.enterprise_id = en.id
                GROUP BY en.id
                ORDER BY total_unit_count DESC, en.id
            LOOP
                IF v_current_change_set_size > 0
                   AND v_current_change_set_size + v_group.total_unit_count > p_target_change_set_size
                THEN
                    IF p_limit IS NOT NULL AND v_change_sets_returned >= p_limit THEN
                        v_has_more := TRUE;
                        EXIT;
                    END IF;
                    IF v_skipped < p_offset THEN
                        v_skipped := v_skipped + 1;
                        v_current_change_set_seq := v_current_change_set_seq + 1;
                        v_current_change_set_size := 0;
                        TRUNCATE _change_set_accumulator;
                    ELSE
                        SELECT v_current_change_set_seq,
                            array_agg(DISTINCT ba.group_id ORDER BY ba.group_id) FILTER (WHERE ba.group_id IS NOT NULL),
                            array_agg(DISTINCT ba.enterprise_id ORDER BY ba.enterprise_id) FILTER (WHERE ba.enterprise_id IS NOT NULL),
                            array_agg(DISTINCT ba.legal_unit_id ORDER BY ba.legal_unit_id) FILTER (WHERE ba.legal_unit_id IS NOT NULL),
                            array_agg(DISTINCT ba.establishment_id ORDER BY ba.establishment_id) FILTER (WHERE ba.establishment_id IS NOT NULL),
                            v_current_change_set_size, FALSE
                        INTO change_set_seq, group_ids, enterprise_ids, legal_unit_ids, establishment_ids, total_unit_count, has_more
                        FROM _change_set_accumulator ba;
                        RETURN NEXT;
                        v_change_sets_returned := v_change_sets_returned + 1;
                        v_current_change_set_seq := v_current_change_set_seq + 1;
                        v_current_change_set_size := 0;
                        TRUNCATE _change_set_accumulator;
                    END IF;
                END IF;
                INSERT INTO _change_set_accumulator (group_id) VALUES (v_group.group_id);
                INSERT INTO _change_set_accumulator (enterprise_id) SELECT UNNEST(v_group.enterprise_ids);
                INSERT INTO _change_set_accumulator (legal_unit_id) SELECT UNNEST(COALESCE(v_group.legal_unit_ids, ARRAY[]::INT[]));
                INSERT INTO _change_set_accumulator (establishment_id) SELECT UNNEST(COALESCE(v_group.establishment_ids, ARRAY[]::INT[]));
                v_current_change_set_size := v_current_change_set_size + v_group.total_unit_count;
            END LOOP;
        END IF;
    ELSE
        ---------------------------------------------------------------
        -- FULL REFRESH PATH: Unchanged from previous version
        ---------------------------------------------------------------
        SELECT EXISTS(
            SELECT 1
            FROM public.legal_unit
            WHERE enterprise_id IS NOT NULL
            GROUP BY id
            HAVING MIN(enterprise_id) <> MAX(enterprise_id)
            LIMIT 1
        ) INTO v_has_bridges;

        IF v_has_bridges THEN
            IF to_regclass('pg_temp._bridge_groups') IS NOT NULL THEN DROP TABLE _bridge_groups; END IF;
            CREATE TEMP TABLE _bridge_groups (
                enterprise_id INT PRIMARY KEY,
                group_id INT NOT NULL
            ) ON COMMIT DROP;

            INSERT INTO _bridge_groups (enterprise_id, group_id)
            WITH RECURSIVE
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
                GROUP BY COALESCE(bg.group_id, en.id)
                ORDER BY total_unit_count DESC, group_id
            LOOP
                IF v_current_change_set_size > 0
                   AND v_current_change_set_size + v_group.total_unit_count > p_target_change_set_size
                THEN
                    IF p_limit IS NOT NULL AND v_change_sets_returned >= p_limit THEN
                        v_has_more := TRUE;
                        EXIT;
                    END IF;
                    IF v_skipped < p_offset THEN
                        v_skipped := v_skipped + 1;
                        v_current_change_set_seq := v_current_change_set_seq + 1;
                        v_current_change_set_size := 0;
                        TRUNCATE _change_set_accumulator;
                    ELSE
                        SELECT v_current_change_set_seq,
                            array_agg(DISTINCT ba.group_id ORDER BY ba.group_id) FILTER (WHERE ba.group_id IS NOT NULL),
                            array_agg(DISTINCT ba.enterprise_id ORDER BY ba.enterprise_id) FILTER (WHERE ba.enterprise_id IS NOT NULL),
                            array_agg(DISTINCT ba.legal_unit_id ORDER BY ba.legal_unit_id) FILTER (WHERE ba.legal_unit_id IS NOT NULL),
                            array_agg(DISTINCT ba.establishment_id ORDER BY ba.establishment_id) FILTER (WHERE ba.establishment_id IS NOT NULL),
                            v_current_change_set_size, FALSE
                        INTO change_set_seq, group_ids, enterprise_ids, legal_unit_ids, establishment_ids, total_unit_count, has_more
                        FROM _change_set_accumulator ba;
                        RETURN NEXT;
                        v_change_sets_returned := v_change_sets_returned + 1;
                        v_current_change_set_seq := v_current_change_set_seq + 1;
                        v_current_change_set_size := 0;
                        TRUNCATE _change_set_accumulator;
                    END IF;
                END IF;
                INSERT INTO _change_set_accumulator (group_id) VALUES (v_group.group_id);
                INSERT INTO _change_set_accumulator (enterprise_id) SELECT UNNEST(v_group.enterprise_ids);
                INSERT INTO _change_set_accumulator (legal_unit_id) SELECT UNNEST(COALESCE(v_group.legal_unit_ids, ARRAY[]::INT[]));
                INSERT INTO _change_set_accumulator (establishment_id) SELECT UNNEST(COALESCE(v_group.establishment_ids, ARRAY[]::INT[]));
                v_current_change_set_size := v_current_change_set_size + v_group.total_unit_count;
            END LOOP;
        ELSE
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
                GROUP BY en.id
                ORDER BY total_unit_count DESC, en.id
            LOOP
                IF v_current_change_set_size > 0
                   AND v_current_change_set_size + v_group.total_unit_count > p_target_change_set_size
                THEN
                    IF p_limit IS NOT NULL AND v_change_sets_returned >= p_limit THEN
                        v_has_more := TRUE;
                        EXIT;
                    END IF;
                    IF v_skipped < p_offset THEN
                        v_skipped := v_skipped + 1;
                        v_current_change_set_seq := v_current_change_set_seq + 1;
                        v_current_change_set_size := 0;
                        TRUNCATE _change_set_accumulator;
                    ELSE
                        SELECT v_current_change_set_seq,
                            array_agg(DISTINCT ba.group_id ORDER BY ba.group_id) FILTER (WHERE ba.group_id IS NOT NULL),
                            array_agg(DISTINCT ba.enterprise_id ORDER BY ba.enterprise_id) FILTER (WHERE ba.enterprise_id IS NOT NULL),
                            array_agg(DISTINCT ba.legal_unit_id ORDER BY ba.legal_unit_id) FILTER (WHERE ba.legal_unit_id IS NOT NULL),
                            array_agg(DISTINCT ba.establishment_id ORDER BY ba.establishment_id) FILTER (WHERE ba.establishment_id IS NOT NULL),
                            v_current_change_set_size, FALSE
                        INTO change_set_seq, group_ids, enterprise_ids, legal_unit_ids, establishment_ids, total_unit_count, has_more
                        FROM _change_set_accumulator ba;
                        RETURN NEXT;
                        v_change_sets_returned := v_change_sets_returned + 1;
                        v_current_change_set_seq := v_current_change_set_seq + 1;
                        v_current_change_set_size := 0;
                        TRUNCATE _change_set_accumulator;
                    END IF;
                END IF;
                INSERT INTO _change_set_accumulator (group_id) VALUES (v_group.group_id);
                INSERT INTO _change_set_accumulator (enterprise_id) SELECT UNNEST(v_group.enterprise_ids);
                INSERT INTO _change_set_accumulator (legal_unit_id) SELECT UNNEST(COALESCE(v_group.legal_unit_ids, ARRAY[]::INT[]));
                INSERT INTO _change_set_accumulator (establishment_id) SELECT UNNEST(COALESCE(v_group.establishment_ids, ARRAY[]::INT[]));
                v_current_change_set_size := v_current_change_set_size + v_group.total_unit_count;
            END LOOP;
        END IF;
    END IF;

    -- Emit final batch (same for both paths)
    IF v_current_change_set_size > 0 AND NOT v_has_more THEN
        IF p_limit IS NOT NULL AND v_change_sets_returned >= p_limit THEN
            v_has_more := TRUE;
        ELSIF v_skipped < p_offset THEN
            v_has_more := FALSE;
        ELSE
            SELECT v_current_change_set_seq,
                array_agg(DISTINCT ba.group_id ORDER BY ba.group_id) FILTER (WHERE ba.group_id IS NOT NULL),
                array_agg(DISTINCT ba.enterprise_id ORDER BY ba.enterprise_id) FILTER (WHERE ba.enterprise_id IS NOT NULL),
                array_agg(DISTINCT ba.legal_unit_id ORDER BY ba.legal_unit_id) FILTER (WHERE ba.legal_unit_id IS NOT NULL),
                array_agg(DISTINCT ba.establishment_id ORDER BY ba.establishment_id) FILTER (WHERE ba.establishment_id IS NOT NULL),
                v_current_change_set_size, FALSE
            INTO change_set_seq, group_ids, enterprise_ids, legal_unit_ids, establishment_ids, total_unit_count, has_more
            FROM _change_set_accumulator ba;
            RETURN NEXT;
        END IF;
    END IF;
END;
$function$
;


----------------------------------------------------------------------
-- 2. Update sole caller: worker.derive_statistical_unit
----------------------------------------------------------------------

CREATE OR REPLACE FUNCTION worker.derive_statistical_unit(p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange, p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange, p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange, p_power_group_id_ranges int4multirange DEFAULT NULL::int4multirange, p_valid_from date DEFAULT NULL::date, p_valid_until date DEFAULT NULL::date, p_task_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
    v_pg_batch_size INT;
BEGIN
    v_is_full_refresh := (p_establishment_id_ranges IS NULL
                         AND p_legal_unit_id_ranges IS NULL
                         AND p_enterprise_id_ranges IS NULL
                         AND p_power_group_id_ranges IS NULL);

    IF v_is_full_refresh THEN
        FOR v_batch IN SELECT * FROM public.get_temporally_closed_change_sets(p_target_change_set_size => 1000)
        LOOP
            v_enterprise_count := v_enterprise_count + COALESCE(array_length(v_batch.enterprise_ids, 1), 0);
            v_legal_unit_count := v_legal_unit_count + COALESCE(array_length(v_batch.legal_unit_ids, 1), 0);
            v_establishment_count := v_establishment_count + COALESCE(array_length(v_batch.establishment_ids, 1), 0);

            PERFORM worker.spawn(
                p_command => 'statistical_unit_refresh_batch',
                p_payload => jsonb_build_object(
                    'command', 'statistical_unit_refresh_batch',
                    'batch_seq', v_batch.change_set_seq,
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
            IF to_regclass('pg_temp._change_sets') IS NOT NULL THEN DROP TABLE _change_sets; END IF;
            CREATE TEMP TABLE _change_sets ON COMMIT DROP AS
            SELECT * FROM public.get_temporally_closed_change_sets(
                p_target_change_set_size => 1000,
                p_establishment_id_ranges => NULLIF(p_establishment_id_ranges, '{}'::int4multirange),
                p_legal_unit_id_ranges => NULLIF(p_legal_unit_id_ranges, '{}'::int4multirange),
                p_enterprise_id_ranges => NULLIF(p_enterprise_id_ranges, '{}'::int4multirange)
            );
            INSERT INTO public.statistical_unit_facet_dirty_hash_slots (dirty_hash_slot)
            SELECT DISTINCT public.hash_slot(t.unit_type, t.unit_id)
            FROM (
                SELECT 'enterprise'::text AS unit_type, unnest(b.enterprise_ids) AS unit_id FROM _change_sets AS b
                UNION ALL SELECT 'legal_unit', unnest(b.legal_unit_ids) FROM _change_sets AS b
                UNION ALL SELECT 'establishment', unnest(b.establishment_ids) FROM _change_sets AS b
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
                    FROM (SELECT unnest(establishment_ids) AS id FROM _change_sets) AS t);
                v_all_batch_lu_ranges := (SELECT range_agg(int4range(id, id, '[]'))
                    FROM (SELECT unnest(legal_unit_ids) AS id FROM _change_sets) AS t);
                v_all_batch_en_ranges := (SELECT range_agg(int4range(id, id, '[]'))
                    FROM (SELECT unnest(enterprise_ids) AS id FROM _change_sets) AS t);

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

            FOR v_batch IN SELECT * FROM _change_sets LOOP
                PERFORM worker.spawn(
                    p_command => 'statistical_unit_refresh_batch',
                    p_payload => jsonb_build_object(
                        'command', 'statistical_unit_refresh_batch',
                        'batch_seq', v_batch.change_set_seq,
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
            INSERT INTO public.statistical_unit_facet_dirty_hash_slots (dirty_hash_slot)
            SELECT DISTINCT public.hash_slot('power_group', pg_id)
            FROM unnest(v_power_group_ids) AS pg_id
            ON CONFLICT DO NOTHING;

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

    -- BLOCK B: *_used_derive() calls removed. See worker.derive_used_tables
    -- (spawned as a serial child of derive_units_phase AFTER flush_staging).

    RETURN jsonb_build_object(
        'effective_establishment_count', v_establishment_count,
        'effective_legal_unit_count', v_legal_unit_count,
        'effective_enterprise_count', v_enterprise_count,
        'effective_power_group_count', v_power_group_count,
        'batch_count', v_batch_count
    );
END;
$function$
;


----------------------------------------------------------------------
-- 3. Drop the old function name (no other callers — verified via grep
--    across migrations/, doc/db/, app/, cli/, test/sql/)
----------------------------------------------------------------------

DROP FUNCTION public.get_closed_group_batches(integer, int4multirange, int4multirange, int4multirange, integer, integer);

END;
