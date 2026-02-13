```sql
CREATE OR REPLACE FUNCTION public.get_closed_group_batches(p_target_batch_size integer DEFAULT 1000, p_establishment_ids integer[] DEFAULT NULL::integer[], p_legal_unit_ids integer[] DEFAULT NULL::integer[], p_enterprise_ids integer[] DEFAULT NULL::integer[], p_offset integer DEFAULT 0, p_limit integer DEFAULT NULL::integer)
 RETURNS TABLE(batch_seq integer, group_ids integer[], enterprise_ids integer[], legal_unit_ids integer[], establishment_ids integer[], total_unit_count integer, has_more boolean)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_current_batch_seq INT := 1;
    v_current_batch_size INT := 0;
    v_group RECORD;
    v_filter_active BOOLEAN;
    v_batches_returned INT := 0;
    v_skipped INT := 0;
    v_has_more BOOLEAN := FALSE;
BEGIN
    v_filter_active := (p_establishment_ids IS NOT NULL
                       OR p_legal_unit_ids IS NOT NULL
                       OR p_enterprise_ids IS NOT NULL);

    -- Use temp table to accumulate IDs (O(n) instead of O(n²) array concatenation)
    IF to_regclass('pg_temp._batch_accumulator') IS NOT NULL THEN DROP TABLE _batch_accumulator; END IF;
    CREATE TEMP TABLE _batch_accumulator (
        group_id INT,
        enterprise_id INT,
        legal_unit_id INT,
        establishment_id INT
    ) ON COMMIT DROP;

    FOR v_group IN
        WITH RECURSIVE
        -- For partial refresh: targeted BFS from affected enterprise IDs only.
        -- For full refresh: compute all groups via get_enterprise_closed_groups().
        affected_enterprise_ids AS (
            SELECT UNNEST(p_enterprise_ids) AS enterprise_id
            WHERE p_enterprise_ids IS NOT NULL
            UNION
            SELECT DISTINCT lu.enterprise_id
            FROM public.legal_unit AS lu
            WHERE lu.id = ANY(p_legal_unit_ids) AND p_legal_unit_ids IS NOT NULL
            UNION
            SELECT DISTINCT COALESCE(lu.enterprise_id, es.enterprise_id)
            FROM public.establishment AS es
            LEFT JOIN public.legal_unit AS lu ON es.legal_unit_id = lu.id
            WHERE es.id = ANY(p_establishment_ids) AND p_establishment_ids IS NOT NULL
        ),
        -- Targeted BFS: walk the enterprise connectivity graph starting from
        -- affected_enterprise_ids only. This avoids computing the full transitive
        -- closure over all 1.1M+ enterprises when only a few are affected.
        targeted_reachable(enterprise_id) AS (
            SELECT ae.enterprise_id FROM affected_enterprise_ids AS ae
            UNION
            SELECT DISTINCT b.enterprise_id
            FROM targeted_reachable AS r
            JOIN public.legal_unit AS a ON a.enterprise_id = r.enterprise_id
            JOIN public.legal_unit AS b ON b.id = a.id
            WHERE b.enterprise_id IS NOT NULL
        ),
        -- Build edges scoped to the reachable set, then compute transitive closure
        -- within that set to correctly identify per-component group_ids.
        targeted_edges AS (
            SELECT DISTINCT a.enterprise_id AS from_en, b.enterprise_id AS to_en
            FROM public.legal_unit AS a
            JOIN public.legal_unit AS b ON a.id = b.id
            WHERE a.enterprise_id IN (SELECT enterprise_id FROM targeted_reachable)
              AND b.enterprise_id IN (SELECT enterprise_id FROM targeted_reachable)
              AND a.enterprise_id IS NOT NULL AND b.enterprise_id IS NOT NULL
            UNION
            SELECT r.enterprise_id, r.enterprise_id FROM targeted_reachable AS r
        ),
        targeted_closure(from_en, to_en) AS (
            SELECT from_en, to_en FROM targeted_edges
            UNION
            SELECT tc.from_en, e.to_en
            FROM targeted_closure AS tc
            JOIN targeted_edges AS e ON tc.to_en = e.from_en
        ),
        -- Assign group_id = minimum reachable enterprise_id per connected component
        targeted_enterprise_to_group AS (
            SELECT from_en AS enterprise_id, MIN(to_en) AS group_id
            FROM targeted_closure
            GROUP BY from_en
        ),
        -- Collect enterprises per group
        targeted_group_enterprises AS (
            SELECT
                teg.group_id,
                array_agg(DISTINCT teg.enterprise_id ORDER BY teg.enterprise_id) AS enterprise_ids,
                COUNT(DISTINCT teg.enterprise_id)::INT AS enterprise_count
            FROM targeted_enterprise_to_group AS teg
            GROUP BY teg.group_id
        ),
        -- Collect legal units per group
        targeted_group_legal_units AS (
            SELECT
                teg.group_id,
                array_agg(DISTINCT lu.id ORDER BY lu.id) AS legal_unit_ids,
                COUNT(DISTINCT lu.id)::INT AS legal_unit_count
            FROM targeted_enterprise_to_group AS teg
            JOIN public.legal_unit AS lu ON lu.enterprise_id = teg.enterprise_id
            GROUP BY teg.group_id
        ),
        -- Collect establishments per group
        targeted_group_establishments AS (
            SELECT
                teg.group_id,
                array_agg(DISTINCT es.id ORDER BY es.id) AS establishment_ids,
                COUNT(DISTINCT es.id)::INT AS establishment_count
            FROM targeted_enterprise_to_group AS teg
            LEFT JOIN public.legal_unit AS lu ON lu.enterprise_id = teg.enterprise_id
            LEFT JOIN public.establishment AS es ON
                es.enterprise_id = teg.enterprise_id OR es.legal_unit_id = lu.id
            WHERE es.id IS NOT NULL
            GROUP BY teg.group_id
        ),
        -- Assemble targeted groups (same shape as get_enterprise_closed_groups output)
        targeted_groups AS (
            SELECT
                tge.group_id,
                tge.enterprise_ids,
                COALESCE(tglu.legal_unit_ids, ARRAY[]::INT[]) AS legal_unit_ids,
                COALESCE(tges.establishment_ids, ARRAY[]::INT[]) AS establishment_ids,
                (tge.enterprise_count + COALESCE(tglu.legal_unit_count, 0) + COALESCE(tges.establishment_count, 0))::INT AS total_unit_count
            FROM targeted_group_enterprises AS tge
            LEFT JOIN targeted_group_legal_units AS tglu ON tglu.group_id = tge.group_id
            LEFT JOIN targeted_group_establishments AS tges ON tges.group_id = tge.group_id
        ),
        -- Full refresh path: uses existing get_enterprise_closed_groups()
        all_groups AS (
            SELECT
                ecg.group_id,
                ecg.enterprise_ids,
                ecg.legal_unit_ids,
                ecg.establishment_ids,
                ecg.total_unit_count
            FROM public.get_enterprise_closed_groups() AS ecg
            WHERE NOT v_filter_active
        ),
        -- Combine: for partial refresh use targeted_groups, for full refresh use all_groups
        combined_groups AS (
            SELECT * FROM targeted_groups WHERE v_filter_active
            UNION ALL
            SELECT * FROM all_groups
        )
        SELECT
            cg.group_id,
            cg.enterprise_ids,
            cg.legal_unit_ids,
            cg.establishment_ids,
            cg.total_unit_count
        FROM combined_groups AS cg
        ORDER BY cg.total_unit_count DESC, cg.group_id
    LOOP
        IF v_current_batch_size > 0
           AND v_current_batch_size + v_group.total_unit_count > p_target_batch_size
        THEN
            -- Check if we've hit the limit
            IF p_limit IS NOT NULL AND v_batches_returned >= p_limit THEN
                v_has_more := TRUE;
                EXIT;  -- Stop processing, we have more batches available
            END IF;

            -- Check if we should skip this batch (offset)
            IF v_skipped < p_offset THEN
                v_skipped := v_skipped + 1;
                -- Reset for next batch without returning
                v_current_batch_seq := v_current_batch_seq + 1;
                v_current_batch_size := 0;
                TRUNCATE _batch_accumulator;
            ELSE
                -- Output current batch
                SELECT
                    v_current_batch_seq,
                    array_agg(DISTINCT ba.group_id ORDER BY ba.group_id) FILTER (WHERE ba.group_id IS NOT NULL),
                    array_agg(DISTINCT ba.enterprise_id ORDER BY ba.enterprise_id) FILTER (WHERE ba.enterprise_id IS NOT NULL),
                    array_agg(DISTINCT ba.legal_unit_id ORDER BY ba.legal_unit_id) FILTER (WHERE ba.legal_unit_id IS NOT NULL),
                    array_agg(DISTINCT ba.establishment_id ORDER BY ba.establishment_id) FILTER (WHERE ba.establishment_id IS NOT NULL),
                    v_current_batch_size,
                    FALSE  -- has_more will be updated later if needed
                INTO batch_seq, group_ids, enterprise_ids, legal_unit_ids, establishment_ids, total_unit_count, has_more
                FROM _batch_accumulator ba;
                RETURN NEXT;
                v_batches_returned := v_batches_returned + 1;

                -- Reset for next batch
                v_current_batch_seq := v_current_batch_seq + 1;
                v_current_batch_size := 0;
                TRUNCATE _batch_accumulator;
            END IF;
        END IF;

        -- Insert unnested arrays into temp table
        INSERT INTO _batch_accumulator (group_id) VALUES (v_group.group_id);
        INSERT INTO _batch_accumulator (enterprise_id) SELECT UNNEST(v_group.enterprise_ids);
        INSERT INTO _batch_accumulator (legal_unit_id) SELECT UNNEST(v_group.legal_unit_ids);
        INSERT INTO _batch_accumulator (establishment_id) SELECT UNNEST(v_group.establishment_ids);

        v_current_batch_size := v_current_batch_size + v_group.total_unit_count;
    END LOOP;

    -- Handle final batch if not already exited due to limit
    IF v_current_batch_size > 0 AND NOT v_has_more THEN
        -- Check if we've hit the limit
        IF p_limit IS NOT NULL AND v_batches_returned >= p_limit THEN
            v_has_more := TRUE;
        ELSIF v_skipped < p_offset THEN
            -- This final batch should be skipped, but check if there's nothing after
            v_has_more := FALSE;
        ELSE
            -- Output final batch
            SELECT
                v_current_batch_seq,
                array_agg(DISTINCT ba.group_id ORDER BY ba.group_id) FILTER (WHERE ba.group_id IS NOT NULL),
                array_agg(DISTINCT ba.enterprise_id ORDER BY ba.enterprise_id) FILTER (WHERE ba.enterprise_id IS NOT NULL),
                array_agg(DISTINCT ba.legal_unit_id ORDER BY ba.legal_unit_id) FILTER (WHERE ba.legal_unit_id IS NOT NULL),
                array_agg(DISTINCT ba.establishment_id ORDER BY ba.establishment_id) FILTER (WHERE ba.establishment_id IS NOT NULL),
                v_current_batch_size,
                FALSE
            INTO batch_seq, group_ids, enterprise_ids, legal_unit_ids, establishment_ids, total_unit_count, has_more
            FROM _batch_accumulator ba;
            RETURN NEXT;
        END IF;
    END IF;
END;
$function$
```
