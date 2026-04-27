-- Down migration 20260427124351: restore ensure_collect_changes triggers + revert loggers
--
-- Reverses task #32: rebuilds worker.ensure_collect_changes() function,
-- re-attaches the 14 unconditional triggers, and reverts log_base_change /
-- log_region_change to their pre-fold form (no inline scheduling).
BEGIN;

-- ============================================================================
-- Step 1: Revert log_base_change to the pre-fold form (no scheduling).
-- ============================================================================

CREATE OR REPLACE FUNCTION worker.log_base_change()
RETURNS trigger
LANGUAGE plpgsql
AS $log_base_change$
DECLARE
    v_columns TEXT;
    v_has_valid_range BOOLEAN;
    v_where_clause TEXT := '';
    v_source TEXT;
    v_est_ids int4multirange;
    v_lu_ids int4multirange;
    v_ent_ids int4multirange;
    v_pg_ids int4multirange;
    v_valid_range datemultirange;
BEGIN
    CASE TG_TABLE_NAME
        WHEN 'establishment' THEN
            v_columns := 'id AS est_id, legal_unit_id AS lu_id, enterprise_id AS ent_id, NULL::INT AS pg_id';
            v_has_valid_range := TRUE;
        WHEN 'legal_unit' THEN
            v_columns := 'NULL::INT AS est_id, id AS lu_id, enterprise_id AS ent_id, NULL::INT AS pg_id';
            v_has_valid_range := TRUE;
        WHEN 'enterprise' THEN
            v_columns := 'NULL::INT AS est_id, NULL::INT AS lu_id, id AS ent_id, NULL::INT AS pg_id';
            v_has_valid_range := FALSE;
        WHEN 'activity', 'location', 'contact', 'stat_for_unit' THEN
            v_columns := 'establishment_id AS est_id, legal_unit_id AS lu_id, NULL::INT AS ent_id, NULL::INT AS pg_id';
            v_has_valid_range := TRUE;
        WHEN 'person_for_unit' THEN
            v_columns := 'establishment_id AS est_id, legal_unit_id AS lu_id, NULL::INT AS ent_id, NULL::INT AS pg_id';
            v_has_valid_range := TRUE;
        WHEN 'external_ident' THEN
            v_columns := 'establishment_id AS est_id, legal_unit_id AS lu_id, enterprise_id AS ent_id, NULL::INT AS pg_id';
            v_has_valid_range := FALSE;
        WHEN 'tag_for_unit' THEN
            v_columns := 'establishment_id AS est_id, legal_unit_id AS lu_id, enterprise_id AS ent_id, power_group_id AS pg_id';
            v_has_valid_range := FALSE;
        WHEN 'legal_relationship' THEN
            v_columns := 'NULL::INT AS est_id, NULL::INT AS lu_id, NULL::INT AS ent_id, derived_power_group_id AS pg_id';
            v_has_valid_range := TRUE;

            v_where_clause := ' WHERE derived_power_group_id IS NOT NULL';
        WHEN 'power_group' THEN
            v_columns := 'NULL::INT AS est_id, NULL::INT AS lu_id, NULL::INT AS ent_id, id AS pg_id';
            v_has_valid_range := FALSE;
        WHEN 'power_root' THEN
            v_columns := 'NULL::INT AS est_id, NULL::INT AS lu_id, NULL::INT AS ent_id, power_group_id AS pg_id';
            v_has_valid_range := TRUE;
        ELSE
            RAISE EXCEPTION 'log_base_change: unsupported table %', TG_TABLE_NAME;
    END CASE;

    IF v_has_valid_range THEN
        v_columns := v_columns || ', valid_range';
    ELSE
        v_columns := v_columns || ', NULL::daterange AS valid_range';
    END IF;

    CASE TG_OP
        WHEN 'INSERT' THEN v_source := format('SELECT %s FROM new_rows%s', v_columns, v_where_clause);
        WHEN 'DELETE' THEN v_source := format('SELECT %s FROM old_rows%s', v_columns, v_where_clause);
        WHEN 'UPDATE' THEN v_source := format('SELECT %s FROM old_rows%s UNION ALL SELECT %s FROM new_rows%s', v_columns, v_where_clause, v_columns, v_where_clause);
        ELSE RAISE EXCEPTION 'log_base_change: unsupported operation %', TG_OP;
    END CASE;

    EXECUTE format(
        'SELECT COALESCE(range_agg(int4range(est_id, est_id, %1$L)) FILTER (WHERE est_id IS NOT NULL), %2$L::int4multirange),
                COALESCE(range_agg(int4range(lu_id, lu_id, %1$L)) FILTER (WHERE lu_id IS NOT NULL), %2$L::int4multirange),
                COALESCE(range_agg(int4range(ent_id, ent_id, %1$L)) FILTER (WHERE ent_id IS NOT NULL), %2$L::int4multirange),
                COALESCE(range_agg(int4range(pg_id, pg_id, %1$L)) FILTER (WHERE pg_id IS NOT NULL), %2$L::int4multirange),
                COALESCE(range_agg(valid_range) FILTER (WHERE valid_range IS NOT NULL), %3$L::datemultirange)
         FROM (%s) AS mapped',
        '[]', '{}', '{}', v_source
    ) INTO v_est_ids, v_lu_ids, v_ent_ids, v_pg_ids, v_valid_range;

    IF v_est_ids != '{}'::int4multirange
       OR v_lu_ids != '{}'::int4multirange
       OR v_ent_ids != '{}'::int4multirange
       OR v_pg_ids != '{}'::int4multirange THEN
        INSERT INTO worker.base_change_log (establishment_ids, legal_unit_ids, enterprise_ids, power_group_ids, valid_ranges)
        VALUES (v_est_ids, v_lu_ids, v_ent_ids, v_pg_ids, v_valid_range);
    END IF;

    RETURN NULL;
