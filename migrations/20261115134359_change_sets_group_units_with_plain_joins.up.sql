-- Migration 20261115134359: change sets group units with plain joins (STATBUS-626).
--
-- public.get_temporally_closed_change_sets gathered each enterprise's establishments with one
-- join, es.legal_unit_id = lu.id OR es.enterprise_id = en.id. A join condition with OR over two
-- tables can be neither a hash nor a merge join, so PostgreSQL ran a nested loop that probed both
-- establishment indexes once for every legal unit row (a BitmapOr per row). The membership of an
-- enterprise group is a union of plain equality joins, one per link: the enterprise itself, its
-- legal units, the establishments of those legal units, and the establishments attached to the
-- enterprise directly. Each is an ordinary hash or merge join over the whole table. On the Norway
-- register the function's full path took 16.9-17.2 s and 8.6-9.3 s after; a partial change of
-- 800,000 unit ids took 12.7-13.1 s and 8.7-8.9 s. The change sets are identical (387 full,
-- 1,845 partial; test/sql/361 checks the groups on all four paths).
BEGIN;

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
    -- The change set being assembled. Each group appends its ids, so assembly costs
    -- one array append per group rather than one temp-table INSERT per id kind.
    v_acc_group_ids INT[] := '{}';
    v_acc_enterprise_ids INT[] := '{}';
    v_acc_legal_unit_ids INT[] := '{}';
    v_acc_establishment_ids INT[] := '{}';
