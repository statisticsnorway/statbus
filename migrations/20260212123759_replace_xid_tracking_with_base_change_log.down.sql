-- Down Migration 20260212123759: replace_xid_tracking_with_base_change_log
BEGIN;

-- Phase 1: Drop new triggers
CALL worker.teardown();

-- Phase 2: Remove new command from registry
DELETE FROM worker.command_registry WHERE command = 'collect_changes';

-- Phase 3: Drop new objects
DROP PROCEDURE IF EXISTS worker.command_collect_changes(jsonb);
DROP FUNCTION IF EXISTS worker.log_base_change();
DROP FUNCTION IF EXISTS worker.ensure_collect_changes();
DROP PROCEDURE IF EXISTS worker.setup_base_change_triggers();
DROP INDEX IF EXISTS worker.idx_tasks_collect_changes_dedup;
DROP TABLE IF EXISTS worker.base_change_log;
DROP TABLE IF EXISTS worker.base_change_log_has_pending;

-- Phase 4: Restore old tracking table
CREATE TABLE worker.last_processed (
    table_name text NOT NULL,
    transaction_id bigint NOT NULL,
    CONSTRAINT last_processed_pkey PRIMARY KEY (table_name)
);
GRANT SELECT ON worker.last_processed TO authenticated;

-- Phase 5: Restore old dedup indexes
CREATE UNIQUE INDEX idx_tasks_check_table_dedup
ON worker.tasks USING btree (((payload ->> 'table_name'::text)))
WHERE command = 'check_table'::text AND state = 'pending'::worker.task_state;

CREATE UNIQUE INDEX idx_tasks_deleted_row_dedup
ON worker.tasks USING btree (((payload ->> 'table_name'::text)))
WHERE command = 'deleted_row'::text AND state = 'pending'::worker.task_state;

-- Phase 6: Restore old commands in registry
INSERT INTO worker.command_registry (command, handler_procedure, queue, description)
VALUES
    ('check_table', 'worker.command_check_table', 'analytics',
     'Process changes in a table since a specific transaction ID'),
    ('deleted_row', 'worker.command_deleted_row', 'analytics',
     'Handle deletion of rows from statistical unit tables');

-- Phase 7: Restore old functions (dumped via \sf from current database)

CREATE OR REPLACE FUNCTION worker.enqueue_check_table(p_table_name text, p_transaction_id bigint)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_task_id BIGINT;
  v_payload JSONB;
BEGIN
  -- Create payload
  v_payload := jsonb_build_object(
    'table_name', p_table_name,
    'transaction_id', p_transaction_id
  );

  -- Insert with ON CONFLICT for this specific command type
  INSERT INTO worker.tasks (
    command, payload
  ) VALUES ('check_table', v_payload)
  ON CONFLICT ((payload->>'table_name')) WHERE command = 'check_table' AND state = 'pending'::worker.task_state
  DO UPDATE SET
    payload = jsonb_set(
      worker.tasks.payload,
      '{transaction_id}',
      -- Use age() for a wraparound-safe comparison to find the newer transaction ID.
      -- The transaction with the smaller age is the newer one.
      to_jsonb(
        CASE
          WHEN age((worker.tasks.payload->>'transaction_id')::bigint::text::xid) > age((EXCLUDED.payload->>'transaction_id')::bigint::text::xid)
          THEN (EXCLUDED.payload->>'transaction_id')::bigint
          ELSE (worker.tasks.payload->>'transaction_id')::bigint
        END
      )
    ),
    state = 'pending'::worker.task_state,
    priority = EXCLUDED.priority,  -- Use the new priority to push queue position
    processed_at = NULL,
    error = NULL
  RETURNING id INTO v_task_id;

  -- Notify worker of new task with queue information
  PERFORM pg_notify('worker_tasks', 'analytics');

  RETURN v_task_id;
END;
$function$;

