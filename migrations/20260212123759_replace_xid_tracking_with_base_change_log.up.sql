-- Migration 20260212123759: replace_xid_tracking_with_base_change_log
BEGIN;

-- =============================================================================
-- Replace xid-based change tracking with direct ID capture via UNLOGGED
-- base_change_log table.
--
-- Problem: enqueue_check_table uses ON CONFLICT DO UPDATE inside import
-- transactions, acquiring row locks on worker.tasks. The analytics queue uses
-- FOR UPDATE SKIP LOCKED, skipping locked rows and blocking analytics for
-- 12-20s per import batch, causing 5 pipeline rounds instead of expected 2.
--
-- Solution: Statement-level REFERENCING triggers write pre-aggregated
-- multiranges to an UNLOGGED accumulator table. A separate collect_changes
-- task atomically drains the table and enqueues derive_statistical_unit.
-- Task creation uses ON CONFLICT DO NOTHING (no row locks!).
-- =============================================================================

-- Phase 1: Drop old triggers
CALL worker.teardown();

-- Phase 2: Remove old commands from registry
DELETE FROM worker.command_registry WHERE command IN ('check_table', 'deleted_row');

-- Phase 3: Drop old functions and tables
DROP FUNCTION IF EXISTS worker.enqueue_check_table(text, bigint);
DROP PROCEDURE IF EXISTS worker.command_check_table(jsonb);
DROP FUNCTION IF EXISTS worker.enqueue_deleted_row(text, integer, integer, integer, date, date);
DROP PROCEDURE IF EXISTS worker.command_deleted_row(jsonb);
DROP FUNCTION IF EXISTS worker.notify_worker_about_statement_changes();
DROP FUNCTION IF EXISTS worker.notify_worker_about_row_changes();
DROP FUNCTION IF EXISTS worker.notify_worker_about_deletes();

-- Phase 4: Drop old dedup indexes
DROP INDEX IF EXISTS worker.idx_tasks_check_table_dedup;
DROP INDEX IF EXISTS worker.idx_tasks_deleted_row_dedup;

-- Phase 5: Drop old setup helpers
DROP PROCEDURE IF EXISTS worker.setup_statement_triggers(text[]);
DROP PROCEDURE IF EXISTS worker.setup_row_level_triggers();
DROP PROCEDURE IF EXISTS worker.setup_delete_triggers(text[]);

-- Phase 6: Drop old tracking table
DROP TABLE IF EXISTS worker.last_processed;

-- =============================================================================
-- Create new infrastructure
-- =============================================================================

-- Phase 7: UNLOGGED accumulator table
-- No indexes. INSERT-only workload, drained via unqualified DELETE.
-- UNLOGGED = no WAL overhead. Survives normal crashes, lost on PG unclean shutdown.
-- Pre-aggregated: 1 row per DML statement (not per row).
CREATE UNLOGGED TABLE worker.base_change_log (
    establishment_ids int4multirange NOT NULL DEFAULT '{}'::int4multirange,
    legal_unit_ids    int4multirange NOT NULL DEFAULT '{}'::int4multirange,
    enterprise_ids    int4multirange NOT NULL DEFAULT '{}'::int4multirange,
    edited_by_valid_range datemultirange NOT NULL DEFAULT '{}'::datemultirange
);

-- Phase 8: LOGGED crash recovery flag
-- Survives PG unclean shutdown. Enables detection of UNLOGGED table truncation.
CREATE TABLE worker.base_change_log_has_pending (
    has_pending BOOLEAN NOT NULL DEFAULT FALSE
);
INSERT INTO worker.base_change_log_has_pending VALUES (FALSE);

-- Phase 9: GRANTs
-- Triggers run as the importing user (authenticated role)
GRANT INSERT ON worker.base_change_log TO authenticated;
GRANT SELECT, DELETE ON worker.base_change_log TO authenticated;
GRANT SELECT, UPDATE ON worker.base_change_log_has_pending TO authenticated;

-- Phase 10: Statement trigger function with REFERENCING
-- Single function for all 8 tables, 3 triggers per table (INSERT/UPDATE/DELETE).
-- Uses transition tables to pre-aggregate into multiranges.
CREATE FUNCTION worker.log_base_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $log_base_change$
DECLARE
    v_columns TEXT;
    v_has_valid_range BOOLEAN;
    v_source TEXT;
    v_est_ids int4multirange;
    v_lu_ids int4multirange;
    v_ent_ids int4multirange;
    v_valid_range datemultirange;
