```sql
CREATE OR REPLACE PROCEDURE import.process_power_group_link(IN p_job_id integer, IN p_batch_seq integer, IN p_step_code text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'import', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_job public.import_job;
    v_definition public.import_definition;
    v_data_table_name TEXT;
    _cluster RECORD;
    _power_group public.power_group;
    _created_count integer := 0;
    _updated_count integer := 0;
    _linked_count integer := 0;
    _row_count integer;
    _iter integer;
    _current_user_id integer;
BEGIN
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;

    SELECT * INTO v_definition
    FROM jsonb_populate_record(NULL::public.import_definition, v_job.definition_snapshot->'import_definition');

    -- Only run for legal_relationship mode (IS DISTINCT FROM is NULL-safe: NULL skips correctly)
    IF v_definition.mode IS DISTINCT FROM 'legal_relationship' THEN
        RAISE DEBUG '[Job %] process_power_group_link: Skipping, mode is %', p_job_id, v_definition.mode;
        RETURN;
    END IF;

    RAISE DEBUG '[Job %] process_power_group_link: Creating/updating power groups (holistic)', p_job_id;

    -- Change-detection triggers (log_base_change + ensure_collect_changes) stay
    -- ENABLED. The derived_power_group_id UPDATEs re-log LU IDs to base_change_log so
    -- that collect_changes (on the analytics queue) sees correct derived_power_group_ids.
    -- This is safe: log rows merge via multirange, ensure_collect is idempotent.

    -- Use the importing user from the job, not session_user (which is the worker's DB role)
    _current_user_id := v_job.user_id;
    IF _current_user_id IS NULL THEN
        RAISE EXCEPTION 'Import job % has no user_id', p_job_id;
    END IF;

    -- ================================================================
    -- Compute connected components via iterative label propagation.
    -- Replaces the legal_relationship_cluster view which evaluates
    -- the old power_hierarchy view (a multi-phase recursive CTE, cost ~17M).
    -- This approach: O(edges × depth) ≈ O(29K × 5) ≈ ~150K ops, ~1s.
    -- ================================================================

    -- Build bidirectional edge list from relationships
    IF to_regclass('pg_temp._edges') IS NOT NULL THEN
        DROP TABLE _edges;
    END IF;
    CREATE TEMP TABLE _edges ON COMMIT DROP AS
    SELECT influencing_id AS a, influenced_id AS b FROM public.legal_relationship
    UNION ALL
    SELECT influenced_id, influencing_id FROM public.legal_relationship;
    CREATE INDEX ON _edges (a);

    -- Each LU starts as its own component (component_id = lu_id)
    IF to_regclass('pg_temp._lu_comp') IS NOT NULL THEN
        DROP TABLE _lu_comp;
    END IF;
    CREATE TEMP TABLE _lu_comp (lu_id integer PRIMARY KEY, comp_id integer) ON COMMIT DROP;
    INSERT INTO _lu_comp SELECT DISTINCT a, a FROM _edges;

    -- Propagate minimum component_id through edges until stable
    _iter := 0;
    LOOP
        _iter := _iter + 1;
        UPDATE _lu_comp AS c
        SET comp_id = sub.min_comp
        FROM (
            SELECT e.a AS lu_id, MIN(c2.comp_id) AS min_comp
            FROM _edges AS e
            JOIN _lu_comp AS c2 ON c2.lu_id = e.b
            GROUP BY e.a
        ) AS sub
        WHERE c.lu_id = sub.lu_id AND sub.min_comp < c.comp_id;
        GET DIAGNOSTICS _row_count = ROW_COUNT;
        EXIT WHEN _row_count = 0;
        IF _iter > 100 THEN
            RAISE EXCEPTION '[Job %] process_power_group_link: Connected components did not converge after 100 iterations', p_job_id;
        END IF;
    END LOOP;
    RAISE DEBUG '[Job %] process_power_group_link: Connected components converged in % iterations', p_job_id, _iter;

    -- Map each relationship to its component (= cluster root)
    IF to_regclass('pg_temp._lr_clusters') IS NOT NULL THEN
        DROP TABLE _lr_clusters;
    END IF;
    CREATE TEMP TABLE _lr_clusters ON COMMIT DROP AS
    SELECT lr.id AS legal_relationship_id, c.comp_id AS root_legal_unit_id
    FROM public.legal_relationship AS lr
    JOIN _lu_comp AS c ON c.lu_id = lr.influencing_id;
    CREATE INDEX ON _lr_clusters (root_legal_unit_id);
    CREATE INDEX ON _lr_clusters (legal_relationship_id);

    -- Find existing power_group per cluster (set-based, no loop needed)
    IF to_regclass('pg_temp._cluster_pg') IS NOT NULL THEN
        DROP TABLE _cluster_pg;
    END IF;
    CREATE TEMP TABLE _cluster_pg (
        root_legal_unit_id integer,
        power_group_id integer
    ) ON COMMIT DROP;

    INSERT INTO _cluster_pg (root_legal_unit_id, power_group_id)
    SELECT DISTINCT ON (lrc.root_legal_unit_id)
        lrc.root_legal_unit_id,
        lr.derived_power_group_id
    FROM _lr_clusters AS lrc
    JOIN public.legal_relationship AS lr ON lr.id = lrc.legal_relationship_id
    WHERE lr.derived_power_group_id IS NOT NULL
    ORDER BY lrc.root_legal_unit_id;

    _updated_count := (SELECT count(*) FROM _cluster_pg);

    -- Create new power_groups only for clusters that don't have one yet
    FOR _cluster IN
        SELECT DISTINCT lrc.root_legal_unit_id
        FROM _lr_clusters AS lrc
        WHERE NOT EXISTS (
            SELECT 1 FROM _cluster_pg AS cpg
            WHERE cpg.root_legal_unit_id = lrc.root_legal_unit_id
        )
    LOOP
        INSERT INTO public.power_group (edit_by_user_id)
        VALUES (_current_user_id)
        RETURNING * INTO _power_group;

        INSERT INTO _cluster_pg (root_legal_unit_id, power_group_id)
        VALUES (_cluster.root_legal_unit_id, _power_group.id);

        _created_count := _created_count + 1;
        RAISE DEBUG '[Job %] process_power_group_link: Created power_group % for root LU %',
            p_job_id, _power_group.ident, _cluster.root_legal_unit_id;
    END LOOP;

    -- Bulk-update all relationships at once (single pass over indexed temp tables)
    UPDATE public.legal_relationship AS lr
    SET derived_power_group_id = cpg.power_group_id
    FROM _lr_clusters AS lrc
    JOIN _cluster_pg AS cpg ON cpg.root_legal_unit_id = lrc.root_legal_unit_id
    WHERE lr.id = lrc.legal_relationship_id
      AND lr.derived_power_group_id IS DISTINCT FROM cpg.power_group_id;
    GET DIAGNOSTICS _linked_count = ROW_COUNT;

    -- Handle cluster merges (multiple power_groups pointing to same cluster)
    WITH cluster_sizes AS (
        SELECT lr.derived_power_group_id, COUNT(*) AS rel_count
        FROM public.legal_relationship AS lr
        WHERE lr.derived_power_group_id IS NOT NULL
        GROUP BY lr.derived_power_group_id
    ),
    merge_candidates AS (
        SELECT DISTINCT lrc.root_legal_unit_id, lr.derived_power_group_id AS current_pg_id, cs.rel_count
        FROM _lr_clusters AS lrc
        JOIN public.legal_relationship AS lr ON lr.id = lrc.legal_relationship_id
        JOIN cluster_sizes AS cs ON cs.derived_power_group_id = lr.derived_power_group_id
        WHERE lr.derived_power_group_id IS NOT NULL
    ),
    clusters_with_multiple_pgs AS (
        SELECT root_legal_unit_id, array_agg(current_pg_id ORDER BY rel_count DESC, current_pg_id) AS pg_ids
        FROM merge_candidates GROUP BY root_legal_unit_id HAVING COUNT(DISTINCT current_pg_id) > 1
    )
    UPDATE public.legal_relationship AS lr
    SET derived_power_group_id = cwmp.pg_ids[1]
    FROM _lr_clusters AS lrc
    JOIN clusters_with_multiple_pgs AS cwmp ON cwmp.root_legal_unit_id = lrc.root_legal_unit_id
    WHERE lr.id = lrc.legal_relationship_id AND lr.derived_power_group_id != cwmp.pg_ids[1];
    GET DIAGNOSTICS _row_count = ROW_COUNT;
    IF _row_count > 0 THEN
        RAISE DEBUG '[Job %] process_power_group_link: Merged % relationships into surviving power groups', p_job_id, _row_count;
    END IF;

    RAISE DEBUG '[Job %] process_power_group_link: Completed: created=%, updated=%, linked=%',
        p_job_id, _created_count, _updated_count, _linked_count;

    -- ================================================================
    -- Compute derived_influenced_power_level via BFS from roots.
    -- Root LUs (level 1) are implicit — influencing LUs never influenced
    -- within the same PG. Each LR stores the influenced LU's BFS depth:
    --   root→child: level 2, child→grandchild: level 3, etc.
    -- Cycles (no natural root) get NULL — identified by power_root below.
    -- ================================================================

    IF to_regclass('pg_temp._bfs') IS NOT NULL THEN
        DROP TABLE _bfs;
    END IF;
    CREATE TEMP TABLE _bfs (lu_id integer, level integer, pg_id integer) ON COMMIT DROP;

    -- Seed: root LUs (influencing, never influenced in same PG) at level 1
    INSERT INTO _bfs (lu_id, level, pg_id)
    SELECT DISTINCT lr.influencing_id, 1, lr.derived_power_group_id
    FROM public.legal_relationship AS lr
    WHERE lr.derived_power_group_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.legal_relationship AS lr2
        WHERE lr2.influenced_id = lr.influencing_id
          AND lr2.derived_power_group_id = lr.derived_power_group_id
      );
    CREATE INDEX ON _bfs (lu_id, pg_id);

    -- Propagate through directed edges (influencing → influenced)
    _iter := 0;
    LOOP
        _iter := _iter + 1;
        INSERT INTO _bfs (lu_id, level, pg_id)
        SELECT DISTINCT lr.influenced_id, b.level + 1, b.pg_id
        FROM _bfs AS b
        JOIN public.legal_relationship AS lr
            ON lr.influencing_id = b.lu_id
            AND lr.derived_power_group_id = b.pg_id
        WHERE b.level = _iter  -- only expand frontier
          AND NOT EXISTS (
            SELECT 1 FROM _bfs AS b2
            WHERE b2.lu_id = lr.influenced_id AND b2.pg_id = b.pg_id
        );
        GET DIAGNOSTICS _row_count = ROW_COUNT;
        EXIT WHEN _row_count = 0;
        IF _iter > 100 THEN
            RAISE EXCEPTION '[Job %] process_power_group_link: BFS did not converge after 100 iterations', p_job_id;
        END IF;
    END LOOP;
    RAISE DEBUG '[Job %] process_power_group_link: BFS power levels converged in % iterations', p_job_id, _iter;

    -- Update derived_influenced_power_level on each LR
    -- The influenced LU's BFS level becomes the LR's power level
    UPDATE public.legal_relationship AS lr
    SET derived_influenced_power_level = b.level
    FROM _bfs AS b
    WHERE b.lu_id = lr.influenced_id
      AND b.pg_id = lr.derived_power_group_id
      AND lr.derived_influenced_power_level IS DISTINCT FROM b.level;
    GET DIAGNOSTICS _row_count = ROW_COUNT;
    RAISE DEBUG '[Job %] process_power_group_link: Updated derived_influenced_power_level on % relationships', p_job_id, _row_count;

    -- Clear stale levels for LRs no longer in a PG or in cycles (no BFS root)
    UPDATE public.legal_relationship AS lr
    SET derived_influenced_power_level = NULL
    WHERE lr.derived_influenced_power_level IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM _bfs AS b
        WHERE b.lu_id = lr.influenced_id AND b.pg_id = lr.derived_power_group_id
    );
    GET DIAGNOSTICS _row_count = ROW_COUNT;
    IF _row_count > 0 THEN
        RAISE DEBUG '[Job %] process_power_group_link: Cleared stale power levels on % relationships', p_job_id, _row_count;
    END IF;

    -- ================================================================
    -- Populate power_root for cycle/multi PGs via temporal_merge.
    -- Uses graph-based detection from _lu_comp/_edges instead of the
    -- the old power_hierarchy view (cost ~17M).
    -- ================================================================

    -- Disable power_root change tracking triggers to prevent enqueue loop during temporal_merge.
    -- Must NOT disable power_root_valid_sync_temporal_trg (sql_saga sync for valid_from/valid_until).
    ALTER TABLE public.power_root DISABLE TRIGGER a_power_root_log_insert;
    ALTER TABLE public.power_root DISABLE TRIGGER a_power_root_log_update;
    ALTER TABLE public.power_root DISABLE TRIGGER a_power_root_log_delete;
    ALTER TABLE public.power_root DISABLE TRIGGER b_power_root_ensure_collect_insert;
    ALTER TABLE public.power_root DISABLE TRIGGER b_power_root_ensure_collect_update;
    ALTER TABLE public.power_root DISABLE TRIGGER b_power_root_ensure_collect_delete;

    -- Detect natural roots: LUs that influence others but are NOT influenced
    IF to_regclass('pg_temp._natural_roots') IS NOT NULL THEN
        DROP TABLE _natural_roots;
    END IF;
    CREATE TEMP TABLE _natural_roots ON COMMIT DROP AS
    SELECT DISTINCT ing.lu_id, c.comp_id
    FROM (SELECT DISTINCT influencing_id AS lu_id FROM public.legal_relationship) AS ing
    JOIN _lu_comp AS c ON c.lu_id = ing.lu_id
    WHERE NOT EXISTS (
        SELECT 1 FROM public.legal_relationship AS lr
        WHERE lr.influenced_id = ing.lu_id
    );
    CREATE INDEX ON _natural_roots (comp_id);

    -- Count natural roots per component to classify cycle/multi
    IF to_regclass('pg_temp._comp_status') IS NOT NULL THEN
        DROP TABLE _comp_status;
    END IF;
    CREATE TEMP TABLE _comp_status ON COMMIT DROP AS
    SELECT
        c.comp_id,
        cpg.power_group_id,
        CASE
            WHEN nr.root_count IS NULL OR nr.root_count = 0 THEN 'cycle'::public.power_group_root_status
            WHEN nr.root_count > 1 THEN 'multi'::public.power_group_root_status
        END AS derived_root_status,
        -- Pick the natural root LU (for multi: smallest id; for cycle: comp_id as synthetic root)
        COALESCE(nr.min_root_lu_id, c.comp_id) AS derived_root_legal_unit_id
    FROM (SELECT DISTINCT comp_id FROM _lu_comp) AS c
    JOIN _cluster_pg AS cpg ON cpg.root_legal_unit_id = c.comp_id
    LEFT JOIN (
        SELECT comp_id, count(*) AS root_count, min(lu_id) AS min_root_lu_id
        FROM _natural_roots
        GROUP BY comp_id
    ) AS nr ON nr.comp_id = c.comp_id
    WHERE nr.root_count IS NULL OR nr.root_count = 0 OR nr.root_count > 1;

    IF to_regclass('pg_temp._power_root_source') IS NOT NULL THEN
        DROP TABLE _power_root_source;
    END IF;
    CREATE TEMP TABLE _power_root_source (
        row_id integer GENERATED BY DEFAULT AS IDENTITY,
        power_group_id integer,
        derived_root_legal_unit_id integer,
        derived_root_status public.power_group_root_status,
        custom_root_legal_unit_id integer,
        valid_range daterange,
        edit_by_user_id integer
    ) ON COMMIT DROP;

    -- Build power_root source rows from cycle/multi components.
    -- Use the union of valid_ranges from the component's relationships as the time span.
    INSERT INTO _power_root_source (power_group_id, derived_root_legal_unit_id, derived_root_status, custom_root_legal_unit_id, valid_range, edit_by_user_id)
    SELECT
        cs.power_group_id,
        cs.derived_root_legal_unit_id,
        cs.derived_root_status,
        -- Carry forward existing custom_root if any
        existing_pr.custom_root_legal_unit_id,
        lr_range.valid_range,
        _current_user_id
    FROM _comp_status AS cs
    CROSS JOIN LATERAL (
        -- Get distinct valid_ranges for relationships in this component
        SELECT DISTINCT lr.valid_range
        FROM public.legal_relationship AS lr
        JOIN _lu_comp AS c ON c.lu_id = lr.influencing_id
        WHERE c.comp_id = cs.comp_id
    ) AS lr_range
    LEFT JOIN public.power_root AS existing_pr
        ON existing_pr.power_group_id = cs.power_group_id
        AND existing_pr.valid_range && lr_range.valid_range;

    GET DIAGNOSTICS _row_count = ROW_COUNT;
    RAISE DEBUG '[Job %] process_power_group_link: power_root source rows: % (cycle/multi PGs)', p_job_id, _row_count;

    -- Only run temporal_merge if there are source rows or existing rows to clean up
    IF EXISTS (SELECT 1 FROM _power_root_source) OR EXISTS (SELECT 1 FROM public.power_root) THEN
        CALL sql_saga.temporal_merge(
            target_table => 'public.power_root'::regclass,
            source_table => '_power_root_source'::regclass,
            primary_identity_columns => ARRAY['id'],
            natural_identity_columns => ARRAY['power_group_id'],
            mode => 'MERGE_ENTITY_REPLACE'::sql_saga.temporal_merge_mode
        );
        GET DIAGNOSTICS _row_count = ROW_COUNT;
        RAISE DEBUG '[Job %] process_power_group_link: temporal_merge power_root affected % rows', p_job_id, _row_count;
    END IF;

    ALTER TABLE public.power_root ENABLE TRIGGER a_power_root_log_insert;
    ALTER TABLE public.power_root ENABLE TRIGGER a_power_root_log_update;
    ALTER TABLE public.power_root ENABLE TRIGGER a_power_root_log_delete;
    ALTER TABLE public.power_root ENABLE TRIGGER b_power_root_ensure_collect_insert;
    ALTER TABLE public.power_root ENABLE TRIGGER b_power_root_ensure_collect_update;
    ALTER TABLE public.power_root ENABLE TRIGGER b_power_root_ensure_collect_delete;
END;
$procedure$
```