CREATE OR REPLACE PROCEDURE worker.command_check_table(IN payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $procedure$
DECLARE
    v_table_name text = payload->>'table_name';
    v_last_processed_txid bigint;
    v_unit_id_columns text;
    v_valid_columns text;
    v_changed_rows record;
    v_establishment_ids int[] := ARRAY[]::int[];
    v_legal_unit_ids int[] := ARRAY[]::int[];
    v_enterprise_ids int[] := ARRAY[]::int[];
    v_valid_from date := NULL::date;
    v_valid_until date := NULL::date;
BEGIN
    -- Get the last transaction ID successfully processed for this table.
    -- If this is the first run, COALESCE will start the range from 0.
    SELECT transaction_id INTO v_last_processed_txid
    FROM worker.last_processed
    WHERE table_name = v_table_name;

    v_last_processed_txid := COALESCE(v_last_processed_txid, 0);

    RAISE DEBUG '[worker.command_check_table] Checking table % for changes since transaction ID %',
        v_table_name, v_last_processed_txid;

  -- Set up columns based on table type
  CASE v_table_name
    WHEN 'establishment' THEN
      v_unit_id_columns := 'id AS establishment_id, legal_unit_id, enterprise_id';
    WHEN 'legal_unit' THEN
      v_unit_id_columns := 'NULL::INT AS establishment_id, id AS legal_unit_id, enterprise_id';
    WHEN 'enterprise' THEN
      v_unit_id_columns := 'NULL::INT AS establishment_id, NULL::INT AS legal_unit_id, id AS enterprise_id';
    WHEN 'activity', 'location', 'contact', 'stat_for_unit' THEN
      v_unit_id_columns := 'establishment_id, legal_unit_id, NULL::INT AS enterprise_id';
    WHEN 'external_ident' THEN
      v_unit_id_columns := 'establishment_id, legal_unit_id, enterprise_id';
    ELSE
      RAISE EXCEPTION 'Unknown table: %', v_table_name;
  END CASE;

  -- Set up validity columns
  -- Enterprise and external_ident derive dates from related temporal tables
  -- instead of returning NULL (which would cause -infinity/infinity full refresh).
  CASE v_table_name
    WHEN 'enterprise' THEN
      v_valid_columns := $valid_cols$
        (SELECT MIN(es.valid_from) FROM public.establishment AS es WHERE es.enterprise_id = enterprise.id) AS valid_from,
        NULL::DATE AS valid_to,
        (SELECT MAX(es.valid_until) FROM public.establishment AS es WHERE es.enterprise_id = enterprise.id) AS valid_until
      $valid_cols$;
    WHEN 'external_ident' THEN
      -- Use MIN/MAX because establishments and legal_units have multiple temporal periods
      v_valid_columns := $valid_cols$
        COALESCE(
          (SELECT MIN(es.valid_from) FROM public.establishment AS es WHERE es.id = external_ident.establishment_id),
          (SELECT MIN(lu.valid_from) FROM public.legal_unit AS lu WHERE lu.id = external_ident.legal_unit_id),
          (SELECT MIN(es.valid_from) FROM public.establishment AS es WHERE es.enterprise_id = external_ident.enterprise_id)
        ) AS valid_from,
        NULL::DATE AS valid_to,
        COALESCE(
          (SELECT MAX(es.valid_until) FROM public.establishment AS es WHERE es.id = external_ident.establishment_id),
          (SELECT MAX(lu.valid_until) FROM public.legal_unit AS lu WHERE lu.id = external_ident.legal_unit_id),
          (SELECT MAX(es.valid_until) FROM public.establishment AS es WHERE es.enterprise_id = external_ident.enterprise_id)
        ) AS valid_until
      $valid_cols$;
    WHEN 'establishment', 'legal_unit', 'activity', 'location', 'contact', 'stat_for_unit' THEN
      v_valid_columns := 'valid_from, valid_to, valid_until';
    ELSE
      RAISE EXCEPTION 'Unknown table: %', v_table_name;
  END CASE;

  -- Find changed rows using a wraparound-safe check. This selects all rows
  -- with a transaction ID greater than or equal to the last one processed.
  -- The upper bound is implicitly and safely handled by the transaction snapshot.
  FOR v_changed_rows IN EXECUTE format(
    'SELECT id, %s, %s
     FROM %I
     WHERE age($1::text::xid) >= age(xmin)
     ORDER BY id',
    v_unit_id_columns, v_valid_columns, v_table_name
  ) USING v_last_processed_txid
  LOOP
    -- Accumulate IDs
    IF v_changed_rows.establishment_id IS NOT NULL THEN
      v_establishment_ids := array_append(v_establishment_ids, v_changed_rows.establishment_id);
    END IF;
    IF v_changed_rows.legal_unit_id IS NOT NULL THEN
      v_legal_unit_ids := array_append(v_legal_unit_ids, v_changed_rows.legal_unit_id);
    END IF;
    IF v_changed_rows.enterprise_id IS NOT NULL THEN
      v_enterprise_ids := array_append(v_enterprise_ids, v_changed_rows.enterprise_id);
    END IF;

    -- Update validity range
    v_valid_from := LEAST(v_valid_from, v_changed_rows.valid_from);
    v_valid_until := GREATEST(v_valid_until, v_changed_rows.valid_until);
  END LOOP;

  -- Process collected IDs if any exist
  IF array_length(v_establishment_ids, 1) > 0 OR
     array_length(v_legal_unit_ids, 1) > 0 OR
     array_length(v_enterprise_ids, 1) > 0
  THEN
    -- Schedule statistical unit refresh
    PERFORM worker.enqueue_derive_statistical_unit(
      p_establishment_id_ranges := public.array_to_int4multirange(v_establishment_ids),
      p_legal_unit_id_ranges := public.array_to_int4multirange(v_legal_unit_ids),
      p_enterprise_id_ranges := public.array_to_int4multirange(v_enterprise_ids),
      p_valid_from := v_valid_from,
      p_valid_until := v_valid_until
    );
  END IF;

  -- Record that we have successfully processed up to the current transaction ID.
  -- This transaction ID serves as the new bookmark for the next run.
  INSERT INTO worker.last_processed (table_name, transaction_id)
  VALUES (v_table_name, txid_current())
  ON CONFLICT (table_name)
  DO UPDATE SET transaction_id = EXCLUDED.transaction_id;
END;
$procedure$;

CREATE OR REPLACE FUNCTION worker.enqueue_deleted_row(p_table_name text, p_establishment_id integer DEFAULT NULL::integer, p_legal_unit_id integer DEFAULT NULL::integer, p_enterprise_id integer DEFAULT NULL::integer, p_valid_from date DEFAULT NULL::date, p_valid_until date DEFAULT NULL::date)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_task_id BIGINT;
  v_payload JSONB;
  v_existing_payload JSONB;
  v_establishment_ids INT[] := ARRAY[]::INT[];
  v_legal_unit_ids INT[] := ARRAY[]::INT[];
  v_enterprise_ids INT[] := ARRAY[]::INT[];
BEGIN
  -- Add the single IDs to arrays if they're not NULL
  IF p_establishment_id IS NOT NULL THEN
    v_establishment_ids := ARRAY[p_establishment_id];
  END IF;

  IF p_legal_unit_id IS NOT NULL THEN
    v_legal_unit_ids := ARRAY[p_legal_unit_id];
  END IF;

  IF p_enterprise_id IS NOT NULL THEN
    v_enterprise_ids := ARRAY[p_enterprise_id];
  END IF;

  -- Create payload with arrays
  -- Create initial payload with arrays
  v_payload := jsonb_build_object(
    'command', 'deleted_row',
    'table_name', p_table_name,
    'establishment_ids', to_jsonb(v_establishment_ids),
    'legal_unit_ids', to_jsonb(v_legal_unit_ids),
    'enterprise_ids', to_jsonb(v_enterprise_ids),
    'valid_from', p_valid_from,
    'valid_until', p_valid_until
  );

  -- Insert or update the task with array merging in the conflict clause
  INSERT INTO worker.tasks AS t (
    command, payload
  ) VALUES ('deleted_row', v_payload)
  ON CONFLICT ((payload->>'table_name'))
  WHERE command = 'deleted_row' AND state = 'pending'::worker.task_state
  DO UPDATE SET
    payload = jsonb_build_object(
      'command', 'deleted_row',
      'table_name', p_table_name,
      -- Merge and deduplicate establishment IDs
      'establishment_ids', to_jsonb(
        ARRAY(
          SELECT DISTINCT unnest
          FROM unnest(
            array_cat(
              ARRAY(SELECT jsonb_array_elements_text(t.payload->'establishment_ids')::int),
              ARRAY(SELECT jsonb_array_elements_text(EXCLUDED.payload->'establishment_ids')::int)
            )
          )
          WHERE unnest IS NOT NULL
          ORDER BY 1
        )
      ),
      -- Merge and deduplicate legal unit IDs
      'legal_unit_ids', to_jsonb(
        ARRAY(
          SELECT DISTINCT unnest
          FROM unnest(
            array_cat(
              ARRAY(SELECT jsonb_array_elements_text(t.payload->'legal_unit_ids')::int),
              ARRAY(SELECT jsonb_array_elements_text(EXCLUDED.payload->'legal_unit_ids')::int)
            )
          )
          WHERE unnest IS NOT NULL
          ORDER BY 1
        )
      ),
      -- Merge and deduplicate enterprise IDs
      'enterprise_ids', to_jsonb(
        ARRAY(
          SELECT DISTINCT unnest
          FROM unnest(
            array_cat(
              ARRAY(SELECT jsonb_array_elements_text(t.payload->'enterprise_ids')::int),
              ARRAY(SELECT jsonb_array_elements_text(EXCLUDED.payload->'enterprise_ids')::int)
            )
          )
          WHERE unnest IS NOT NULL
          ORDER BY 1
        )
      ),
      -- Expand date ranges
      'valid_from', LEAST(
        (t.payload->>'valid_from')::date,
        (EXCLUDED.payload->>'valid_from')::date
      ),
      'valid_until', GREATEST(
        (t.payload->>'valid_until')::date,
        (EXCLUDED.payload->>'valid_until')::date
      )
    ),
    state = 'pending'::worker.task_state,
    priority = EXCLUDED.priority,  -- Use the new priority to push queue position
    processed_at = NULL,
    error = NULL
  RETURNING id INTO v_task_id;

  PERFORM pg_notify('worker_tasks', 'analytics');

  RETURN v_task_id;
END;
$function$;

CREATE OR REPLACE PROCEDURE worker.command_deleted_row(IN payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $procedure$
DECLARE
    v_table_name text = payload->>'table_name';
    v_establishment_ids int[] = CASE
        WHEN jsonb_typeof(payload->'establishment_ids') = 'array' THEN
            ARRAY(
                SELECT elem::int
                FROM jsonb_array_elements_text(payload->'establishment_ids') AS x(elem)
                WHERE elem IS NOT NULL AND elem ~ '^[0-9]+$'
            )
        ELSE ARRAY[]::int[]
    END;
    v_legal_unit_ids int[] = CASE
        WHEN jsonb_typeof(payload->'legal_unit_ids') = 'array' THEN
            ARRAY(
                SELECT elem::int
                FROM jsonb_array_elements_text(payload->'legal_unit_ids') AS x(elem)
                WHERE elem IS NOT NULL AND elem ~ '^[0-9]+$'
            )
        ELSE ARRAY[]::int[]
    END;
    v_enterprise_ids int[] = CASE
        WHEN jsonb_typeof(payload->'enterprise_ids') = 'array' THEN
            ARRAY(
                SELECT elem::int
                FROM jsonb_array_elements_text(payload->'enterprise_ids') AS x(elem)
                WHERE elem IS NOT NULL AND elem ~ '^[0-9]+$'
            )
        ELSE ARRAY[]::int[]
    END;
    v_valid_from date = (payload->>'valid_from')::date;
    v_valid_until date = (payload->>'valid_until')::date;
BEGIN
  -- Schedule statistical unit refresh
  PERFORM worker.enqueue_derive_statistical_unit(
    p_establishment_id_ranges := public.array_to_int4multirange(v_establishment_ids),
    p_legal_unit_id_ranges := public.array_to_int4multirange(v_legal_unit_ids),
    p_enterprise_id_ranges := public.array_to_int4multirange(v_enterprise_ids),
    p_valid_from := v_valid_from,
    p_valid_until := v_valid_until
  );
END;
$procedure$;

CREATE OR REPLACE FUNCTION worker.notify_worker_about_statement_changes()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- Enqueue a check_table task for the affected table.
  PERFORM worker.enqueue_check_table(
    p_table_name := TG_TABLE_NAME,
    p_transaction_id := txid_current()
  );
  RETURN NULL; -- Statement-level AFTER triggers must return NULL.
END;
$function$;

CREATE OR REPLACE FUNCTION worker.notify_worker_about_row_changes()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- Enqueue a deleted_row task for the OLD parent IDs. This handles re-parenting,
  -- ensuring that the old parent's data is refreshed to reflect the removal of the child.
  CASE TG_TABLE_NAME
    WHEN 'establishment' THEN
      PERFORM worker.enqueue_deleted_row(
        p_table_name := TG_TABLE_NAME,
        p_establishment_id := OLD.id,
        p_legal_unit_id := OLD.legal_unit_id,
        p_enterprise_id := OLD.enterprise_id,
        p_valid_from := OLD.valid_from,
        p_valid_until := OLD.valid_until
      );
    WHEN 'legal_unit' THEN
      PERFORM worker.enqueue_deleted_row(
        p_table_name := TG_TABLE_NAME,
        p_establishment_id := NULL,
        p_legal_unit_id := OLD.id,
        p_enterprise_id := OLD.enterprise_id,
        p_valid_from := OLD.valid_from,
        p_valid_until := OLD.valid_until
      );
    WHEN 'activity', 'location', 'contact', 'stat_for_unit' THEN
      PERFORM worker.enqueue_deleted_row(
        p_table_name := TG_TABLE_NAME,
        p_establishment_id := OLD.establishment_id,
        p_legal_unit_id := OLD.legal_unit_id,
        p_enterprise_id := NULL,
        p_valid_from := OLD.valid_from,
        p_valid_until := OLD.valid_until
      );
    WHEN 'external_ident' THEN
      PERFORM worker.enqueue_deleted_row(
        p_table_name := TG_TABLE_NAME,
        p_establishment_id := OLD.establishment_id,
        p_legal_unit_id := OLD.legal_unit_id,
        p_enterprise_id := OLD.enterprise_id,
        p_valid_from := NULL,
        p_valid_until := NULL
      );
    ELSE
      RAISE EXCEPTION 'Unexpected table name in row change trigger: %', TG_TABLE_NAME;
  END CASE;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION worker.notify_worker_about_deletes()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  establishment_id_value int;
  legal_unit_id_value int;
  enterprise_id_value int;
  valid_from_value date;
  valid_until_value date;
BEGIN
  -- Set values based on table name
  CASE TG_TABLE_NAME
    WHEN 'establishment' THEN
      establishment_id_value := OLD.id;
      legal_unit_id_value := OLD.legal_unit_id;
      enterprise_id_value := OLD.enterprise_id;
      valid_from_value := OLD.valid_from;
      valid_until_value := OLD.valid_until;
    WHEN 'legal_unit' THEN
      establishment_id_value := NULL;
      legal_unit_id_value := OLD.id;
      enterprise_id_value := OLD.enterprise_id;
      valid_from_value := OLD.valid_from;
      valid_until_value := OLD.valid_until;
    WHEN 'enterprise' THEN
      establishment_id_value := NULL;
      legal_unit_id_value := NULL;
      enterprise_id_value := OLD.id;
      valid_from_value := NULL;
      valid_until_value := NULL;
    WHEN 'activity','location','contact','stat_for_unit' THEN
      establishment_id_value := OLD.establishment_id;
      legal_unit_id_value := OLD.legal_unit_id;
      enterprise_id_value := NULL;
      valid_from_value := OLD.valid_from;
      valid_until_value := OLD.valid_until;
    WHEN 'external_ident' THEN
      establishment_id_value := OLD.establishment_id;
      legal_unit_id_value := OLD.legal_unit_id;
      enterprise_id_value := OLD.enterprise_id;
      valid_from_value := NULL;
      valid_until_value := NULL;
    ELSE
      RAISE EXCEPTION 'Unexpected table name in delete trigger: %', TG_TABLE_NAME;
  END CASE;

  -- Enqueue deleted row task
  PERFORM worker.enqueue_deleted_row(
    p_table_name := TG_TABLE_NAME,
    p_establishment_id := establishment_id_value,
    p_legal_unit_id := legal_unit_id_value,
    p_enterprise_id := enterprise_id_value,
    p_valid_from := valid_from_value,
    p_valid_until := valid_until_value
  );

  RETURN OLD;
END;
$function$;

-- Phase 8: Restore old setup helpers

CREATE OR REPLACE PROCEDURE worker.setup_statement_triggers(IN p_table_names text[])
 LANGUAGE plpgsql
AS $procedure$
DECLARE
  table_name TEXT;
BEGIN
  FOREACH table_name IN ARRAY p_table_names
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_trigger
      WHERE tgname = table_name || '_statement_changes_trigger' AND tgrelid = ('public.' || table_name)::regclass
    ) THEN
      EXECUTE format(
        'CREATE TRIGGER %I
        AFTER INSERT OR UPDATE ON public.%I
        FOR EACH STATEMENT
        EXECUTE FUNCTION worker.notify_worker_about_statement_changes()',
        table_name || '_statement_changes_trigger',
        table_name
      );
    END IF;
  END LOOP;
END;
$procedure$;

CREATE OR REPLACE PROCEDURE worker.setup_row_level_triggers()
 LANGUAGE plpgsql
AS $procedure$
DECLARE
  table_name TEXT;
  when_clause TEXT;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'establishment', 'legal_unit', 'external_ident',
    'activity', 'location', 'contact', 'stat_for_unit'
  ]
  LOOP
    CASE table_name
      WHEN 'establishment' THEN
        when_clause := 'WHEN (OLD.legal_unit_id IS DISTINCT FROM NEW.legal_unit_id OR OLD.enterprise_id IS DISTINCT FROM NEW.enterprise_id)';
      WHEN 'legal_unit' THEN
        when_clause := 'WHEN (OLD.enterprise_id IS DISTINCT FROM NEW.enterprise_id)';
      WHEN 'external_ident' THEN
        when_clause := 'WHEN (OLD.establishment_id IS DISTINCT FROM NEW.establishment_id OR OLD.legal_unit_id IS DISTINCT FROM NEW.legal_unit_id OR OLD.enterprise_id IS DISTINCT FROM NEW.enterprise_id)';
      WHEN 'activity', 'location', 'contact', 'stat_for_unit' THEN
        when_clause := 'WHEN (OLD.establishment_id IS DISTINCT FROM NEW.establishment_id OR OLD.legal_unit_id IS DISTINCT FROM NEW.legal_unit_id)';
    END CASE;

    IF NOT EXISTS (
      SELECT 1 FROM pg_trigger
      WHERE tgname = table_name || '_row_changes_trigger' AND tgrelid = ('public.' || table_name)::regclass
    ) THEN
      EXECUTE format(
        'CREATE TRIGGER %I
        AFTER UPDATE ON public.%I
        FOR EACH ROW
        %s
        EXECUTE FUNCTION worker.notify_worker_about_row_changes()',
        table_name || '_row_changes_trigger',
        table_name,
        when_clause
      );
    END IF;
  END LOOP;