END;
$log_base_change$;

-- ============================================================================
-- Step 2: Revert log_region_change to the pre-fold form (no scheduling).
-- ============================================================================

CREATE OR REPLACE FUNCTION worker.log_region_change()
RETURNS trigger
LANGUAGE plpgsql
AS $log_region_change$
DECLARE
    v_est_ids int4multirange;
    v_lu_ids int4multirange;
    v_valid_ranges datemultirange;
    v_source TEXT;
BEGIN
    CASE TG_OP
        WHEN 'INSERT' THEN v_source := 'new_rows';
        WHEN 'DELETE' THEN v_source := 'old_rows';
        WHEN 'UPDATE' THEN v_source := 'old_rows UNION ALL SELECT * FROM new_rows';
        ELSE RAISE EXCEPTION 'log_region_change: unsupported operation %', TG_OP;
    END CASE;

    EXECUTE format(
        $SQL$
        SELECT
            COALESCE(range_agg(int4range(l.establishment_id, l.establishment_id, '[]')) FILTER (WHERE l.establishment_id IS NOT NULL), '{}'::int4multirange),
            COALESCE(range_agg(int4range(l.legal_unit_id, l.legal_unit_id, '[]')) FILTER (WHERE l.legal_unit_id IS NOT NULL), '{}'::int4multirange),
            COALESCE(range_agg(l.valid_range) FILTER (WHERE l.valid_range IS NOT NULL), '{}'::datemultirange)
        FROM (%s) AS affected_regions
        JOIN public.location AS l ON l.region_id = affected_regions.id
        $SQL$,
        format('SELECT * FROM %s', v_source)
    ) INTO v_est_ids, v_lu_ids, v_valid_ranges;

    IF v_est_ids != '{}'::int4multirange
       OR v_lu_ids != '{}'::int4multirange THEN
        INSERT INTO worker.base_change_log (establishment_ids, legal_unit_ids, enterprise_ids, power_group_ids, valid_ranges)
        VALUES (v_est_ids, v_lu_ids, '{}'::int4multirange, '{}'::int4multirange, v_valid_ranges);
    END IF;

    RETURN NULL;
END;
$log_region_change$;

-- ============================================================================
-- Step 3: Restore worker.ensure_collect_changes() function.
-- ============================================================================

