-- STATBUS-124 UP: 0-index power_level (root=0); depth=max(power_level). depth/width/reach values unchanged.
BEGIN;

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
    -- Root LUs (level 0) are implicit — influencing LUs never influenced
    -- within the same PG. Each LR stores the influenced LU's BFS depth:
    --   root→child: level 1, child→grandchild: level 2, etc.
    -- Cycles (no natural root) get NULL — identified by power_root below.
    -- ================================================================

    IF to_regclass('pg_temp._bfs') IS NOT NULL THEN
        DROP TABLE _bfs;
    END IF;
    CREATE TEMP TABLE _bfs (lu_id integer, level integer, pg_id integer) ON COMMIT DROP;

    -- Seed: root LUs (influencing, never influenced in same PG) at level 0
    INSERT INTO _bfs (lu_id, level, pg_id)
    SELECT DISTINCT lr.influencing_id, 0, lr.derived_power_group_id
    FROM public.legal_relationship AS lr
    WHERE lr.derived_power_group_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.legal_relationship AS lr2
        WHERE lr2.influenced_id = lr.influencing_id
          AND lr2.derived_power_group_id = lr.derived_power_group_id
      );
    CREATE INDEX ON _bfs (lu_id, pg_id);

    -- Propagate through directed edges (influencing → influenced)
    -- Seed roots at level 0, so the frontier starts at _iter=0 (−1 then +1).
    _iter := -1;
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
END;
$procedure$
;

CREATE OR REPLACE VIEW public.power_group_membership
 WITH (security_invoker='on') AS
 SELECT DISTINCT lr.derived_power_group_id AS power_group_id,
    pg.ident AS power_group_ident,
    lr.influencing_id AS legal_unit_id,
    0 AS power_level,
    lr.valid_range
   FROM legal_relationship lr
     JOIN power_group pg ON pg.id = lr.derived_power_group_id
  WHERE lr.derived_power_group_id IS NOT NULL AND NOT (EXISTS ( SELECT 1
           FROM legal_relationship lr2
          WHERE lr2.influenced_id = lr.influencing_id AND lr2.derived_power_group_id = lr.derived_power_group_id AND lr2.valid_range && lr.valid_range))
UNION
 SELECT lr.derived_power_group_id AS power_group_id,
    pg.ident AS power_group_ident,
    lr.influenced_id AS legal_unit_id,
    lr.derived_influenced_power_level AS power_level,
    lr.valid_range
   FROM legal_relationship lr
     JOIN power_group pg ON pg.id = lr.derived_power_group_id
  WHERE lr.derived_power_group_id IS NOT NULL AND lr.derived_influenced_power_level IS NOT NULL
;

CREATE OR REPLACE VIEW public.power_group_def
 WITH (security_invoker='on') AS
 SELECT power_group_id,
    max(power_level) AS depth,
    count(*) FILTER (WHERE power_level = 1) AS width,
    count(*) - 1 AS reach
   FROM power_group_membership pgm
  GROUP BY power_group_id
;