END;
$procedure$;

CREATE OR REPLACE PROCEDURE worker.setup_delete_triggers(IN p_table_names text[])
 LANGUAGE plpgsql
AS $procedure$
DECLARE
  table_name TEXT;
BEGIN
  FOREACH table_name IN ARRAY p_table_names
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_trigger
      WHERE tgname = table_name || '_deletes_trigger' AND tgrelid = ('public.' || table_name)::regclass
    ) THEN
      EXECUTE format(
        'CREATE TRIGGER %I
        BEFORE DELETE ON public.%I
        FOR EACH ROW
        EXECUTE FUNCTION worker.notify_worker_about_deletes()',
        table_name || '_deletes_trigger',
        table_name
      );
    END IF;
  END LOOP;
END;
$procedure$;

-- Phase 9: Restore old setup/teardown

CREATE OR REPLACE PROCEDURE worker.setup()
 LANGUAGE plpgsql
AS $procedure$
BEGIN
  -- Create STATEMENT-level triggers for INSERT or UPDATE
  CALL worker.setup_statement_triggers(ARRAY[
    'enterprise', 'external_ident', 'legal_unit', 'establishment',
    'activity', 'location', 'contact', 'stat_for_unit'
  ]);

  -- Create ROW-level triggers for UPDATE to handle re-parenting.
  CALL worker.setup_row_level_triggers();

  -- Create ROW-level triggers for DELETE
  CALL worker.setup_delete_triggers(ARRAY[
    'enterprise', 'external_ident', 'legal_unit', 'establishment',
    'activity', 'location', 'contact', 'stat_for_unit'
  ]);

  -- Create the initial cleanup_tasks task to run daily
  PERFORM worker.enqueue_task_cleanup();
  -- Create the initial import_job_cleanup task to run daily
  PERFORM worker.enqueue_import_job_cleanup();
END;
$procedure$;

CREATE OR REPLACE PROCEDURE worker.teardown()
 LANGUAGE plpgsql
AS $procedure$
DECLARE
  table_name text;
BEGIN
  FOR table_name IN
    SELECT unnest(ARRAY[
      'enterprise', 'external_ident', 'legal_unit', 'establishment',
      'activity', 'location', 'contact', 'stat_for_unit'
    ])
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', table_name || '_deletes_trigger', table_name);
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', table_name || '_statement_changes_trigger', table_name);
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', table_name || '_row_changes_trigger', table_name);
  END LOOP;
END;
$procedure$;

-- Phase 10: Restore reset_abandoned_processing_tasks (without crash recovery)
CREATE OR REPLACE FUNCTION worker.reset_abandoned_processing_tasks()
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_reset_count int := 0;
  v_task RECORD;
  v_stale_pid INT;
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
  RETURN v_reset_count;
END;
$function$;

-- Phase 11: Recreate old triggers
CALL worker.setup();

END;