CREATE OR REPLACE FUNCTION worker.ensure_collect_changes()
RETURNS trigger
LANGUAGE plpgsql
AS $ensure_collect_changes$
BEGIN
    -- Set LOGGED flag for crash recovery (no-op if already TRUE)
    UPDATE worker.base_change_log_has_pending
    SET has_pending = TRUE WHERE has_pending = FALSE;

    -- Enqueue collect_changes task (DO NOTHING = no row lock!)
    INSERT INTO worker.tasks (command, payload)
    VALUES ('collect_changes', '{"command":"collect_changes"}'::jsonb)
    ON CONFLICT (command)
    WHERE command = 'collect_changes' AND state = 'pending'::worker.task_state
    DO NOTHING;

    -- pg_notify fires even when ON CONFLICT DO NOTHING matches (PG provides
    -- no way to detect this). Cost is negligible: worker wakes, finds nothing, sleeps.
    PERFORM pg_notify('worker_tasks', 'analytics');
    RETURN NULL;
END;
$ensure_collect_changes$;

-- ============================================================================
-- Step 4: Re-attach the 14 unconditional ensure_collect_changes triggers.
-- ============================================================================

CREATE TRIGGER b_activity_ensure_collect
AFTER INSERT OR DELETE OR UPDATE ON public.activity
FOR EACH STATEMENT EXECUTE FUNCTION worker.ensure_collect_changes();

CREATE TRIGGER b_contact_ensure_collect
AFTER INSERT OR DELETE OR UPDATE ON public.contact
FOR EACH STATEMENT EXECUTE FUNCTION worker.ensure_collect_changes();

CREATE TRIGGER b_enterprise_ensure_collect
AFTER INSERT OR DELETE OR UPDATE ON public.enterprise
FOR EACH STATEMENT EXECUTE FUNCTION worker.ensure_collect_changes();

CREATE TRIGGER b_establishment_ensure_collect
AFTER INSERT OR DELETE OR UPDATE ON public.establishment
FOR EACH STATEMENT EXECUTE FUNCTION worker.ensure_collect_changes();

CREATE TRIGGER b_external_ident_ensure_collect
AFTER INSERT OR DELETE OR UPDATE ON public.external_ident
FOR EACH STATEMENT EXECUTE FUNCTION worker.ensure_collect_changes();

CREATE TRIGGER b_legal_relationship_ensure_collect_delete
AFTER DELETE ON public.legal_relationship
REFERENCING OLD TABLE AS old_rows
FOR EACH STATEMENT EXECUTE FUNCTION worker.ensure_collect_changes();

CREATE TRIGGER b_legal_unit_ensure_collect
AFTER INSERT OR DELETE OR UPDATE ON public.legal_unit
FOR EACH STATEMENT EXECUTE FUNCTION worker.ensure_collect_changes();

CREATE TRIGGER b_location_ensure_collect
AFTER INSERT OR DELETE OR UPDATE ON public.location
FOR EACH STATEMENT EXECUTE FUNCTION worker.ensure_collect_changes();

CREATE TRIGGER b_person_for_unit_ensure_collect
AFTER INSERT OR DELETE OR UPDATE ON public.person_for_unit
FOR EACH STATEMENT EXECUTE FUNCTION worker.ensure_collect_changes();

CREATE TRIGGER b_power_group_ensure_collect
AFTER INSERT OR DELETE OR UPDATE ON public.power_group
FOR EACH STATEMENT EXECUTE FUNCTION worker.ensure_collect_changes();

CREATE TRIGGER b_power_root_ensure_collect_delete
AFTER DELETE ON public.power_root
REFERENCING OLD TABLE AS old_rows
FOR EACH STATEMENT EXECUTE FUNCTION worker.ensure_collect_changes();

CREATE TRIGGER b_region_ensure_collect
AFTER INSERT OR DELETE OR UPDATE ON public.region
FOR EACH STATEMENT EXECUTE FUNCTION worker.ensure_collect_changes();

CREATE TRIGGER b_stat_for_unit_ensure_collect
AFTER INSERT OR DELETE OR UPDATE ON public.stat_for_unit
FOR EACH STATEMENT EXECUTE FUNCTION worker.ensure_collect_changes();

CREATE TRIGGER b_tag_for_unit_ensure_collect
AFTER INSERT OR DELETE OR UPDATE ON public.tag_for_unit
FOR EACH STATEMENT EXECUTE FUNCTION worker.ensure_collect_changes();

END;
