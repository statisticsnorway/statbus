BEGIN;

-- Remove the ensure_collect trigger
DROP TRIGGER IF EXISTS b_legal_relationship_ensure_collect ON public.legal_relationship;

-- Remove power_group_link step from definitions (inverse of Fix 2)
DELETE FROM public.import_definition_step
WHERE step_id = (SELECT id FROM public.import_step WHERE code = 'power_group_link');

-- Restore process_power_group_link without the ensure_collect disable/enable (inverse of Fix 3)
CREATE OR REPLACE PROCEDURE import.process_power_group_link(IN p_job_id integer, IN p_batch_seq integer, IN p_step_code text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'import', 'worker', 'pg_temp'
AS $process_power_group_link$
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
    _current_user_id integer;
BEGIN
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;

    SELECT * INTO v_definition
    FROM jsonb_populate_record(NULL::public.import_definition, v_job.definition_snapshot->'import_definition');

    -- Only run for legal_relationship mode
    IF v_definition.mode != 'legal_relationship' THEN
        RAISE DEBUG '[Job %] process_power_group_link: Skipping, mode is %', p_job_id, v_definition.mode;
        RETURN;
    END IF;

    RAISE DEBUG '[Job %] process_power_group_link: Creating/updating power groups (holistic)', p_job_id;

    -- Disable log_base_change triggers to prevent re-enqueue loop
    -- (derived_power_group_id UPDATEs should be silent — only actual relationship changes trigger derive)
    ALTER TABLE public.legal_relationship DISABLE TRIGGER a_legal_relationship_log_insert;
    ALTER TABLE public.legal_relationship DISABLE TRIGGER a_legal_relationship_log_update;
    ALTER TABLE public.legal_relationship DISABLE TRIGGER a_legal_relationship_log_delete;

    -- Find current user for power_group creation
    SELECT id INTO _current_user_id FROM auth.user WHERE email = session_user OR session_user = 'postgres';
    IF _current_user_id IS NULL THEN
        SELECT id INTO _current_user_id FROM auth.user WHERE role_id = (SELECT id FROM auth.role WHERE name = 'super_user') LIMIT 1;
    END IF;
    IF _current_user_id IS NULL THEN
        RAISE EXCEPTION 'No user found for power group creation';
    END IF;

    -- Use legal_relationship_cluster view (reads derived_power_group_id from LR)
    FOR _cluster IN SELECT DISTINCT power_group_id FROM public.legal_relationship_cluster
    LOOP
        -- Find existing power_group for this cluster
        SELECT pg.* INTO _power_group
        FROM public.power_group AS pg
        JOIN public.legal_relationship AS lr ON lr.derived_power_group_id = pg.id
        JOIN public.legal_relationship_cluster AS lrc ON lrc.legal_relationship_id = lr.id
        WHERE lrc.power_group_id = _cluster.power_group_id
        LIMIT 1;

        IF NOT FOUND THEN
            INSERT INTO public.power_group (edit_by_user_id) VALUES (_current_user_id) RETURNING * INTO _power_group;
            _created_count := _created_count + 1;
            RAISE DEBUG '[Job %] process_power_group_link: Created power_group % for cluster PG %',
                p_job_id, _power_group.ident, _cluster.power_group_id;
        ELSE
            _updated_count := _updated_count + 1;
        END IF;

        -- Set derived_power_group_id on all legal_relationships in this cluster
        UPDATE public.legal_relationship AS lr
        SET derived_power_group_id = _power_group.id
        FROM public.legal_relationship_cluster AS lrc
        WHERE lr.id = lrc.legal_relationship_id
          AND lrc.power_group_id = _cluster.power_group_id
          AND (lr.derived_power_group_id IS DISTINCT FROM _power_group.id);
        GET DIAGNOSTICS _row_count = ROW_COUNT;
        _linked_count := _linked_count + _row_count;
    END LOOP;

    -- Handle cluster merges (multiple power_groups pointing to same cluster)
    WITH cluster_sizes AS (
        SELECT lr.derived_power_group_id, COUNT(*) AS rel_count
        FROM public.legal_relationship AS lr WHERE lr.derived_power_group_id IS NOT NULL GROUP BY lr.derived_power_group_id
    ),
    merge_candidates AS (
        SELECT DISTINCT lrc.power_group_id, lr.derived_power_group_id AS current_pg_id, cs.rel_count
        FROM public.legal_relationship_cluster AS lrc
        JOIN public.legal_relationship AS lr ON lr.id = lrc.legal_relationship_id
        JOIN cluster_sizes AS cs ON cs.derived_power_group_id = lr.derived_power_group_id
        WHERE lr.derived_power_group_id IS NOT NULL
    ),
    clusters_with_multiple_pgs AS (
        SELECT power_group_id, array_agg(current_pg_id ORDER BY rel_count DESC, current_pg_id) AS pg_ids
        FROM merge_candidates GROUP BY power_group_id HAVING COUNT(DISTINCT current_pg_id) > 1
    )
    UPDATE public.legal_relationship AS lr
    SET derived_power_group_id = cwmp.pg_ids[1]
    FROM public.legal_relationship_cluster AS lrc
    JOIN clusters_with_multiple_pgs AS cwmp ON cwmp.power_group_id = lrc.power_group_id
    WHERE lr.id = lrc.legal_relationship_id AND lr.derived_power_group_id != cwmp.pg_ids[1];
    GET DIAGNOSTICS _row_count = ROW_COUNT;
    IF _row_count > 0 THEN
        RAISE DEBUG '[Job %] process_power_group_link: Merged % relationships into surviving power groups', p_job_id, _row_count;
    END IF;

    -- Clear derived_power_group_id from non-primary-influencer relationships
    UPDATE public.legal_relationship AS lr SET derived_power_group_id = NULL
    WHERE lr.derived_power_group_id IS NOT NULL AND lr.primary_influencer_only IS NOT TRUE;
    GET DIAGNOSTICS _row_count = ROW_COUNT;
    IF _row_count > 0 THEN
        RAISE DEBUG '[Job %] process_power_group_link: Cleared power_group from % non-primary-influencer relationships', p_job_id, _row_count;
    END IF;

    RAISE DEBUG '[Job %] process_power_group_link: Completed: created=%, updated=%, linked=%',
        p_job_id, _created_count, _updated_count, _linked_count;

    -- ================================================================
    -- Populate power_root for cycle/multi PGs via temporal_merge
    -- ================================================================

    -- Disable power_root trigger to prevent enqueue loop during temporal_merge
    ALTER TABLE public.power_root DISABLE TRIGGER power_root_derive_trigger;

    IF to_regclass('pg_temp._power_root_source') IS NOT NULL THEN
        DROP TABLE _power_root_source;
    END IF;
    CREATE TEMP TABLE _power_root_source (
        row_id integer GENERATED BY DEFAULT AS IDENTITY,
        power_group_id integer,
        derived_root_legal_unit_id integer,
        derived_root_status public.power_group_root_status,
        custom_root_legal_unit_id integer,  -- carried forward from existing rows
        valid_range daterange,
        edit_by_user_id integer
    ) ON COMMIT DROP;

    INSERT INTO _power_root_source (power_group_id, derived_root_legal_unit_id, derived_root_status, custom_root_legal_unit_id, valid_range, edit_by_user_id)
    SELECT DISTINCT ON (pgm.power_group_id, lower(pgm.valid_range))
        pgm.power_group_id,
        pgm_root.legal_unit_id AS derived_root_legal_unit_id,
        CASE
            -- Multiple distinct roots for same PG in overlapping time → 'multi'
            WHEN (SELECT COUNT(DISTINCT pgm2.legal_unit_id)
                  FROM public.power_group_membership AS pgm2
                  WHERE pgm2.power_group_id = pgm.power_group_id
                    AND pgm2.valid_range && pgm.valid_range
                    AND pgm2.power_level = 1) > 1
            THEN 'multi'::public.power_group_root_status
            -- Root came from Phase 2 (no natural root period for this LU) → 'cycle'
            WHEN NOT EXISTS (
                SELECT 1 FROM public.legal_unit AS lu
                WHERE lu.id = pgm_root.legal_unit_id
                  AND EXISTS (
                      SELECT 1 FROM public.legal_relationship AS lr_child
                      WHERE lr_child.influencing_id = lu.id
                        AND lr_child.primary_influencer_only IS TRUE
                        AND lr_child.valid_range && pgm.valid_range)
                  AND NOT EXISTS (
                      SELECT 1 FROM public.legal_relationship AS lr_parent
                      WHERE lr_parent.influenced_id = lu.id
                        AND lr_parent.primary_influencer_only IS TRUE
                        AND lr_parent.valid_range && pgm.valid_range))
            THEN 'cycle'::public.power_group_root_status
            ELSE NULL  -- single-root: no power_root entry (sparse)
        END AS derived_root_status,
        -- Carry forward existing custom_root so period splits preserve NSO overrides
        existing_pr.custom_root_legal_unit_id,
        pgm.valid_range,
        _current_user_id
    FROM public.power_group_membership AS pgm
    JOIN public.power_group_membership AS pgm_root
        ON pgm_root.power_group_id = pgm.power_group_id
        AND pgm_root.power_level = 1
        AND pgm_root.valid_range && pgm.valid_range
    LEFT JOIN public.power_root AS existing_pr
        ON existing_pr.power_group_id = pgm.power_group_id
        AND existing_pr.valid_range && pgm.valid_range
    ORDER BY pgm.power_group_id, lower(pgm.valid_range);

    -- Remove single-root entries (sparse: only cycle/multi get rows)
    DELETE FROM _power_root_source WHERE derived_root_status IS NULL;

    -- Only run temporal_merge if there are source rows or existing power_root rows to clean up
    IF EXISTS (SELECT 1 FROM _power_root_source) OR EXISTS (SELECT 1 FROM public.power_root) THEN
        -- temporal_merge handles: new PGs → INSERT, shifted boundaries → split/merge,
        -- PGs that became single-root → removed (no source row + MERGE_ENTITY_REPLACE)
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

    ALTER TABLE public.power_root ENABLE TRIGGER power_root_derive_trigger;

    -- Re-enable triggers
    ALTER TABLE public.legal_relationship ENABLE TRIGGER a_legal_relationship_log_insert;
    ALTER TABLE public.legal_relationship ENABLE TRIGGER a_legal_relationship_log_update;
    ALTER TABLE public.legal_relationship ENABLE TRIGGER a_legal_relationship_log_delete;
END;
$process_power_group_link$;

END;
