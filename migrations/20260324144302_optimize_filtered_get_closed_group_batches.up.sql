-- Migration 20260324144302: optimize_filtered_get_closed_group_batches
--
-- Fix: When called with filter parameters (partial refresh for 1-2 units),
-- the function joined ALL enterprises × legal_units × establishments (380k × 1.1M × 824k)
-- then filtered with OR. PostgreSQL couldn't push the OR into the join → 28s for 1 unit.
--
-- Fix: For filtered mode, collect affected enterprise IDs first via index lookups,
-- then join outward from those specific enterprises. 28s → <100ms.
BEGIN;

CREATE OR REPLACE FUNCTION public.get_closed_group_batches(p_target_batch_size integer DEFAULT 1000, p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange, p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange, p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange, p_offset integer DEFAULT 0, p_limit integer DEFAULT NULL::integer)
 RETURNS TABLE(batch_seq integer, group_ids integer[], enterprise_ids integer[], legal_unit_ids integer[], establishment_ids integer[], total_unit_count integer, has_more boolean)
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
    END IF;

    -- Emit final batch (same for both paths)
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