BEGIN
    -- Column mapping based on table name
    CASE TG_TABLE_NAME
        WHEN 'establishment' THEN
            v_columns := 'id AS est_id, legal_unit_id AS lu_id, enterprise_id AS ent_id';
            v_has_valid_range := TRUE;
        WHEN 'legal_unit' THEN
            v_columns := 'NULL::INT AS est_id, id AS lu_id, enterprise_id AS ent_id';
            v_has_valid_range := TRUE;
        WHEN 'enterprise' THEN
            v_columns := 'NULL::INT AS est_id, NULL::INT AS lu_id, id AS ent_id';
            v_has_valid_range := FALSE;
        WHEN 'activity', 'location', 'contact', 'stat_for_unit' THEN
            v_columns := 'establishment_id AS est_id, legal_unit_id AS lu_id, NULL::INT AS ent_id';
            v_has_valid_range := TRUE;
        WHEN 'external_ident' THEN
            v_columns := 'establishment_id AS est_id, legal_unit_id AS lu_id, enterprise_id AS ent_id';
            v_has_valid_range := FALSE;
        ELSE
            RAISE EXCEPTION 'log_base_change: unsupported table %', TG_TABLE_NAME;
    END CASE;

    -- Add valid_range to column list
    IF v_has_valid_range THEN
        v_columns := v_columns || ', valid_range';
    ELSE
        v_columns := v_columns || ', NULL::daterange AS valid_range';
    END IF;

    -- Build source query based on operation
    CASE TG_OP
        WHEN 'INSERT' THEN
            v_source := format('SELECT %s FROM new_rows', v_columns);
        WHEN 'DELETE' THEN
            v_source := format('SELECT %s FROM old_rows', v_columns);
        WHEN 'UPDATE' THEN
            v_source := format('SELECT %s FROM old_rows UNION ALL SELECT %s FROM new_rows',
                               v_columns, v_columns);
        ELSE
            RAISE EXCEPTION 'log_base_change: unsupported operation %', TG_OP;
    END CASE;

    -- Aggregate into multiranges
    -- CRITICAL: Use FILTER (WHERE col IS NOT NULL) to avoid int4range(NULL,NULL,'[]')
    -- which produces unbounded range (,) meaning ALL integers, not empty.
    EXECUTE format(
        'SELECT COALESCE(range_agg(int4range(est_id, est_id, %1$L)) FILTER (WHERE est_id IS NOT NULL), %2$L::int4multirange),
                COALESCE(range_agg(int4range(lu_id, lu_id, %1$L)) FILTER (WHERE lu_id IS NOT NULL), %2$L::int4multirange),
                COALESCE(range_agg(int4range(ent_id, ent_id, %1$L)) FILTER (WHERE ent_id IS NOT NULL), %2$L::int4multirange),
                COALESCE(range_agg(valid_range) FILTER (WHERE valid_range IS NOT NULL), %3$L::datemultirange)
         FROM (%s) AS mapped',
        '[]', '{}', '{}', v_source
    ) INTO v_est_ids, v_lu_ids, v_ent_ids, v_valid_range;

    -- Only insert if there's actually something to record
    IF v_est_ids != '{}'::int4multirange
       OR v_lu_ids != '{}'::int4multirange
       OR v_ent_ids != '{}'::int4multirange THEN
        INSERT INTO worker.base_change_log (establishment_ids, legal_unit_ids, enterprise_ids, edited_by_valid_range)
        VALUES (v_est_ids, v_lu_ids, v_ent_ids, v_valid_range);
    END IF;

    RETURN NULL;
END;
$log_base_change$;

-- Phase 11: Statement trigger function for task ensurance
-- Uses ON CONFLICT DO NOTHING (no row lock!) instead of DO UPDATE.
CREATE FUNCTION worker.ensure_collect_changes()
RETURNS TRIGGER
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

    PERFORM pg_notify('worker_tasks', 'analytics');
    RETURN NULL;
END;
$ensure_collect_changes$;

