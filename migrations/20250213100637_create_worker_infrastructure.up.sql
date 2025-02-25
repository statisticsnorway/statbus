-- Migration 20250213100637: create worker
BEGIN;

CREATE SCHEMA IF NOT EXISTS "worker";

-- Grant necessary permissions
GRANT USAGE ON SCHEMA worker TO authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA worker TO authenticated;

-- Create settings table for persistent worker mode
CREATE TABLE worker.settings (
  key text PRIMARY KEY,
  value text NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON worker.settings TO authenticated;

CREATE TABLE IF NOT EXISTS worker.last_processed (
  table_name text PRIMARY KEY,
  transaction_id bigint NOT NULL
);
GRANT SELECT, INSERT, UPDATE ON worker.last_processed TO authenticated;

-- currently in that table with worker.process, using subtransaction (savepoint)
-- to ensure that one failure will not stop it all.
-- So there are two functions with overload worker.process() and worker.process(jsonb).

-- Create unlogged notifications table for batch processing
CREATE UNLOGGED TABLE IF NOT EXISTS worker.notifications (
  id BIGSERIAL PRIMARY KEY,
  payload JSONB NOT NULL
);

-- Create statistical unit refresh function
CREATE FUNCTION worker.statistical_unit_refresh_for_ids(
  establishment_ids int[] DEFAULT NULL,
  legal_unit_ids int[] DEFAULT NULL,
  enterprise_ids int[] DEFAULT NULL,
  valid_after date DEFAULT NULL,
  valid_to date DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
AS $statistical_unit_refresh_for_ids$
BEGIN
  -- Delete affected entries
  DELETE FROM public.statistical_unit AS su
  WHERE (
    (su.unit_type = 'establishment' AND su.unit_id = ANY(statistical_unit_refresh_for_ids.establishment_ids)) OR
    (su.unit_type = 'legal_unit' AND su.unit_id = ANY(statistical_unit_refresh_for_ids.legal_unit_ids)) OR
    (su.unit_type = 'enterprise' AND su.unit_id = ANY(statistical_unit_refresh_for_ids.enterprise_ids)) OR
    su.establishment_ids && statistical_unit_refresh_for_ids.establishment_ids OR
    su.legal_unit_ids && statistical_unit_refresh_for_ids.legal_unit_ids OR
    su.enterprise_ids && statistical_unit_refresh_for_ids.enterprise_ids
  )
  AND daterange(su.valid_after, su.valid_to, '(]') &&
      daterange(COALESCE(statistical_unit_refresh_for_ids.valid_after, '-infinity'::date),
               COALESCE(statistical_unit_refresh_for_ids.valid_to, 'infinity'::date), '(]');

  -- Insert new entries
  INSERT INTO public.statistical_unit
  SELECT * FROM public.statistical_unit_def AS sud
  WHERE (
    (sud.unit_type = 'establishment' AND sud.unit_id = ANY(statistical_unit_refresh_for_ids.establishment_ids)) OR
    (sud.unit_type = 'legal_unit' AND sud.unit_id = ANY(statistical_unit_refresh_for_ids.legal_unit_ids)) OR
    (sud.unit_type = 'enterprise' AND sud.unit_id = ANY(statistical_unit_refresh_for_ids.enterprise_ids)) OR
    sud.establishment_ids && statistical_unit_refresh_for_ids.establishment_ids OR
    sud.legal_unit_ids && statistical_unit_refresh_for_ids.legal_unit_ids OR
    sud.enterprise_ids && statistical_unit_refresh_for_ids.enterprise_ids
  )
  AND daterange(sud.valid_after, sud.valid_to, '(]') &&
      daterange(COALESCE(statistical_unit_refresh_for_ids.valid_after, '-infinity'::date),
               COALESCE(statistical_unit_refresh_for_ids.valid_to, 'infinity'::date), '(]');

  -- Notify worker to refresh derived data
  PERFORM worker.notify(jsonb_build_object(
    'command', 'refresh_derived_data',
    'valid_after', statistical_unit_refresh_for_ids.valid_after,
    'valid_to', statistical_unit_refresh_for_ids.valid_to
  ));
END;
$statistical_unit_refresh_for_ids$;

-- Create command handlers
CREATE FUNCTION worker.command_refresh_derived_data(payload jsonb)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_valid_after date := COALESCE((payload->>'valid_after')::date, '-infinity'::DATE);
    v_valid_to date := COALESCE((payload->>'valid_to')::date, 'infinity'::DATE);
BEGIN
    PERFORM public.activity_category_used_derive();
    PERFORM public.region_used_derive();
    PERFORM public.sector_used_derive();
    PERFORM public.data_source_used_derive();
    PERFORM public.legal_form_used_derive();
    PERFORM public.country_used_derive();

    PERFORM public.statistical_unit_facet_derive(
      valid_after := v_valid_after,
      valid_to := v_valid_to
    );

    PERFORM public.statistical_history_derive(
      valid_after := v_valid_after,
      valid_to := v_valid_to
    );

    PERFORM public.statistical_history_facet_derive(
      valid_after := v_valid_after,
      valid_to := v_valid_to
    );
END;
$function$;

CREATE FUNCTION worker.command_check_table(payload jsonb)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
  v_table_name text;
  v_transaction_id xid;
  v_current_txid bigint;
  v_unit_id_columns text;
  v_valid_columns text;
  v_changed_rows record;
  v_establishment_ids int[] := ARRAY[]::int[];
  v_legal_unit_ids int[] := ARRAY[]::int[];
  v_enterprise_ids int[] := ARRAY[]::int[];
  v_valid_after date;
  v_valid_to date;
BEGIN
  -- Extract values from payload
  v_table_name := payload->>'table_name';
  v_transaction_id := (payload->>'transaction_id')::xid;

  -- Get current transaction ID
  SELECT txid_current() INTO v_current_txid;

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
    ELSE
      RAISE EXCEPTION 'Unknown table: %', v_table_name;
  END CASE;

  -- Set up validity columns
  CASE v_table_name
    WHEN 'enterprise' THEN
      v_valid_columns := '''-infinity''::DATE AS valid_after, ''-infinity''::DATE AS valid_from, ''infinity''::DATE AS valid_to';
    WHEN 'establishment', 'legal_unit', 'activity', 'location', 'contact', 'stat_for_unit' THEN
      v_valid_columns := 'valid_after, valid_from, valid_to';
    ELSE
      RAISE EXCEPTION 'Unknown table: %', v_table_name;
  END CASE;

  -- Find changed rows
  FOR v_changed_rows IN EXECUTE format(
    'SELECT id, %s, %s
     FROM %I
     WHERE age(xmin) <= age($1::xid)
     ORDER BY id',
    v_unit_id_columns, v_valid_columns, v_table_name
  ) USING v_transaction_id
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
    v_valid_after := LEAST(v_valid_after, v_changed_rows.valid_after);
    v_valid_to := GREATEST(v_valid_to, v_changed_rows.valid_to);
  END LOOP;

  -- Process collected IDs if any exist
  IF array_length(v_establishment_ids, 1) > 0 OR
     array_length(v_legal_unit_ids, 1) > 0 OR
     array_length(v_enterprise_ids, 1) > 0
  THEN
    PERFORM worker.statistical_unit_refresh_for_ids(
      establishment_ids := v_establishment_ids,
      legal_unit_ids := v_legal_unit_ids,
      enterprise_ids := v_enterprise_ids,
      valid_after := v_valid_after,
      valid_to := v_valid_to
    );
  END IF;

  -- Record the check request in last_processed
  INSERT INTO worker.last_processed (table_name, transaction_id)
  VALUES (v_table_name, v_current_txid)
  ON CONFLICT (table_name)
  DO UPDATE SET transaction_id = EXCLUDED.transaction_id;
END;
$function$;

CREATE FUNCTION worker.command_deleted_row(payload jsonb)
RETURNS void
LANGUAGE plpgsql
AS $function$
BEGIN
  -- Handle deleted row by refreshing affected units
  PERFORM worker.statistical_unit_refresh_for_ids(
    establishment_ids := ARRAY[(payload->>'establishment_id')::int],
    legal_unit_ids := ARRAY[(payload->>'legal_unit_id')::int],
    enterprise_ids := ARRAY[(payload->>'enterprise_id')::int],
    valid_after := (payload->>'valid_after')::date,
    valid_to := (payload->>'valid_to')::date
  );
END;
$function$;


-- Create enum type for worker modes
CREATE TYPE worker.mode_type AS ENUM ('background', 'manual');

-- Create function to set/get worker mode
--
-- The worker system can run in two modes:
--
-- 1. Background Mode (Default):
--    - Commands sent via PostgreSQL NOTIFY/LISTEN
--    - Requires Crystal worker process listening for notifications
--    - Asynchronous processing outside transaction boundaries
--    - Suitable for production deployment
--
-- 2. Manual Mode:
--    - Commands stored in notifications table
--    - Process manually by calling worker.process_batch()
--    - No Crystal worker process needed
--    - Suitable for testing and controlled processing
--    - Can process in batches at suitable times
--

CREATE FUNCTION worker.mode(p_mode worker.mode_type DEFAULT NULL, persist boolean DEFAULT false)
RETURNS worker.mode_type
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = worker, pg_temp
AS $function$
DECLARE
  v_mode text;
BEGIN
  -- Always set session mode if p_mode is provided
  IF p_mode IS NOT NULL THEN
    PERFORM set_config('worker.mode', p_mode::text, false);

    IF persist THEN
      -- Also store in settings table if persist=true
      INSERT INTO worker.settings (key, value)
      VALUES ('mode', p_mode::text)
      ON CONFLICT (key) DO UPDATE
      SET value = EXCLUDED.value,
          updated_at = now();
    END IF;
  ELSIF persist AND p_mode IS NULL THEN
    -- Clear settings when called with NULL and persist=true
    DELETE FROM worker.settings WHERE key = 'mode';
    PERFORM set_config('worker.mode', NULL, false);
  END IF;

  -- Try to get mode from session first
  v_mode := current_setting('worker.mode', true);

  -- If not in session, try our settings table
  IF v_mode IS NULL THEN
    SELECT value INTO v_mode
    FROM worker.settings
    WHERE key = 'mode';
  END IF;

  -- If still not set, use default background mode
  IF v_mode IS NULL OR v_mode = '' THEN
    v_mode := 'background';
    PERFORM set_config('worker.mode', v_mode, false);
  END IF;

  -- Ensure we have a valid enum value
  IF v_mode NOT IN ('background', 'manual') THEN
    v_mode := 'background';
  END IF;

  RETURN v_mode::worker.mode_type;
END;
$function$;


-- Create function to deduplicate notifications
CREATE FUNCTION worker.deduplicate_batch()
RETURNS TABLE (
  rows_before bigint,
  rows_after bigint
)
LANGUAGE plpgsql
AS $function$
DECLARE
  v_rows_before bigint;
  v_rows_after bigint;
BEGIN
  -- Count rows before
  SELECT COUNT(*) INTO v_rows_before FROM worker.notifications;
  
  -- Combine all refresh_derived_data notifications into a single notification with the widest date range
  -- and delete duplicates in a single CTE
  WITH refresh_data AS (
    SELECT
      -- The latest id is the one to keep, since refresh should happen after all other changes. 
      MAX(id) AS keeper_id,
      LEAST(
        COALESCE(MIN(NULLIF((payload->>'valid_after')::text, '')::date), '-infinity'::date),
        '-infinity'::date
      ) AS new_valid_after,
      GREATEST(
        COALESCE(MAX(NULLIF((payload->>'valid_to')::text, '')::date), 'infinity'::date),
        'infinity'::date
      ) AS new_valid_to
    FROM worker.notifications
    WHERE payload->>'command' = 'refresh_derived_data'
    HAVING COUNT(*) > 0
  ),
  updated_keepers AS (
    UPDATE worker.notifications n
    SET payload = jsonb_set(
                    jsonb_set(n.payload, '{valid_after}', to_jsonb(refresh_data.new_valid_after::text)),
                    '{valid_to}', to_jsonb(refresh_data.new_valid_to::text)
                  )
    FROM refresh_data
    WHERE n.id = refresh_data.keeper_id
    RETURNING refresh_data.keeper_id
  )
  DELETE FROM worker.notifications n
  WHERE n.payload->>'command' = 'refresh_derived_data'
  AND n.id NOT IN (SELECT keeper_id FROM updated_keepers);

  -- For other commands, delete duplicates keeping only the most relevant notification per group
  DELETE FROM worker.notifications n
  WHERE n.id IN (
    SELECT id FROM (
      SELECT id,
        FIRST_VALUE(id) OVER w AS keeper_id
      FROM worker.notifications
      WHERE payload->>'command' IN ('check_table','deleted_row')
      WINDOW w AS (
        PARTITION BY 
          CASE 
            WHEN payload->>'command' = 'check_table' THEN payload->>'table_name'
            WHEN payload->>'command' = 'deleted_row' THEN
              payload->>'table_name' || ':' || 
              COALESCE(payload->>'establishment_id','') || ',' ||
              COALESCE(payload->>'legal_unit_id','') || ',' ||
              COALESCE(payload->>'enterprise_id','')
          END
        ORDER BY
          CASE payload->>'command'
            WHEN 'check_table' THEN (payload->>'transaction_id')::bigint
            ELSE id
          END DESC
      )
    ) dup
    WHERE id <> keeper_id
  );
  -- Count rows after
  SELECT COUNT(*) INTO v_rows_after FROM worker.notifications;

  -- Return the counts
  RETURN QUERY SELECT v_rows_before, v_rows_after;
END;
$function$;

-- Create worker notification function
CREATE FUNCTION worker.process_batch(
  batch_size integer DEFAULT NULL
)
RETURNS TABLE (
  id bigint,
  command text,
  table_name text,
  valid_after date,
  valid_to date,
  transaction_id bigint,
  duration_ms numeric,
  success boolean,
  payload jsonb,
  error_message text
)
LANGUAGE plpgsql
AS $function$
DECLARE
  notification_record RECORD;
  start_time timestamptz;
BEGIN
  LOOP
    -- Deduplicate notifications before processing
    DECLARE
      dedup_result record;
    BEGIN
      SELECT * INTO dedup_result FROM worker.deduplicate_batch();
      RAISE DEBUG 'Deduplicated notifications: % -> % rows', 
        dedup_result.rows_before, dedup_result.rows_after;
    END;

    -- Process notifications in batch
    FOR notification_record IN
      SELECT n.id, n.payload
      FROM worker.notifications AS n
      ORDER BY n.id
      LIMIT CASE 
        WHEN process_batch.batch_size IS NULL THEN NULL
        ELSE process_batch.batch_size
      END
    LOOP
      BEGIN
        -- Record start time
        start_time := clock_timestamp();
        
        -- Process command
        PERFORM worker.process_single(notification_record.payload);

        -- Return successful result with duration
        RETURN QUERY SELECT 
          notification_record.id,
          notification_record.payload->>'command',
          notification_record.payload->>'table_name',
          (notification_record.payload->>'valid_after')::DATE,
          (notification_record.payload->>'valid_to')::DATE,
          (notification_record.payload->>'transaction_id')::BIGINT,
          EXTRACT(EPOCH FROM (clock_timestamp() - start_time)) * 1000,
          true::boolean,
          notification_record.payload,
          NULL::text;

      EXCEPTION WHEN OTHERS THEN
        -- Return failed result with error and duration
        RETURN QUERY SELECT
          notification_record.id,
          notification_record.payload->>'command',
          notification_record.payload->>'table_name',
          (notification_record.payload->>'valid_after')::DATE,
          (notification_record.payload->>'valid_to')::DATE,
          (notification_record.payload->>'transaction_id')::BIGINT,
          EXTRACT(EPOCH FROM (clock_timestamp() - start_time)) * 1000,
          false::boolean,
          notification_record.payload,
          SQLERRM::text;
      END;

      -- Always delete the notification after processing, regardless of success
      DELETE FROM worker.notifications AS n WHERE n.id = notification_record.id;
    END LOOP;

    EXIT WHEN NOT FOUND;
  END LOOP;
END;
$function$;

CREATE FUNCTION worker.process_single(payload jsonb)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
  v_command text;
BEGIN
  v_command := payload->>'command';
  RAISE DEBUG 'Processing worker command: %', v_command;
  CASE v_command
    WHEN 'refresh_derived_data' THEN
      PERFORM worker.command_refresh_derived_data(payload);
    WHEN 'check_table' THEN
      PERFORM worker.command_check_table(payload);
    WHEN 'deleted_row' THEN
      PERFORM worker.command_deleted_row(payload);
    ELSE
      RAISE EXCEPTION 'Unknown command: %', v_command;
  END CASE;
END;
$function$;

CREATE FUNCTION worker.notify(payload jsonb)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
  v_mode worker.mode_type;
BEGIN
  -- Get current mode
  v_mode := worker.mode();

  -- Handle based on mode
  IF v_mode = 'background'::worker.mode_type THEN
    -- Background mode: send notification
    PERFORM pg_notify('worker', payload::text);
  ELSE
    -- Manual mode: insert into notifications for later processing
    INSERT INTO worker.notifications ( payload )
    VALUES ( notify.payload );
    -- Note: Call worker.process_batch() manually to process notifications
  END IF;
END;
$function$;

-- Create notifications table access
GRANT SELECT, INSERT, UPDATE, DELETE ON worker.notifications TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE worker.notifications_id_seq TO authenticated;


-- Create trigger functions for changes and deletes
CREATE FUNCTION worker.notify_worker_about_changes()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  PERFORM worker.notify(jsonb_build_object(
    'command', 'check_table',
    'table_name', TG_TABLE_NAME,
    'transaction_id', txid_current()
  ));
  RETURN NULL;
END;
$function$;

CREATE FUNCTION worker.notify_worker_about_deletes()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
  payload jsonb;
  establishment_id_value int;
  legal_unit_id_value int;
  enterprise_id_value int;
  valid_after_value date;
  valid_from_value date;
  valid_to_value date;
BEGIN
  -- Set values based on table name
  CASE TG_TABLE_NAME
    WHEN 'establishment' THEN
      establishment_id_value := OLD.id;
      legal_unit_id_value := OLD.legal_unit_id;
      enterprise_id_value := OLD.enterprise_id;
      valid_after_value := OLD.valid_after;
      valid_from_value := OLD.valid_from;
      valid_to_value := OLD.valid_to;
    WHEN 'legal_unit' THEN
      establishment_id_value := NULL;
      legal_unit_id_value := OLD.id;
      enterprise_id_value := OLD.enterprise_id;
      valid_after_value := OLD.valid_after;
      valid_from_value := OLD.valid_from;
      valid_to_value := OLD.valid_to;
    WHEN 'enterprise' THEN
      establishment_id_value := NULL;
      legal_unit_id_value := NULL;
      enterprise_id_value := OLD.id;
      valid_after_value := NULL;
      valid_from_value := NULL;
      valid_to_value := NULL;
    WHEN 'activity','location','contact','stat_for_unit' THEN
      establishment_id_value := OLD.establishment_id;
      legal_unit_id_value := OLD.legal_unit_id;
      enterprise_id_value := NULL;
      valid_after_value := OLD.valid_after;
      valid_from_value := OLD.valid_from;
      valid_to_value := OLD.valid_to;
    ELSE
      RAISE EXCEPTION 'Unexpected table name in delete trigger: %', TG_TABLE_NAME;
  END CASE;

  -- Build the payload
  payload := jsonb_build_object(
    'command', 'deleted_row',
    'table_name', TG_TABLE_NAME,
    'id', OLD.id,
    'establishment_id', establishment_id_value,
    'legal_unit_id', legal_unit_id_value,
    'enterprise_id', enterprise_id_value,
    'valid_after', valid_after_value,
    'valid_from', valid_from_value,
    'valid_to', valid_to_value
  );

  -- Send notification
  PERFORM worker.notify(payload);

  RETURN OLD;
END;
$function$;

CREATE PROCEDURE worker.setup()
LANGUAGE plpgsql
AS $procedure$
DECLARE
  table_name text;
BEGIN
  FOR table_name IN
    SELECT unnest(ARRAY[
      'enterprise',
      'legal_unit',
      'establishment',
      'activity',
      'location',
      'contact',
      'stat_for_unit'
    ])
  LOOP
    -- Create delete trigger
    IF NOT EXISTS (
      SELECT 1 FROM pg_trigger
      WHERE tgname = table_name || '_deletes_trigger'
      AND tgrelid = ('public.' || table_name)::regclass
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

    -- Create changes trigger for inserts and updates
    IF NOT EXISTS (
      SELECT 1 FROM pg_trigger
      WHERE tgname = table_name || '_changes_trigger'
      AND tgrelid = ('public.' || table_name)::regclass
    ) THEN
      EXECUTE format(
        'CREATE TRIGGER %I
        AFTER INSERT OR UPDATE ON public.%I
        FOR EACH STATEMENT
        EXECUTE FUNCTION worker.notify_worker_about_changes()',
        table_name || '_changes_trigger',
        table_name
      );
    END IF;
  END LOOP;
END;
$procedure$;

CREATE PROCEDURE worker.teardown()
LANGUAGE plpgsql
AS $procedure$
DECLARE
  table_name text;
BEGIN
  FOR table_name IN
    SELECT unnest(ARRAY[
      'enterprise',
      'legal_unit',
      'establishment',
      'activity',
      'location',
      'contact',
      'stat_for_unit'
    ])
  LOOP
    -- Drop delete trigger
    EXECUTE format(
      'DROP TRIGGER IF EXISTS %I ON public.%I',
      table_name || '_deletes_trigger',
      table_name
    );

    -- Drop changes trigger
    EXECUTE format(
      'DROP TRIGGER IF EXISTS %I ON public.%I',
      table_name || '_changes_trigger',
      table_name
    );
  END LOOP;
END;
$procedure$;

-- Call setup to create triggers
CALL worker.setup();

END;