BEGIN
    v_filter_active := (p_establishment_id_ranges IS NOT NULL
                       OR p_legal_unit_id_ranges IS NOT NULL
                       OR p_enterprise_id_ranges IS NOT NULL);

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
                    COALESCE(bg.group_id, member.enterprise_id) AS group_id,
                    array_agg(DISTINCT member.unit_id ORDER BY member.unit_id)
                        FILTER (WHERE member.kind = 'enterprise') AS enterprise_ids,
                    array_agg(DISTINCT member.unit_id ORDER BY member.unit_id)
                        FILTER (WHERE member.kind = 'legal_unit') AS legal_unit_ids,
                    array_agg(DISTINCT member.unit_id ORDER BY member.unit_id)
                        FILTER (WHERE member.kind = 'establishment') AS establishment_ids,
                    COUNT(DISTINCT (member.kind, member.unit_id))::INT AS total_unit_count
                FROM (
                    SELECT en.id AS enterprise_id, 'enterprise'::TEXT AS kind, en.id AS unit_id
                    FROM _affected_enterprises AS ae
                    JOIN public.enterprise AS en ON en.id = ae.enterprise_id
                    UNION ALL
                    SELECT lu.enterprise_id, 'legal_unit', lu.id
                    FROM _affected_enterprises AS ae
                    JOIN public.legal_unit AS lu ON lu.enterprise_id = ae.enterprise_id
                    UNION ALL
                    SELECT lu.enterprise_id, 'establishment', es.id
                    FROM _affected_enterprises AS ae
                    JOIN public.legal_unit AS lu ON lu.enterprise_id = ae.enterprise_id
                    JOIN public.establishment AS es ON es.legal_unit_id = lu.id
                    UNION ALL
                    SELECT es.enterprise_id, 'establishment', es.id
                    FROM _affected_enterprises AS ae
                    JOIN public.establishment AS es ON es.enterprise_id = ae.enterprise_id
                ) AS member
                LEFT JOIN _bridge_groups AS bg ON bg.enterprise_id = member.enterprise_id
                GROUP BY COALESCE(bg.group_id, member.enterprise_id)
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
                        v_acc_group_ids := '{}'; v_acc_enterprise_ids := '{}'; v_acc_legal_unit_ids := '{}'; v_acc_establishment_ids := '{}';
                    ELSE
                        SELECT v_current_change_set_seq,
                            (SELECT array_agg(DISTINCT x ORDER BY x) FROM unnest(v_acc_group_ids) AS x WHERE x IS NOT NULL),
                            (SELECT array_agg(DISTINCT x ORDER BY x) FROM unnest(v_acc_enterprise_ids) AS x WHERE x IS NOT NULL),
                            (SELECT array_agg(DISTINCT x ORDER BY x) FROM unnest(v_acc_legal_unit_ids) AS x WHERE x IS NOT NULL),
                            (SELECT array_agg(DISTINCT x ORDER BY x) FROM unnest(v_acc_establishment_ids) AS x WHERE x IS NOT NULL),
                            v_current_change_set_size, FALSE
                        INTO change_set_seq, group_ids, enterprise_ids, legal_unit_ids, establishment_ids, total_unit_count, has_more;
                        RETURN NEXT;
                        v_change_sets_returned := v_change_sets_returned + 1;
                        v_current_change_set_seq := v_current_change_set_seq + 1;
                        v_current_change_set_size := 0;
                        v_acc_group_ids := '{}'; v_acc_enterprise_ids := '{}'; v_acc_legal_unit_ids := '{}'; v_acc_establishment_ids := '{}';
                    END IF;
                END IF;
                v_acc_group_ids := v_acc_group_ids || v_group.group_id;
                v_acc_enterprise_ids := v_acc_enterprise_ids || v_group.enterprise_ids;
                v_acc_legal_unit_ids := v_acc_legal_unit_ids || COALESCE(v_group.legal_unit_ids, ARRAY[]::INT[]);
                v_acc_establishment_ids := v_acc_establishment_ids || COALESCE(v_group.establishment_ids, ARRAY[]::INT[]);
                v_current_change_set_size := v_current_change_set_size + v_group.total_unit_count;
            END LOOP;
        ELSE
            -- No bridges, filtered: scoped group query
            FOR v_group IN
                SELECT
                    member.enterprise_id AS group_id,
                    ARRAY[member.enterprise_id] AS enterprise_ids,
                    array_agg(DISTINCT member.unit_id ORDER BY member.unit_id)
                        FILTER (WHERE member.kind = 'legal_unit') AS legal_unit_ids,
                    array_agg(DISTINCT member.unit_id ORDER BY member.unit_id)
                        FILTER (WHERE member.kind = 'establishment') AS establishment_ids,
                    COUNT(DISTINCT (member.kind, member.unit_id))::INT AS total_unit_count
                FROM (
                    SELECT en.id AS enterprise_id, 'enterprise'::TEXT AS kind, en.id AS unit_id
                    FROM _affected_enterprises AS ae
                    JOIN public.enterprise AS en ON en.id = ae.enterprise_id
                    UNION ALL
                    SELECT lu.enterprise_id, 'legal_unit', lu.id
                    FROM _affected_enterprises AS ae
                    JOIN public.legal_unit AS lu ON lu.enterprise_id = ae.enterprise_id
                    UNION ALL
                    SELECT lu.enterprise_id, 'establishment', es.id
                    FROM _affected_enterprises AS ae
                    JOIN public.legal_unit AS lu ON lu.enterprise_id = ae.enterprise_id
                    JOIN public.establishment AS es ON es.legal_unit_id = lu.id
                    UNION ALL
                    SELECT es.enterprise_id, 'establishment', es.id
                    FROM _affected_enterprises AS ae
                    JOIN public.establishment AS es ON es.enterprise_id = ae.enterprise_id
                ) AS member
                GROUP BY member.enterprise_id
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
                        v_acc_group_ids := '{}'; v_acc_enterprise_ids := '{}'; v_acc_legal_unit_ids := '{}'; v_acc_establishment_ids := '{}';
                    ELSE
                        SELECT v_current_change_set_seq,
                            (SELECT array_agg(DISTINCT x ORDER BY x) FROM unnest(v_acc_group_ids) AS x WHERE x IS NOT NULL),
                            (SELECT array_agg(DISTINCT x ORDER BY x) FROM unnest(v_acc_enterprise_ids) AS x WHERE x IS NOT NULL),
                            (SELECT array_agg(DISTINCT x ORDER BY x) FROM unnest(v_acc_legal_unit_ids) AS x WHERE x IS NOT NULL),
                            (SELECT array_agg(DISTINCT x ORDER BY x) FROM unnest(v_acc_establishment_ids) AS x WHERE x IS NOT NULL),
                            v_current_change_set_size, FALSE
                        INTO change_set_seq, group_ids, enterprise_ids, legal_unit_ids, establishment_ids, total_unit_count, has_more;
                        RETURN NEXT;
                        v_change_sets_returned := v_change_sets_returned + 1;
                        v_current_change_set_seq := v_current_change_set_seq + 1;
                        v_current_change_set_size := 0;
                        v_acc_group_ids := '{}'; v_acc_enterprise_ids := '{}'; v_acc_legal_unit_ids := '{}'; v_acc_establishment_ids := '{}';
                    END IF;
                END IF;
                v_acc_group_ids := v_acc_group_ids || v_group.group_id;
                v_acc_enterprise_ids := v_acc_enterprise_ids || v_group.enterprise_ids;
                v_acc_legal_unit_ids := v_acc_legal_unit_ids || COALESCE(v_group.legal_unit_ids, ARRAY[]::INT[]);
                v_acc_establishment_ids := v_acc_establishment_ids || COALESCE(v_group.establishment_ids, ARRAY[]::INT[]);
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
                    COALESCE(bg.group_id, member.enterprise_id) AS group_id,
                    array_agg(DISTINCT member.unit_id ORDER BY member.unit_id)
                        FILTER (WHERE member.kind = 'enterprise') AS enterprise_ids,
                    array_agg(DISTINCT member.unit_id ORDER BY member.unit_id)
                        FILTER (WHERE member.kind = 'legal_unit') AS legal_unit_ids,
                    array_agg(DISTINCT member.unit_id ORDER BY member.unit_id)
                        FILTER (WHERE member.kind = 'establishment') AS establishment_ids,
                    COUNT(DISTINCT (member.kind, member.unit_id))::INT AS total_unit_count
                FROM (
                    SELECT en.id AS enterprise_id, 'enterprise'::TEXT AS kind, en.id AS unit_id
                    FROM public.enterprise AS en
                    UNION ALL
                    SELECT lu.enterprise_id, 'legal_unit', lu.id
                    FROM public.legal_unit AS lu
                    WHERE lu.enterprise_id IS NOT NULL
                    UNION ALL
                    SELECT lu.enterprise_id, 'establishment', es.id
                    FROM public.legal_unit AS lu
                    JOIN public.establishment AS es ON es.legal_unit_id = lu.id
                    WHERE lu.enterprise_id IS NOT NULL
                    UNION ALL
                    SELECT es.enterprise_id, 'establishment', es.id
                    FROM public.establishment AS es
                    WHERE es.enterprise_id IS NOT NULL
                ) AS member
                LEFT JOIN _bridge_groups AS bg ON bg.enterprise_id = member.enterprise_id
                GROUP BY COALESCE(bg.group_id, member.enterprise_id)
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
                        v_acc_group_ids := '{}'; v_acc_enterprise_ids := '{}'; v_acc_legal_unit_ids := '{}'; v_acc_establishment_ids := '{}';
                    ELSE
                        SELECT v_current_change_set_seq,
                            (SELECT array_agg(DISTINCT x ORDER BY x) FROM unnest(v_acc_group_ids) AS x WHERE x IS NOT NULL),
                            (SELECT array_agg(DISTINCT x ORDER BY x) FROM unnest(v_acc_enterprise_ids) AS x WHERE x IS NOT NULL),
                            (SELECT array_agg(DISTINCT x ORDER BY x) FROM unnest(v_acc_legal_unit_ids) AS x WHERE x IS NOT NULL),
                            (SELECT array_agg(DISTINCT x ORDER BY x) FROM unnest(v_acc_establishment_ids) AS x WHERE x IS NOT NULL),
                            v_current_change_set_size, FALSE
                        INTO change_set_seq, group_ids, enterprise_ids, legal_unit_ids, establishment_ids, total_unit_count, has_more;
                        RETURN NEXT;
                        v_change_sets_returned := v_change_sets_returned + 1;
                        v_current_change_set_seq := v_current_change_set_seq + 1;
                        v_current_change_set_size := 0;
                        v_acc_group_ids := '{}'; v_acc_enterprise_ids := '{}'; v_acc_legal_unit_ids := '{}'; v_acc_establishment_ids := '{}';
                    END IF;
                END IF;
                v_acc_group_ids := v_acc_group_ids || v_group.group_id;
                v_acc_enterprise_ids := v_acc_enterprise_ids || v_group.enterprise_ids;
                v_acc_legal_unit_ids := v_acc_legal_unit_ids || COALESCE(v_group.legal_unit_ids, ARRAY[]::INT[]);
                v_acc_establishment_ids := v_acc_establishment_ids || COALESCE(v_group.establishment_ids, ARRAY[]::INT[]);
                v_current_change_set_size := v_current_change_set_size + v_group.total_unit_count;
            END LOOP;
        ELSE
            FOR v_group IN
                SELECT
                    member.enterprise_id AS group_id,
                    ARRAY[member.enterprise_id] AS enterprise_ids,
                    array_agg(DISTINCT member.unit_id ORDER BY member.unit_id)
                        FILTER (WHERE member.kind = 'legal_unit') AS legal_unit_ids,
                    array_agg(DISTINCT member.unit_id ORDER BY member.unit_id)
                        FILTER (WHERE member.kind = 'establishment') AS establishment_ids,
                    COUNT(DISTINCT (member.kind, member.unit_id))::INT AS total_unit_count
                FROM (
                    SELECT en.id AS enterprise_id, 'enterprise'::TEXT AS kind, en.id AS unit_id
                    FROM public.enterprise AS en
                    UNION ALL
                    SELECT lu.enterprise_id, 'legal_unit', lu.id
                    FROM public.legal_unit AS lu
                    WHERE lu.enterprise_id IS NOT NULL
                    UNION ALL
                    SELECT lu.enterprise_id, 'establishment', es.id
                    FROM public.legal_unit AS lu
                    JOIN public.establishment AS es ON es.legal_unit_id = lu.id
                    WHERE lu.enterprise_id IS NOT NULL
                    UNION ALL
                    SELECT es.enterprise_id, 'establishment', es.id
                    FROM public.establishment AS es
                    WHERE es.enterprise_id IS NOT NULL
                ) AS member
                GROUP BY member.enterprise_id
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
                        v_acc_group_ids := '{}'; v_acc_enterprise_ids := '{}'; v_acc_legal_unit_ids := '{}'; v_acc_establishment_ids := '{}';
                    ELSE
                        SELECT v_current_change_set_seq,
                            (SELECT array_agg(DISTINCT x ORDER BY x) FROM unnest(v_acc_group_ids) AS x WHERE x IS NOT NULL),
                            (SELECT array_agg(DISTINCT x ORDER BY x) FROM unnest(v_acc_enterprise_ids) AS x WHERE x IS NOT NULL),
                            (SELECT array_agg(DISTINCT x ORDER BY x) FROM unnest(v_acc_legal_unit_ids) AS x WHERE x IS NOT NULL),
                            (SELECT array_agg(DISTINCT x ORDER BY x) FROM unnest(v_acc_establishment_ids) AS x WHERE x IS NOT NULL),
                            v_current_change_set_size, FALSE
                        INTO change_set_seq, group_ids, enterprise_ids, legal_unit_ids, establishment_ids, total_unit_count, has_more;
                        RETURN NEXT;
                        v_change_sets_returned := v_change_sets_returned + 1;
                        v_current_change_set_seq := v_current_change_set_seq + 1;
                        v_current_change_set_size := 0;
                        v_acc_group_ids := '{}'; v_acc_enterprise_ids := '{}'; v_acc_legal_unit_ids := '{}'; v_acc_establishment_ids := '{}';
                    END IF;
                END IF;
                v_acc_group_ids := v_acc_group_ids || v_group.group_id;
                v_acc_enterprise_ids := v_acc_enterprise_ids || v_group.enterprise_ids;
                v_acc_legal_unit_ids := v_acc_legal_unit_ids || COALESCE(v_group.legal_unit_ids, ARRAY[]::INT[]);
                v_acc_establishment_ids := v_acc_establishment_ids || COALESCE(v_group.establishment_ids, ARRAY[]::INT[]);
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
                (SELECT array_agg(DISTINCT x ORDER BY x) FROM unnest(v_acc_group_ids) AS x WHERE x IS NOT NULL),
                (SELECT array_agg(DISTINCT x ORDER BY x) FROM unnest(v_acc_enterprise_ids) AS x WHERE x IS NOT NULL),
                (SELECT array_agg(DISTINCT x ORDER BY x) FROM unnest(v_acc_legal_unit_ids) AS x WHERE x IS NOT NULL),
                (SELECT array_agg(DISTINCT x ORDER BY x) FROM unnest(v_acc_establishment_ids) AS x WHERE x IS NOT NULL),
                v_current_change_set_size, FALSE
            INTO change_set_seq, group_ids, enterprise_ids, legal_unit_ids, establishment_ids, total_unit_count, has_more;
            RETURN NEXT;
        END IF;
    END IF;
END;
$function$
;

END;