-- Phase 12: Register collect_changes command
INSERT INTO worker.command_registry (command, handler_procedure, queue, description)
VALUES ('collect_changes', 'worker.command_collect_changes', 'analytics',
        'Drain base_change_log and enqueue derive_statistical_unit with aggregated IDs');

-- Phase 13: Dedup index for collect_changes
CREATE UNIQUE INDEX idx_tasks_collect_changes_dedup
ON worker.tasks (command)
WHERE command = 'collect_changes' AND state = 'pending'::worker.task_state;

-- Phase 14: Handler procedure
CREATE PROCEDURE worker.command_collect_changes(IN p_payload jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
AS $command_collect_changes$
DECLARE
    v_row RECORD;
    v_est_ids int4multirange := '{}'::int4multirange;
    v_lu_ids int4multirange := '{}'::int4multirange;
    v_ent_ids int4multirange := '{}'::int4multirange;
    v_valid_range datemultirange := '{}'::datemultirange;
    v_valid_from DATE;
    v_valid_until DATE;
BEGIN
    -- Atomically drain all committed rows, merging multiranges
    FOR v_row IN DELETE FROM worker.base_change_log RETURNING * LOOP
        v_est_ids := v_est_ids + v_row.establishment_ids;
        v_lu_ids := v_lu_ids + v_row.legal_unit_ids;
        v_ent_ids := v_ent_ids + v_row.enterprise_ids;
        v_valid_range := v_valid_range + v_row.edited_by_valid_range;
    END LOOP;

    -- Clear crash recovery flag
    UPDATE worker.base_change_log_has_pending SET has_pending = FALSE;

    -- If any changes exist, enqueue derive
    IF v_est_ids != '{}'::int4multirange
       OR v_lu_ids != '{}'::int4multirange
       OR v_ent_ids != '{}'::int4multirange THEN
        -- Extract date bounds for enqueue_derive interface (takes DATE, not daterange)
        v_valid_from := lower(v_valid_range);
        v_valid_until := upper(v_valid_range);

        PERFORM worker.enqueue_derive_statistical_unit(
            p_establishment_id_ranges := v_est_ids,
            p_legal_unit_id_ranges := v_lu_ids,
            p_enterprise_id_ranges := v_ent_ids,
            p_valid_from := v_valid_from,
            p_valid_until := v_valid_until
        );
    END IF;
END;
$command_collect_changes$;

-- =============================================================================
-- Phase 15: Replace setup/teardown and add new helper
-- =============================================================================

-- New helper: creates 32 triggers (8 tables x 4 triggers each)
CREATE OR REPLACE PROCEDURE worker.setup_base_change_triggers()
LANGUAGE plpgsql
AS $setup_base_change_triggers$
DECLARE
    v_table_name TEXT;
BEGIN
    FOREACH v_table_name IN ARRAY ARRAY[
        'enterprise', 'external_ident', 'legal_unit', 'establishment',
        'activity', 'location', 'contact', 'stat_for_unit'
    ]
    LOOP
        -- Statement triggers with REFERENCING for ID capture
        -- Named a_* to fire before b_* (PG fires alphabetically)
        EXECUTE format(
            'CREATE TRIGGER %I
            AFTER INSERT ON public.%I
            REFERENCING NEW TABLE AS new_rows
            FOR EACH STATEMENT
            EXECUTE FUNCTION worker.log_base_change()',
            'a_' || v_table_name || '_log_insert',
            v_table_name
        );

        EXECUTE format(
            'CREATE TRIGGER %I
            AFTER UPDATE ON public.%I
            REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows
            FOR EACH STATEMENT
            EXECUTE FUNCTION worker.log_base_change()',
            'a_' || v_table_name || '_log_update',
            v_table_name
        );

        EXECUTE format(
            'CREATE TRIGGER %I
            AFTER DELETE ON public.%I
            REFERENCING OLD TABLE AS old_rows
            FOR EACH STATEMENT
            EXECUTE FUNCTION worker.log_base_change()',
            'a_' || v_table_name || '_log_delete',
            v_table_name
        );

        -- Statement trigger for task ensurance (fires after a_* triggers)
        EXECUTE format(
            'CREATE TRIGGER %I
            AFTER INSERT OR UPDATE OR DELETE ON public.%I
            FOR EACH STATEMENT
            EXECUTE FUNCTION worker.ensure_collect_changes()',
            'b_' || v_table_name || '_ensure_collect',
            v_table_name
        );
    END LOOP;
END;
$setup_base_change_triggers$;

-- Replace setup()
CREATE OR REPLACE PROCEDURE worker.setup()
LANGUAGE plpgsql
AS $procedure$
BEGIN
    -- Create base change tracking triggers on all 8 tables
    CALL worker.setup_base_change_triggers();

    -- Create the initial cleanup_tasks task to run daily
    PERFORM worker.enqueue_task_cleanup();
    -- Create the initial import_job_cleanup task to run daily
    PERFORM worker.enqueue_import_job_cleanup();
END;
$procedure$;

-- Replace teardown()
CREATE OR REPLACE PROCEDURE worker.teardown()
LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_table_name TEXT;
BEGIN
    FOREACH v_table_name IN ARRAY ARRAY[
        'enterprise', 'external_ident', 'legal_unit', 'establishment',
        'activity', 'location', 'contact', 'stat_for_unit'
    ]
    LOOP
        -- Drop new triggers
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', 'a_' || v_table_name || '_log_insert', v_table_name);
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', 'a_' || v_table_name || '_log_update', v_table_name);
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', 'a_' || v_table_name || '_log_delete', v_table_name);
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', 'b_' || v_table_name || '_ensure_collect', v_table_name);
        -- Also drop legacy triggers if they still exist
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', v_table_name || '_deletes_trigger', v_table_name);
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', v_table_name || '_statement_changes_trigger', v_table_name);
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', v_table_name || '_row_changes_trigger', v_table_name);
    END LOOP;
END;
$procedure$;

-- Phase 16: Update reset_abandoned_processing_tasks with crash recovery
CREATE OR REPLACE FUNCTION worker.reset_abandoned_processing_tasks()
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_reset_count int := 0;
    v_task RECORD;
    v_stale_pid INT;
    v_has_pending BOOLEAN;
    v_change_log_count BIGINT;
BEGIN
    -- Terminate all other lingering worker backends FOR THIS DATABASE ONLY.
    FOR v_stale_pid IN
        SELECT pid FROM pg_stat_activity
        WHERE application_name = 'worker'
          AND pid <> pg_backend_pid()
          AND datname = current_database()
    LOOP
        RAISE LOG 'Terminating stale worker PID %', v_stale_pid;
        PERFORM pg_terminate_backend(v_stale_pid);
    END LOOP;

    -- Find tasks stuck in 'processing' and reset their status to 'pending'.
    FOR v_task IN
        SELECT id FROM worker.tasks WHERE state = 'processing'::worker.task_state FOR UPDATE
    LOOP
        UPDATE worker.tasks
        SET state = 'pending'::worker.task_state,
            worker_pid = NULL,
            processed_at = NULL,
            error = NULL,
            duration_ms = NULL
        WHERE id = v_task.id;

        v_reset_count := v_reset_count + 1;
    END LOOP;

    -- CRASH RECOVERY: Detect if UNLOGGED base_change_log was truncated by PG crash.
    -- If has_pending = TRUE (LOGGED, survives crash) but base_change_log is empty
    -- (UNLOGGED, truncated on unclean shutdown), we lost change data.
    -- Enqueue a full refresh to recover.
    SELECT has_pending INTO v_has_pending
    FROM worker.base_change_log_has_pending;

    IF v_has_pending THEN
        SELECT count(*) INTO v_change_log_count
        FROM worker.base_change_log;

        IF v_change_log_count = 0 THEN
            -- UNLOGGED data was lost in crash - enqueue full refresh
            RAISE LOG 'Crash recovery: base_change_log_has_pending=TRUE but base_change_log is empty. Enqueueing full refresh.';
            PERFORM worker.enqueue_derive_statistical_unit(
                p_establishment_id_ranges := '{(,)}'::int4multirange,
                p_legal_unit_id_ranges := '{(,)}'::int4multirange,
                p_enterprise_id_ranges := '{(,)}'::int4multirange,
                p_valid_from := '-infinity'::DATE,
                p_valid_until := 'infinity'::DATE
            );
            UPDATE worker.base_change_log_has_pending SET has_pending = FALSE;
        END IF;
    END IF;

    RETURN v_reset_count;
END;
$function$;

-- Phase 17: Create the triggers
CALL worker.setup();

END;