-- Re-base the STORED child levels to match root=0 (uniform −1). derived_influenced_power_level
-- is read only by power_group_membership (verified via pg_depend) + the sql_saga passthrough
-- temporal view — nothing interprets its absolute value. On a fresh import the procedure
-- recomputes these idempotently (IS DISTINCT FROM guard); this UPDATE keeps a LIVE-DB upgrade
-- consistent (root=0 with children 1,2,… not stale 2,3,…) before the next import runs.
-- Cycles (NULL level) untouched. Min stored value today is 2 (root's direct children) → 1.
UPDATE public.legal_relationship
SET derived_influenced_power_level = derived_influenced_power_level - 1
WHERE derived_influenced_power_level IS NOT NULL;


-- STATBUS-124 missed ripple (root selectors): timeline_power_group_def / statistical_unit_enterprise_id / timeline_power_group_refresh select the root LU via power_level; re-base 1->0.
CREATE OR REPLACE VIEW public.timeline_power_group_def
 WITH (security_invoker='on') AS
 WITH aggregation AS (
         SELECT tpg.power_group_id,
            tpg.valid_from,
            tpg.valid_until,
            array_distinct_concat(tlu.data_source_ids) AS data_source_ids,
            array_distinct_concat(tlu.data_source_codes) AS data_source_codes,
            array_distinct_concat(tlu.related_establishment_ids) AS related_establishment_ids,
            array_distinct_concat(tlu.excluded_establishment_ids) AS excluded_establishment_ids,
            array_distinct_concat(tlu.included_establishment_ids) AS included_establishment_ids,
            array_agg(DISTINCT tlu.legal_unit_id) AS related_legal_unit_ids,
            array_agg(DISTINCT tlu.legal_unit_id) FILTER (WHERE NOT tlu.used_for_counting) AS excluded_legal_unit_ids,
            array_agg(DISTINCT tlu.legal_unit_id) FILTER (WHERE tlu.used_for_counting) AS included_legal_unit_ids,
            array_agg(DISTINCT tlu.enterprise_id) AS related_enterprise_ids,
            array_agg(DISTINCT tlu.enterprise_id) FILTER (WHERE NOT tlu.used_for_counting) AS excluded_enterprise_ids,
            array_agg(DISTINCT tlu.enterprise_id) FILTER (WHERE tlu.used_for_counting) AS included_enterprise_ids,
            COALESCE(jsonb_stats_merge_agg(tlu.stats_summary) FILTER (WHERE tlu.used_for_counting), '{}'::jsonb) AS stats_summary
           FROM ( SELECT t.unit_type,
                    t.unit_id,
                    t.valid_from,
                    t.valid_until,
                    pg.id AS power_group_id
                   FROM timesegments t
                     JOIN power_group pg ON t.unit_type = 'power_group'::statistical_unit_type AND t.unit_id = pg.id) tpg
             LEFT JOIN LATERAL ( SELECT tlu_inner.legal_unit_id,
                    tlu_inner.enterprise_id,
                    tlu_inner.data_source_ids,
                    tlu_inner.data_source_codes,
                    tlu_inner.related_establishment_ids,
                    tlu_inner.excluded_establishment_ids,
                    tlu_inner.included_establishment_ids,
                    tlu_inner.used_for_counting,
                    tlu_inner.stats_summary
                   FROM power_group_membership pgm
                     JOIN timeline_legal_unit tlu_inner ON tlu_inner.legal_unit_id = pgm.legal_unit_id AND from_until_overlaps(tpg.valid_from, tpg.valid_until, tlu_inner.valid_from, tlu_inner.valid_until)
                  WHERE pgm.power_group_id = tpg.power_group_id AND pgm.valid_range && daterange(tpg.valid_from, tpg.valid_until)) tlu ON true
          GROUP BY tpg.power_group_id, tpg.valid_from, tpg.valid_until
        ), power_group_basis AS (
         SELECT tpg.unit_type,
            tpg.unit_id,
            tpg.valid_from,
            tpg.valid_until,
            tpg.power_group_id,
            COALESCE(NULLIF(tpg.short_name::text, ''::text), pgplu.name::text) AS name,
            pgplu.birth_date,
            pgplu.death_date,
            pgplu.primary_activity_category_id,
            pgplu.primary_activity_category_path,
            pgplu.primary_activity_category_code,
            pgplu.secondary_activity_category_id,
            pgplu.secondary_activity_category_path,
            pgplu.secondary_activity_category_code,
            pgplu.sector_id,
            pgplu.sector_path,
            pgplu.sector_code,
            pgplu.sector_name,
            pgplu.data_source_ids,
            pgplu.data_source_codes,
            pgplu.legal_form_id,
            pgplu.legal_form_code,
            pgplu.legal_form_name,
            pgplu.physical_address_part1,
            pgplu.physical_address_part2,
            pgplu.physical_address_part3,
            pgplu.physical_postcode,
            pgplu.physical_postplace,
            pgplu.physical_region_id,
            pgplu.physical_region_path,
            pgplu.physical_region_code,
            pgplu.physical_country_id,
            pgplu.physical_country_iso_2,
            pgplu.physical_latitude,
            pgplu.physical_longitude,
            pgplu.physical_altitude,
            pgplu.domestic,
            pgplu.postal_address_part1,
            pgplu.postal_address_part2,
            pgplu.postal_address_part3,
            pgplu.postal_postcode,
            pgplu.postal_postplace,
            pgplu.postal_region_id,
            pgplu.postal_region_path,
            pgplu.postal_region_code,
            pgplu.postal_country_id,
            pgplu.postal_country_iso_2,
            pgplu.postal_latitude,
            pgplu.postal_longitude,
            pgplu.postal_altitude,
            pgplu.web_address,
            pgplu.email_address,
            pgplu.phone_number,
            pgplu.landline,
            pgplu.mobile_number,
            pgplu.fax_number,
            pgplu.unit_size_id,
            pgplu.unit_size_code,
            pgplu.status_id,
            pgplu.status_code,
            true AS used_for_counting,
            last_edit.edit_comment AS last_edit_comment,
            last_edit.edit_by_user_id AS last_edit_by_user_id,
            last_edit.edit_at AS last_edit_at,
                CASE
                    WHEN pgplu.legal_unit_id IS NOT NULL THEN true
                    ELSE false
                END AS has_legal_unit,
            pgplu.legal_unit_id AS primary_legal_unit_id
           FROM ( SELECT t.unit_type,
                    t.unit_id,
                    t.valid_from,
                    t.valid_until,
                    pg.id AS power_group_id,
                    pg.short_name,
                    pg.edit_comment,
                    pg.edit_by_user_id,
                    pg.edit_at
                   FROM timesegments t
                     JOIN power_group pg ON t.unit_type = 'power_group'::statistical_unit_type AND t.unit_id = pg.id) tpg
             LEFT JOIN LATERAL ( SELECT tlu_p.legal_unit_id,
                    tlu_p.enterprise_id,
                    tlu_p.name,
                    tlu_p.birth_date,
                    tlu_p.death_date,
                    tlu_p.primary_activity_category_id,
                    tlu_p.primary_activity_category_path,
                    tlu_p.primary_activity_category_code,
                    tlu_p.secondary_activity_category_id,
                    tlu_p.secondary_activity_category_path,
                    tlu_p.secondary_activity_category_code,
                    tlu_p.sector_id,
                    tlu_p.sector_path,
                    tlu_p.sector_code,
                    tlu_p.sector_name,
                    tlu_p.data_source_ids,
                    tlu_p.data_source_codes,
                    tlu_p.legal_form_id,
                    tlu_p.legal_form_code,
                    tlu_p.legal_form_name,
                    tlu_p.physical_address_part1,
                    tlu_p.physical_address_part2,
                    tlu_p.physical_address_part3,
                    tlu_p.physical_postcode,
                    tlu_p.physical_postplace,
                    tlu_p.physical_region_id,
                    tlu_p.physical_region_path,
                    tlu_p.physical_region_code,
                    tlu_p.physical_country_id,
                    tlu_p.physical_country_iso_2,
                    tlu_p.physical_latitude,
                    tlu_p.physical_longitude,
                    tlu_p.physical_altitude,
                    tlu_p.domestic,
                    tlu_p.postal_address_part1,
                    tlu_p.postal_address_part2,
                    tlu_p.postal_address_part3,
                    tlu_p.postal_postcode,
                    tlu_p.postal_postplace,
                    tlu_p.postal_region_id,
                    tlu_p.postal_region_path,
                    tlu_p.postal_region_code,
                    tlu_p.postal_country_id,
                    tlu_p.postal_country_iso_2,
                    tlu_p.postal_latitude,
                    tlu_p.postal_longitude,
                    tlu_p.postal_altitude,
                    tlu_p.web_address,
                    tlu_p.email_address,
                    tlu_p.phone_number,
                    tlu_p.landline,
                    tlu_p.mobile_number,
                    tlu_p.fax_number,
                    tlu_p.unit_size_id,
                    tlu_p.unit_size_code,
                    tlu_p.status_id,
                    tlu_p.status_code,
                    tlu_p.last_edit_comment,
                    tlu_p.last_edit_by_user_id,
                    tlu_p.last_edit_at
                   FROM power_group_membership pgm
                     JOIN timeline_legal_unit tlu_p ON tlu_p.legal_unit_id = pgm.legal_unit_id AND from_until_overlaps(tpg.valid_from, tpg.valid_until, tlu_p.valid_from, tlu_p.valid_until)
                  WHERE pgm.power_group_id = tpg.power_group_id AND pgm.power_level = 0 AND pgm.valid_range && daterange(tpg.valid_from, tpg.valid_until)
                  ORDER BY tlu_p.valid_from DESC, tlu_p.legal_unit_id DESC
                 LIMIT 1) pgplu ON true
             LEFT JOIN LATERAL ( SELECT all_edits.edit_comment,
                    all_edits.edit_by_user_id,
                    all_edits.edit_at
                   FROM ( VALUES (tpg.edit_comment,tpg.edit_by_user_id,tpg.edit_at), (pgplu.last_edit_comment,pgplu.last_edit_by_user_id,pgplu.last_edit_at)) all_edits(edit_comment, edit_by_user_id, edit_at)
                  WHERE all_edits.edit_at IS NOT NULL
                  ORDER BY all_edits.edit_at DESC
                 LIMIT 1) last_edit ON true
        )
 SELECT b.unit_type,
    b.unit_id,
    b.valid_from,
    (b.valid_until - '1 day'::interval)::date AS valid_to,
    b.valid_until,
    b.name,
    b.birth_date,
    b.death_date,
    to_tsvector('simple'::regconfig, COALESCE(b.name, ''::text)) AS search,
    b.primary_activity_category_id,
    b.primary_activity_category_path,
    b.primary_activity_category_code,
    b.secondary_activity_category_id,
    b.secondary_activity_category_path,
    b.secondary_activity_category_code,
    NULLIF(array_remove(ARRAY[b.primary_activity_category_path, b.secondary_activity_category_path], NULL::ltree), '{}'::ltree[]) AS activity_category_paths,
    b.sector_id,
    b.sector_path,
    b.sector_code,
    b.sector_name,
    COALESCE(( SELECT array_agg(DISTINCT ids.id) AS array_agg
           FROM ( SELECT unnest(b.data_source_ids) AS id
                UNION
                 SELECT unnest(a.data_source_ids) AS id) ids), a.data_source_ids, b.data_source_ids) AS data_source_ids,
    COALESCE(( SELECT array_agg(DISTINCT codes.code) AS array_agg
           FROM ( SELECT unnest(b.data_source_codes) AS code
                UNION ALL
                 SELECT unnest(a.data_source_codes) AS code) codes), a.data_source_codes, b.data_source_codes) AS data_source_codes,
    b.legal_form_id,
    b.legal_form_code,
    b.legal_form_name,
    b.physical_address_part1,
    b.physical_address_part2,
    b.physical_address_part3,
    b.physical_postcode,
    b.physical_postplace,
    b.physical_region_id,
    b.physical_region_path,
    b.physical_region_code,
    b.physical_country_id,
    b.physical_country_iso_2,
    b.physical_latitude,
    b.physical_longitude,
    b.physical_altitude,
    b.domestic,
    b.postal_address_part1,
    b.postal_address_part2,
    b.postal_address_part3,
    b.postal_postcode,
    b.postal_postplace,
    b.postal_region_id,
    b.postal_region_path,
    b.postal_region_code,
    b.postal_country_id,
    b.postal_country_iso_2,
    b.postal_latitude,
    b.postal_longitude,
    b.postal_altitude,
    b.web_address,
    b.email_address,
    b.phone_number,
    b.landline,
    b.mobile_number,
    b.fax_number,
    b.unit_size_id,
    b.unit_size_code,
    b.status_id,
    b.status_code,
    b.used_for_counting,
    b.last_edit_comment,
    b.last_edit_by_user_id,
    b.last_edit_at,
    b.has_legal_unit,
    a.related_establishment_ids,
    a.excluded_establishment_ids,
    a.included_establishment_ids,
    a.related_legal_unit_ids,
    a.excluded_legal_unit_ids,
    a.included_legal_unit_ids,
    a.related_enterprise_ids,
    a.excluded_enterprise_ids,
    a.included_enterprise_ids,
    b.power_group_id,
    b.primary_legal_unit_id,
    a.stats_summary
   FROM power_group_basis b
     LEFT JOIN aggregation a ON b.power_group_id = a.power_group_id AND b.valid_from = a.valid_from AND b.valid_until = a.valid_until
  ORDER BY b.unit_type, b.unit_id, b.valid_from
;

CREATE OR REPLACE FUNCTION public.statistical_unit_enterprise_id(unit_type statistical_unit_type, unit_id integer, valid_on date DEFAULT CURRENT_DATE)
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE unit_type
         WHEN 'establishment' THEN (
            WITH selected_establishment AS (
                SELECT es.id, es.enterprise_id, es.legal_unit_id, es.valid_from, es.valid_to
                FROM public.establishment AS es
                WHERE es.id = unit_id
                  AND es.valid_from <= valid_on AND valid_on < es.valid_until
            )
            -- Either the establishment has a a direct enterprise connection
            SELECT enterprise_id FROM selected_establishment WHERE enterprise_id IS NOT NULL
            UNION ALL
            -- Or connects to an enterprise through it's legal unit.
            SELECT lu.enterprise_id
            FROM selected_establishment AS es
            JOIN public.legal_unit AS lu ON es.legal_unit_id = lu.id
            WHERE lu.valid_from <= valid_on AND valid_on < lu.valid_until
         )
         WHEN 'legal_unit' THEN (
             -- A legal_unit is always connected to an enterprise.
             SELECT lu.enterprise_id
               FROM public.legal_unit AS lu
              WHERE lu.id = unit_id
                AND lu.valid_from <= valid_on AND valid_on < lu.valid_until
         )
         WHEN 'enterprise' THEN (
            -- Handle both formal (legal unit) and informal (establishment) connections
            -- Return the enterprise ID if it matches either connection type
            SELECT DISTINCT unit_id AS enterprise_id
            FROM (
                SELECT lu.enterprise_id
                FROM public.legal_unit AS lu
                WHERE lu.enterprise_id = unit_id
                  AND lu.valid_from <= valid_on AND valid_on < lu.valid_until
                UNION ALL
                SELECT es.enterprise_id
                FROM public.establishment AS es
                WHERE es.enterprise_id = unit_id
                  AND es.valid_from <= valid_on AND valid_on < es.valid_until
            ) combined_connections
            WHERE enterprise_id IS NOT NULL
         )
         WHEN 'power_group' THEN (
            -- A power group's enterprise is the enterprise of its root legal unit (power_level = 0).
            SELECT lu.enterprise_id
            FROM public.power_group_membership AS pgm
            JOIN public.legal_unit AS lu
                ON lu.id = pgm.legal_unit_id
                AND lu.valid_from <= valid_on AND valid_on < lu.valid_until
            WHERE pgm.power_group_id = unit_id
              AND pgm.power_level = 0
              AND pgm.valid_range @> valid_on
            LIMIT 1
         )
         END
  ;
$function$
;

CREATE OR REPLACE PROCEDURE public.timeline_power_group_refresh(IN p_unit_id_ranges int4multirange DEFAULT NULL::int4multirange)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_unit_ids INT[];
BEGIN
    IF p_unit_id_ranges IS NULL THEN
        TRUNCATE public.timeline_power_group;
        INSERT INTO public.timeline_power_group SELECT * FROM public.timeline_power_group_def;
        ANALYZE public.timeline_power_group;
    ELSE
        v_unit_ids := public.int4multirange_to_array(p_unit_id_ranges);
        DELETE FROM public.timeline_power_group WHERE unit_id = ANY(v_unit_ids);

        -- Materialize power_group_membership ONCE to avoid re-evaluating the view
        -- in each LATERAL iteration (view has UNION DISTINCT + NOT EXISTS).
        IF to_regclass('pg_temp.pgm_temp') IS NOT NULL THEN DROP TABLE pgm_temp; END IF;
        CREATE TEMP TABLE pgm_temp ON COMMIT DROP AS
        SELECT power_group_id, legal_unit_id, power_level, valid_range
        FROM public.power_group_membership
        WHERE power_group_id = ANY(v_unit_ids);
        CREATE INDEX ON pgm_temp (power_group_id);

        -- Inline the timeline_power_group_def view logic but use pgm_temp
        INSERT INTO public.timeline_power_group
        WITH aggregation AS (
            SELECT
                tpg.power_group_id,
                tpg.valid_from,
                tpg.valid_until,
                array_distinct_concat(tlu.data_source_ids) AS data_source_ids,
                array_distinct_concat(tlu.data_source_codes) AS data_source_codes,
                array_distinct_concat(tlu.related_establishment_ids) AS related_establishment_ids,
                array_distinct_concat(tlu.excluded_establishment_ids) AS excluded_establishment_ids,
                array_distinct_concat(tlu.included_establishment_ids) AS included_establishment_ids,
                array_agg(DISTINCT tlu.legal_unit_id) AS related_legal_unit_ids,
                array_agg(DISTINCT tlu.legal_unit_id) FILTER (WHERE NOT tlu.used_for_counting) AS excluded_legal_unit_ids,
                array_agg(DISTINCT tlu.legal_unit_id) FILTER (WHERE tlu.used_for_counting) AS included_legal_unit_ids,
                array_agg(DISTINCT tlu.enterprise_id) AS related_enterprise_ids,
                array_agg(DISTINCT tlu.enterprise_id) FILTER (WHERE NOT tlu.used_for_counting) AS excluded_enterprise_ids,
                array_agg(DISTINCT tlu.enterprise_id) FILTER (WHERE tlu.used_for_counting) AS included_enterprise_ids,
                COALESCE(jsonb_stats_merge_agg(tlu.stats_summary) FILTER (WHERE tlu.used_for_counting), '{}'::jsonb) AS stats_summary
            FROM (
                SELECT t.unit_type, t.unit_id, t.valid_from, t.valid_until, pg.id AS power_group_id
                FROM timesegments AS t
                JOIN power_group AS pg ON t.unit_type = 'power_group'::statistical_unit_type AND t.unit_id = pg.id
                WHERE t.unit_id = ANY(v_unit_ids)
            ) AS tpg
            LEFT JOIN LATERAL (
                SELECT tlu_inner.legal_unit_id, tlu_inner.enterprise_id,
                       tlu_inner.data_source_ids, tlu_inner.data_source_codes,
                       tlu_inner.related_establishment_ids, tlu_inner.excluded_establishment_ids, tlu_inner.included_establishment_ids,
                       tlu_inner.used_for_counting, tlu_inner.stats_summary
                FROM pgm_temp AS pgm
                JOIN public.timeline_legal_unit AS tlu_inner
                    ON tlu_inner.legal_unit_id = pgm.legal_unit_id
                    AND from_until_overlaps(tpg.valid_from, tpg.valid_until, tlu_inner.valid_from, tlu_inner.valid_until)
                WHERE pgm.power_group_id = tpg.power_group_id
                  AND pgm.valid_range && daterange(tpg.valid_from, tpg.valid_until)
            ) AS tlu ON true
            GROUP BY tpg.power_group_id, tpg.valid_from, tpg.valid_until
        ),
        power_group_basis AS (
            SELECT
                tpg.unit_type, tpg.unit_id, tpg.valid_from, tpg.valid_until,
                tpg.power_group_id,
                COALESCE(NULLIF(tpg.short_name::text, ''::text), pgplu.name::text) AS name,
                pgplu.birth_date, pgplu.death_date,
                pgplu.primary_activity_category_id, pgplu.primary_activity_category_path, pgplu.primary_activity_category_code,
                pgplu.secondary_activity_category_id, pgplu.secondary_activity_category_path, pgplu.secondary_activity_category_code,
                pgplu.sector_id, pgplu.sector_path, pgplu.sector_code, pgplu.sector_name,
                pgplu.data_source_ids, pgplu.data_source_codes,
                pgplu.legal_form_id, pgplu.legal_form_code, pgplu.legal_form_name,
                pgplu.physical_address_part1, pgplu.physical_address_part2, pgplu.physical_address_part3,
                pgplu.physical_postcode, pgplu.physical_postplace,
                pgplu.physical_region_id, pgplu.physical_region_path, pgplu.physical_region_code,
                pgplu.physical_country_id, pgplu.physical_country_iso_2,
                pgplu.physical_latitude, pgplu.physical_longitude, pgplu.physical_altitude,
                pgplu.domestic,
                pgplu.postal_address_part1, pgplu.postal_address_part2, pgplu.postal_address_part3,
                pgplu.postal_postcode, pgplu.postal_postplace,
                pgplu.postal_region_id, pgplu.postal_region_path, pgplu.postal_region_code,
                pgplu.postal_country_id, pgplu.postal_country_iso_2,
                pgplu.postal_latitude, pgplu.postal_longitude, pgplu.postal_altitude,
                pgplu.web_address, pgplu.email_address, pgplu.phone_number,
                pgplu.landline, pgplu.mobile_number, pgplu.fax_number,
                pgplu.unit_size_id, pgplu.unit_size_code,
                pgplu.status_id, pgplu.status_code,
                TRUE AS used_for_counting,
                last_edit.edit_comment AS last_edit_comment,
                last_edit.edit_by_user_id AS last_edit_by_user_id,
                last_edit.edit_at AS last_edit_at,
                CASE WHEN pgplu.legal_unit_id IS NOT NULL THEN TRUE ELSE FALSE END AS has_legal_unit,
                pgplu.legal_unit_id AS primary_legal_unit_id
            FROM (
                SELECT t.unit_type, t.unit_id, t.valid_from, t.valid_until,
                       pg.id AS power_group_id, pg.short_name, pg.edit_comment, pg.edit_by_user_id, pg.edit_at
                FROM timesegments AS t
                JOIN power_group AS pg ON t.unit_type = 'power_group'::statistical_unit_type AND t.unit_id = pg.id
                WHERE t.unit_id = ANY(v_unit_ids)
            ) AS tpg
            LEFT JOIN LATERAL (
                SELECT tlu_p.legal_unit_id, tlu_p.enterprise_id,
                       tlu_p.name, tlu_p.birth_date, tlu_p.death_date,
                       tlu_p.primary_activity_category_id, tlu_p.primary_activity_category_path, tlu_p.primary_activity_category_code,
                       tlu_p.secondary_activity_category_id, tlu_p.secondary_activity_category_path, tlu_p.secondary_activity_category_code,
                       tlu_p.sector_id, tlu_p.sector_path, tlu_p.sector_code, tlu_p.sector_name,
                       tlu_p.data_source_ids, tlu_p.data_source_codes,
                       tlu_p.legal_form_id, tlu_p.legal_form_code, tlu_p.legal_form_name,
                       tlu_p.physical_address_part1, tlu_p.physical_address_part2, tlu_p.physical_address_part3,
                       tlu_p.physical_postcode, tlu_p.physical_postplace,
                       tlu_p.physical_region_id, tlu_p.physical_region_path, tlu_p.physical_region_code,
                       tlu_p.physical_country_id, tlu_p.physical_country_iso_2,
                       tlu_p.physical_latitude, tlu_p.physical_longitude, tlu_p.physical_altitude,
                       tlu_p.domestic,
                       tlu_p.postal_address_part1, tlu_p.postal_address_part2, tlu_p.postal_address_part3,
                       tlu_p.postal_postcode, tlu_p.postal_postplace,
                       tlu_p.postal_region_id, tlu_p.postal_region_path, tlu_p.postal_region_code,
                       tlu_p.postal_country_id, tlu_p.postal_country_iso_2,
                       tlu_p.postal_latitude, tlu_p.postal_longitude, tlu_p.postal_altitude,
                       tlu_p.web_address, tlu_p.email_address, tlu_p.phone_number,
                       tlu_p.landline, tlu_p.mobile_number, tlu_p.fax_number,
                       tlu_p.unit_size_id, tlu_p.unit_size_code,
                       tlu_p.status_id, tlu_p.status_code,
                       tlu_p.last_edit_comment, tlu_p.last_edit_by_user_id, tlu_p.last_edit_at
                FROM pgm_temp AS pgm
                JOIN public.timeline_legal_unit AS tlu_p
                    ON tlu_p.legal_unit_id = pgm.legal_unit_id
                    AND from_until_overlaps(tpg.valid_from, tpg.valid_until, tlu_p.valid_from, tlu_p.valid_until)
                WHERE pgm.power_group_id = tpg.power_group_id
                  AND pgm.power_level = 0
                  AND pgm.valid_range && daterange(tpg.valid_from, tpg.valid_until)
                ORDER BY tlu_p.valid_from DESC, tlu_p.legal_unit_id DESC
                LIMIT 1
            ) AS pgplu ON true
            LEFT JOIN LATERAL (
                SELECT all_edits.edit_comment, all_edits.edit_by_user_id, all_edits.edit_at
                FROM (VALUES
                    (tpg.edit_comment, tpg.edit_by_user_id, tpg.edit_at),
                    (pgplu.last_edit_comment, pgplu.last_edit_by_user_id, pgplu.last_edit_at)
                ) AS all_edits(edit_comment, edit_by_user_id, edit_at)
                WHERE all_edits.edit_at IS NOT NULL
                ORDER BY all_edits.edit_at DESC
                LIMIT 1
            ) AS last_edit ON true
        )
        SELECT
            b.unit_type, b.unit_id, b.valid_from,
            (b.valid_until - '1 day'::interval)::date AS valid_to,
            b.valid_until,
            b.name, b.birth_date, b.death_date,
            to_tsvector('simple'::regconfig, COALESCE(b.name, '')) AS search,
            b.primary_activity_category_id, b.primary_activity_category_path, b.primary_activity_category_code,
            b.secondary_activity_category_id, b.secondary_activity_category_path, b.secondary_activity_category_code,
            NULLIF(array_remove(ARRAY[b.primary_activity_category_path, b.secondary_activity_category_path], NULL::ltree), '{}'::ltree[]) AS activity_category_paths,
            b.sector_id, b.sector_path, b.sector_code, b.sector_name,
            COALESCE(
                ( SELECT array_agg(DISTINCT ids.id) FROM (SELECT unnest(b.data_source_ids) AS id UNION SELECT unnest(a.data_source_ids) AS id) ids ),
                a.data_source_ids, b.data_source_ids
            ) AS data_source_ids,
            COALESCE(
                ( SELECT array_agg(DISTINCT codes.code) FROM (SELECT unnest(b.data_source_codes) AS code UNION ALL SELECT unnest(a.data_source_codes) AS code) codes ),
                a.data_source_codes, b.data_source_codes
            ) AS data_source_codes,
            b.legal_form_id, b.legal_form_code, b.legal_form_name,
            b.physical_address_part1, b.physical_address_part2, b.physical_address_part3, b.physical_postcode, b.physical_postplace,
            b.physical_region_id, b.physical_region_path, b.physical_region_code, b.physical_country_id, b.physical_country_iso_2,
            b.physical_latitude, b.physical_longitude, b.physical_altitude, b.domestic,
            b.postal_address_part1, b.postal_address_part2, b.postal_address_part3, b.postal_postcode, b.postal_postplace,
            b.postal_region_id, b.postal_region_path, b.postal_region_code, b.postal_country_id, b.postal_country_iso_2,
            b.postal_latitude, b.postal_longitude, b.postal_altitude,
            b.web_address, b.email_address, b.phone_number, b.landline, b.mobile_number, b.fax_number,
            b.unit_size_id, b.unit_size_code, b.status_id, b.status_code, b.used_for_counting,
            b.last_edit_comment, b.last_edit_by_user_id, b.last_edit_at, b.has_legal_unit,
            a.related_establishment_ids, a.excluded_establishment_ids, a.included_establishment_ids,
            a.related_legal_unit_ids, a.excluded_legal_unit_ids, a.included_legal_unit_ids,
            a.related_enterprise_ids, a.excluded_enterprise_ids, a.included_enterprise_ids,
            b.power_group_id, b.primary_legal_unit_id,
            a.stats_summary
        FROM power_group_basis AS b
        LEFT JOIN aggregation AS a ON b.power_group_id = a.power_group_id
            AND b.valid_from = a.valid_from AND b.valid_until = a.valid_until
        ORDER BY b.unit_type, b.unit_id, b.valid_from;
    END IF;
END;
$procedure$
;

COMMIT;
