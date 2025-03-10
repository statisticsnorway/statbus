-- Migration 20250213100637: create worker
BEGIN;

CREATE SCHEMA "worker";

-- Grant necessary permissions
GRANT USAGE ON SCHEMA worker TO authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA worker TO authenticated;

CREATE TABLE worker.last_processed (
  table_name text PRIMARY KEY,
  transaction_id bigint NOT NULL
);


-- Create worker.queue_registry with a concurrent (true|false)
-- Notice that presence of queues is required for logically dependent tasks,
-- where a task can produce multiple new tasks, but they must all be processed in order.
CREATE TABLE worker.queue_registry (
  queue TEXT PRIMARY KEY,
  concurrent BOOLEAN NOT NULL DEFAULT false,
  description TEXT
);

INSERT INTO worker.queue_registry (queue, concurrent, description)
VALUES ('analytics', false, 'Serial qeueue for analysing and deriving data')
,('maintenance', false, 'Serial queue for maintenance tasks');

-- Create command registry table for dynamic command handling
CREATE TABLE worker.command_registry (
  command TEXT PRIMARY KEY,
  handler_function TEXT NOT NULL,
  description TEXT,
  queue TEXT NOT NULL REFERENCES worker.queue_registry(queue),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- Create index for efficient queue lookups
CREATE INDEX idx_command_registry_queue ON worker.command_registry(queue);


CREATE TYPE worker.task_state AS ENUM (
  'pending',
  'processing',
  'completed',
  'failed'
);


-- Create unlogged tasks table for batch processing
CREATE UNLOGGED TABLE worker.tasks (
  id BIGSERIAL PRIMARY KEY,
  command TEXT NOT NULL REFERENCES worker.command_registry(command),
  created_at TIMESTAMPTZ DEFAULT now(),
  state worker.task_state DEFAULT 'pending',
  processed_at TIMESTAMPTZ,
  error_message TEXT,
  scheduled_at TIMESTAMPTZ, -- When this task should be processed, if delayed.
  payload JSONB,
  CONSTRAINT "consistent_command_in_payload" CHECK (command = payload->>'command'),
  CONSTRAINT check_payload_type
  CHECK (payload IS NULL OR jsonb_typeof(payload) = 'object' OR jsonb_typeof(payload) = 'null')
);

-- Create partial unique indexes for each command type using payload fields
-- For check_table: deduplicate by table_name
CREATE UNIQUE INDEX idx_tasks_check_table_dedup
ON worker.tasks ((payload->>'table_name'))
WHERE command = 'check_table' AND state = 'pending'::worker.task_state;

-- For deleted_row: deduplicate by table_name and unit IDs
CREATE UNIQUE INDEX idx_tasks_deleted_row_dedup
ON worker.tasks (
  (payload->>'table_name'),
  COALESCE((payload->>'establishment_id')::int, 0),
  COALESCE((payload->>'legal_unit_id')::int, 0),
  COALESCE((payload->>'enterprise_id')::int, 0)
)
WHERE command = 'deleted_row' AND state = 'pending'::worker.task_state;

-- For refresh_derived_data: only one pending task at a time
CREATE UNIQUE INDEX idx_tasks_refresh_derived_data_dedup
ON worker.tasks (command)
WHERE command = 'refresh_derived_data' AND state = 'pending'::worker.task_state;

-- For task_cleanup: only one pending task at a time
CREATE UNIQUE INDEX idx_tasks_task_cleanup_dedup
ON worker.tasks (command)
WHERE command = 'task_cleanup' AND state = 'pending'::worker.task_state;

-- Create statistical unit refresh function
CREATE FUNCTION worker.statistical_unit_refresh_for_ids(
  p_establishment_ids int[] DEFAULT NULL,
  p_legal_unit_ids int[] DEFAULT NULL,
  p_enterprise_ids int[] DEFAULT NULL,
  p_valid_after date DEFAULT NULL,
  p_valid_to date DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
AS $statistical_unit_refresh_for_ids$
DECLARE
  v_affected_count int;
BEGIN
  -- Create a temporary table to store the new data to ensure consistency
  CREATE TEMPORARY TABLE temp_new_units ON COMMIT DROP AS
  SELECT * FROM public.statistical_unit_def AS sud
  WHERE (
    (sud.unit_type = 'establishment' AND sud.unit_id = ANY(p_establishment_ids)) OR
    (sud.unit_type = 'legal_unit' AND sud.unit_id = ANY(p_legal_unit_ids)) OR
    (sud.unit_type = 'enterprise' AND sud.unit_id = ANY(p_enterprise_ids)) OR
    sud.establishment_ids && p_establishment_ids OR
    sud.legal_unit_ids && p_legal_unit_ids OR
    sud.enterprise_ids && p_enterprise_ids
  )
  AND daterange(sud.valid_after, sud.valid_to, '(]') &&
      daterange(COALESCE(p_valid_after, '-infinity'::date),
               COALESCE(p_valid_to, 'infinity'::date), '(]');

  -- Delete affected entries
  DELETE FROM public.statistical_unit AS su
  WHERE (
    (su.unit_type = 'establishment' AND su.unit_id = ANY(p_establishment_ids)) OR
    (su.unit_type = 'legal_unit' AND su.unit_id = ANY(p_legal_unit_ids)) OR
    (su.unit_type = 'enterprise' AND su.unit_id = ANY(p_enterprise_ids)) OR
    su.establishment_ids && p_establishment_ids OR
    su.legal_unit_ids && p_legal_unit_ids OR
    su.enterprise_ids && p_enterprise_ids
  )
  AND daterange(su.valid_after, su.valid_to, '(]') &&
      daterange(COALESCE(p_valid_after, '-infinity'::date),
               COALESCE(p_valid_to, 'infinity'::date), '(]');

  -- Insert new entries from the temporary table with ON CONFLICT DO UPDATE
  -- This ensures all fields are updated when there's a conflict
  INSERT INTO public.statistical_unit
  SELECT * FROM temp_new_units
  ON CONFLICT (valid_from, valid_to, unit_type, unit_id) DO UPDATE SET
    external_idents = EXCLUDED.external_idents,
    name = EXCLUDED.name,
    birth_date = EXCLUDED.birth_date,
    death_date = EXCLUDED.death_date,
    search = EXCLUDED.search,
    primary_activity_category_id = EXCLUDED.primary_activity_category_id,
    primary_activity_category_path = EXCLUDED.primary_activity_category_path,
    primary_activity_category_code = EXCLUDED.primary_activity_category_code,
    secondary_activity_category_id = EXCLUDED.secondary_activity_category_id,
    secondary_activity_category_path = EXCLUDED.secondary_activity_category_path,
    secondary_activity_category_code = EXCLUDED.secondary_activity_category_code,
    activity_category_paths = EXCLUDED.activity_category_paths,
    sector_id = EXCLUDED.sector_id,
    sector_path = EXCLUDED.sector_path,
    sector_code = EXCLUDED.sector_code,
    sector_name = EXCLUDED.sector_name,
    data_source_ids = EXCLUDED.data_source_ids,
    data_source_codes = EXCLUDED.data_source_codes,
    legal_form_id = EXCLUDED.legal_form_id,
    legal_form_code = EXCLUDED.legal_form_code,
    legal_form_name = EXCLUDED.legal_form_name,
    physical_address_part1 = EXCLUDED.physical_address_part1,
    physical_address_part2 = EXCLUDED.physical_address_part2,
    physical_address_part3 = EXCLUDED.physical_address_part3,
    physical_postcode = EXCLUDED.physical_postcode,
    physical_postplace = EXCLUDED.physical_postplace,
    physical_region_id = EXCLUDED.physical_region_id,
    physical_region_path = EXCLUDED.physical_region_path,
    physical_region_code = EXCLUDED.physical_region_code,
    physical_country_id = EXCLUDED.physical_country_id,
    physical_country_iso_2 = EXCLUDED.physical_country_iso_2,
    physical_latitude = EXCLUDED.physical_latitude,
    physical_longitude = EXCLUDED.physical_longitude,
    physical_altitude = EXCLUDED.physical_altitude,
    postal_address_part1 = EXCLUDED.postal_address_part1,
    postal_address_part2 = EXCLUDED.postal_address_part2,
    postal_address_part3 = EXCLUDED.postal_address_part3,
    postal_postcode = EXCLUDED.postal_postcode,
    postal_postplace = EXCLUDED.postal_postplace,
    postal_region_id = EXCLUDED.postal_region_id,
    postal_region_path = EXCLUDED.postal_region_path,
    postal_region_code = EXCLUDED.postal_region_code,
    postal_country_id = EXCLUDED.postal_country_id,
    postal_country_iso_2 = EXCLUDED.postal_country_iso_2,
    postal_latitude = EXCLUDED.postal_latitude,
    postal_longitude = EXCLUDED.postal_longitude,
    postal_altitude = EXCLUDED.postal_altitude,
    web_address = EXCLUDED.web_address,
    email_address = EXCLUDED.email_address,
    phone_number = EXCLUDED.phone_number,
    landline = EXCLUDED.landline,
    mobile_number = EXCLUDED.mobile_number,
    fax_number = EXCLUDED.fax_number,
    status_id = EXCLUDED.status_id,
    status_code = EXCLUDED.status_code,
    include_unit_in_reports = EXCLUDED.include_unit_in_reports,
    invalid_codes = EXCLUDED.invalid_codes,
    has_legal_unit = EXCLUDED.has_legal_unit,
    establishment_ids = EXCLUDED.establishment_ids,
    legal_unit_ids = EXCLUDED.legal_unit_ids,
    enterprise_ids = EXCLUDED.enterprise_ids,
    stats = EXCLUDED.stats,
    stats_summary = EXCLUDED.stats_summary,
    establishment_count = EXCLUDED.establishment_count,
    legal_unit_count = EXCLUDED.legal_unit_count,
    enterprise_count = EXCLUDED.enterprise_count,
    tag_paths = EXCLUDED.tag_paths;

  -- Drop the temporary table
  DROP TABLE temp_new_units;

  -- Enqueue refresh derived data task
  PERFORM worker.enqueue_refresh_derived_data(
    p_valid_after := p_valid_after,
    p_valid_to := p_valid_to
  );
END;
$statistical_unit_refresh_for_ids$;

-- Create command handlers
-- Command handler for refresh_derived_data
-- Refreshes all derived data tables within the specified date range
-- This includes activity categories, regions, sectors, and statistical unit facets
CREATE FUNCTION worker.command_refresh_derived_data(
    payload JSONB
)
RETURNS void
SECURITY DEFINER
LANGUAGE plpgsql
AS $function$
DECLARE
    v_valid_after date = COALESCE((payload->>'valid_after')::date, '-infinity'::DATE);
    v_valid_to date = COALESCE((payload->>'valid_to')::date, 'infinity'::DATE);
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

-- Command handler for check_table
-- Processes changes in a table since a specific transaction ID
-- and refreshes affected statistical units
CREATE FUNCTION worker.command_check_table(
    payload JSONB
)
RETURNS void
SECURITY DEFINER
LANGUAGE plpgsql
AS $function$
DECLARE
    v_table_name text = payload->>'table_name';
    v_transaction_id bigint = (payload->>'transaction_id')::bigint;
DECLARE
  v_current_txid bigint;
  v_unit_id_columns text;
  v_valid_columns text;
  v_changed_rows record;
  v_establishment_ids int[] := ARRAY[]::int[];
  v_legal_unit_ids int[] := ARRAY[]::int[];
  v_enterprise_ids int[] := ARRAY[]::int[];
  v_valid_after date := '-infinity'::date;
  v_valid_to date := 'infinity'::date;
BEGIN
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
     WHERE age(xmin) <= age($1::text::xid)
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
      p_establishment_ids := v_establishment_ids,
      p_legal_unit_ids := v_legal_unit_ids,
      p_enterprise_ids := v_enterprise_ids,
      p_valid_after := v_valid_after,
      p_valid_to := v_valid_to
    );
  END IF;

  -- Record the check request in last_processed
  INSERT INTO worker.last_processed (table_name, transaction_id)
  VALUES (v_table_name, v_current_txid)
  ON CONFLICT (table_name)
  DO UPDATE SET transaction_id = EXCLUDED.transaction_id;
END;
$function$;

-- Command handler for deleted_row
-- Handles the deletion of rows from statistical unit tables
-- by refreshing affected units and their relationships
CREATE FUNCTION worker.command_deleted_row(
    payload JSONB
)
RETURNS void
SECURITY DEFINER
LANGUAGE plpgsql
AS $function$
DECLARE
    v_table_name text = payload->>'table_name';
    v_establishment_id int = (payload->>'establishment_id')::int;
    v_legal_unit_id int = (payload->>'legal_unit_id')::int;
    v_enterprise_id int = (payload->>'enterprise_id')::int;
    v_valid_after date = (payload->>'valid_after')::date;
    v_valid_to date = (payload->>'valid_to')::date;
BEGIN
  -- Handle deleted row by refreshing affected units
  PERFORM worker.statistical_unit_refresh_for_ids(
    p_establishment_ids := ARRAY[v_establishment_id],
    p_legal_unit_ids := ARRAY[v_legal_unit_id],
    p_enterprise_ids := ARRAY[v_enterprise_id],
    p_valid_after := v_valid_after,
    p_valid_to := v_valid_to
  );
END;
$function$;


-- Worker system operates in a single mode:
--
-- Background Mode:
--   - Commands sent via PostgreSQL NOTIFY/LISTEN
--   - Requires Crystal worker process listening for notifications
--   - Asynchronous processing outside transaction boundaries
--   - Suitable for production deployment
--
-- For testing:
--   - Tests use transaction ABORT to roll back changes
--   - No special mode needed for testing
--   - Tasks are created but rolled back with the test transaction
--   - Tests must manually call worker.process_tasks() to simulate worker processing
--   - Example test pattern:
--     BEGIN;
--     -- Create test data and trigger worker tasks
--     INSERT INTO some_table VALUES (...);
--     -- Manually process tasks that would normally be handled by the worker
--     SELECT * FROM worker.process_tasks();
--     -- Verify results
--     SELECT * FROM affected_table WHERE ...;
--     -- Roll back all changes including tasks
--     ROLLBACK;
--


-- Functions to enqueue tasks with deduplication

-- For check_table command
CREATE FUNCTION worker.enqueue_check_table(
  p_table_name TEXT,
  p_transaction_id BIGINT
) RETURNS BIGINT
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
      to_jsonb(GREATEST(
        (worker.tasks.payload->>'transaction_id')::bigint,
        (EXCLUDED.payload->>'transaction_id')::bigint
      ))
    ),
    state = 'pending'::worker.task_state,
    processed_at = NULL,
    error_message = NULL
  RETURNING id INTO v_task_id;

  -- Notify worker of new task with queue information
  PERFORM pg_notify('worker_tasks', 'analytics');

  RETURN v_task_id;
END;
$function$;

-- For deleted_row command
CREATE FUNCTION worker.enqueue_deleted_row(
  p_table_name TEXT,
  p_establishment_id INT DEFAULT NULL,
  p_legal_unit_id INT DEFAULT NULL,
  p_enterprise_id INT DEFAULT NULL,
  p_valid_after DATE DEFAULT NULL,
  p_valid_to DATE DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql
AS $function$
DECLARE
  v_task_id BIGINT;
  v_payload JSONB;
BEGIN
  -- Create payload
  v_payload := jsonb_build_object(
    'table_name', p_table_name,
    'establishment_id', p_establishment_id,
    'legal_unit_id', p_legal_unit_id,
    'enterprise_id', p_enterprise_id,
    'valid_after', p_valid_after,
    'valid_to', p_valid_to
  );

  INSERT INTO worker.tasks (
    command, payload
  ) VALUES ('deleted_row', v_payload)
  ON CONFLICT (
    (payload->>'table_name'),
    COALESCE((payload->>'establishment_id')::int, 0),
    COALESCE((payload->>'legal_unit_id')::int, 0),
    COALESCE((payload->>'enterprise_id')::int, 0)
  )
  WHERE command = 'deleted_row' AND state = 'pending'::worker.task_state
  DO UPDATE SET
    payload = jsonb_set(
      jsonb_set(
        worker.tasks.payload,
        '{valid_after}',
        to_jsonb(LEAST(
          (worker.tasks.payload->>'valid_after')::date,
          (EXCLUDED.payload->>'valid_after')::date
        ))
      ),
      '{valid_to}',
      to_jsonb(GREATEST(
        (worker.tasks.payload->>'valid_to')::date,
        (EXCLUDED.payload->>'valid_to')::date
      ))
    ),
    state = 'pending'::worker.task_state,
    processed_at = NULL,
    error_message = NULL
  RETURNING id INTO v_task_id;

  PERFORM pg_notify('worker_tasks', 'analytics');

  RETURN v_task_id;
END;
$function$;

-- For refresh_derived_data command
CREATE FUNCTION worker.enqueue_refresh_derived_data(
  p_valid_after DATE DEFAULT NULL,
  p_valid_to DATE DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql
AS $function$
DECLARE
  v_task_id BIGINT;
  v_valid_after DATE := COALESCE(p_valid_after, '-infinity'::DATE);
  v_valid_to DATE := COALESCE(p_valid_to, 'infinity'::DATE);
  v_payload JSONB;
BEGIN
  -- Create payload
  v_payload := jsonb_build_object(
    'valid_after', v_valid_after,
    'valid_to', v_valid_to
  );

  INSERT INTO worker.tasks (
    command, payload
  ) VALUES ('refresh_derived_data', v_payload)
  ON CONFLICT (command) WHERE command = 'refresh_derived_data' AND state = 'pending'::worker.task_state
  DO UPDATE SET
    payload = jsonb_set(
      jsonb_set(
        worker.tasks.payload,
        '{valid_after}',
        to_jsonb(LEAST(
          (worker.tasks.payload->>'valid_after')::date,
          v_valid_after
        ))
      ),
      '{valid_to}',
      to_jsonb(GREATEST(
        (worker.tasks.payload->>'valid_to')::date,
        v_valid_to
      ))
    ),
    state = 'pending'::worker.task_state,
    processed_at = NULL,
    error_message = NULL
  RETURNING id INTO v_task_id;

  PERFORM pg_notify('worker_tasks', 'analytics');

  RETURN v_task_id;
END;
$function$;


-- Create unified task processing function
-- Processes pending tasks in batches with time limits
-- Parameters:
--   batch_size: Maximum number of tasks to process in one call
--   max_runtime_ms: Maximum runtime in milliseconds before stopping
--   queue: Process only tasks in this queue (NULL for all queues)
-- Returns:
--   id: The task ID that was processed
--   command: The command that was executed
--   duration_ms: How long the task took to process in milliseconds
--   success: Whether the task succeeded (TRUE) or failed (FALSE)
--   error_message: Error message if task failed, NULL otherwise
CREATE FUNCTION worker.process_tasks(
  p_batch_size INT DEFAULT NULL,
  p_max_runtime_ms INT DEFAULT NULL,
  p_queue TEXT DEFAULT NULL
) RETURNS TABLE (
  id BIGINT,
  command TEXT,
  queue TEXT,
  duration_ms NUMERIC,
  success BOOLEAN,
  error_message TEXT
)
LANGUAGE plpgsql
AS $function$
DECLARE
  task_record RECORD;
  start_time TIMESTAMPTZ;
  batch_start_time TIMESTAMPTZ;
  elapsed_ms NUMERIC;
  processed_count INT := 0;
BEGIN
  batch_start_time := clock_timestamp();

  -- Process tasks in a loop until we hit time limit or run out of tasks
  LOOP
    -- Claim a task with FOR UPDATE SKIP LOCKED to prevent concurrent processing
    SELECT t.*, cr.handler_function, cr.queue INTO task_record
    FROM worker.tasks t
    JOIN worker.command_registry cr ON t.command = cr.command
    WHERE t.state = 'pending'::worker.task_state
      AND (t.scheduled_at IS NULL OR t.scheduled_at <= clock_timestamp())
      AND (p_queue IS NULL OR cr.queue = p_queue)
    ORDER BY
      CASE WHEN t.scheduled_at IS NULL THEN 0 ELSE 1 END, -- Non-scheduled tasks next
      t.scheduled_at, -- Then by scheduled time (earliest first)
      t.id            -- Then by creation sequence
    LIMIT 1
    FOR UPDATE OF t SKIP LOCKED;

    -- Exit if no more tasks or time limit reached (if p_max_runtime_ms is set)
    IF NOT FOUND THEN
      RAISE DEBUG 'Exiting worker loop: No more pending tasks found';
      EXIT;
    ELSIF p_max_runtime_ms IS NOT NULL AND
          EXTRACT(EPOCH FROM (clock_timestamp() - batch_start_time)) * 1000 > p_max_runtime_ms THEN
      RAISE DEBUG 'Exiting worker loop: Time limit of % ms reached (elapsed: % ms)',
        p_max_runtime_ms,
        EXTRACT(EPOCH FROM (clock_timestamp() - batch_start_time)) * 1000;
      EXIT;
    END IF;

    -- Process the task
    DECLARE
      error_details TEXT;
      v_pg_exception_detail TEXT;
      v_pg_exception_hint TEXT;
      v_pg_exception_context TEXT;
    BEGIN

      start_time := clock_timestamp();

      -- Mark as processing
      UPDATE worker.tasks AS t
      SET state = 'processing'::worker.task_state
      WHERE t.id = task_record.id;

      -- Process using dynamic dispatch with payload for all commands
      IF task_record.handler_function IS NOT NULL THEN
        -- Execute the handler function with the payload
        EXECUTE format('SELECT %s($1)', task_record.handler_function)
        USING task_record.payload;
      ELSE
        RAISE EXCEPTION 'No handler function found for command: %', task_record.command;
      END IF;

      -- Mark as completed
      UPDATE worker.tasks AS t
      SET state = 'completed'::worker.task_state,
          processed_at = clock_timestamp()
      WHERE t.id = task_record.id;

      elapsed_ms := EXTRACT(EPOCH FROM (clock_timestamp() - start_time)) * 1000;

      -- Increment processed count
      processed_count := processed_count + 1;

      -- Return success result
      RETURN QUERY SELECT
        task_record.id,           -- id
        task_record.command,      -- command
        task_record.queue,        -- queue
        elapsed_ms,               -- duration_ms
        TRUE,                     -- success
        NULL::TEXT;               -- error_message

    EXCEPTION WHEN OTHERS THEN
      elapsed_ms := EXTRACT(EPOCH FROM (clock_timestamp() - start_time)) * 1000;

      GET STACKED DIAGNOSTICS
        error_details = MESSAGE_TEXT,
        v_pg_exception_detail = PG_EXCEPTION_DETAIL,
        v_pg_exception_hint = PG_EXCEPTION_HINT,
        v_pg_exception_context = PG_EXCEPTION_CONTEXT;

      error_details := format(
        'Error: %s%sContext: %s%sDetail: %s%sHint: %s',
        error_details,
        E'\n',
        v_pg_exception_context,
        E'\n',
        COALESCE(v_pg_exception_detail, ''),
        E'\n',
        COALESCE(v_pg_exception_hint, '')
      );
      -- Mark as failed with detailed error information
      UPDATE worker.tasks AS t
      SET state = 'failed'::worker.task_state,
          processed_at = clock_timestamp(),
          error_message = error_details
      WHERE t.id = task_record.id;

      -- Increment processed count even for failures
      processed_count := processed_count + 1;

      -- Return failure result with detailed error information
      RETURN QUERY SELECT
        task_record.id,           -- id
        task_record.command,      -- command
        task_record.queue,        -- queue (from command_registry join)
        elapsed_ms,               -- duration_ms
        FALSE,                    -- success
        error_details;            -- error_message
    END;

    -- Check if we've hit the batch size limit (if p_batch_size is set)
    IF p_batch_size IS NOT NULL AND processed_count >= p_batch_size THEN
      RAISE DEBUG 'Exiting worker loop: Batch size limit of % reached', p_batch_size;
      EXIT;
    END IF;
  END LOOP;
END;
$function$;

-- Register built-in commands
INSERT INTO worker.command_registry (queue, command, handler_function, description)
VALUES
  ('analytics', 'check_table', 'worker.command_check_table', 'Process changes in a table since a specific transaction ID'),
  ('analytics', 'deleted_row', 'worker.command_deleted_row', 'Handle deletion of rows from statistical unit tables'),
  ('analytics', 'refresh_derived_data', 'worker.command_refresh_derived_data', 'Refresh all derived data tables'),
  ('maintenance', 'task_cleanup', 'worker.command_task_cleanup', 'Clean up old completed and failed tasks');


-- Add foreign key constraint to ensure command exists in command registry
ALTER TABLE worker.tasks ADD CONSTRAINT fk_tasks_command
FOREIGN KEY (command) REFERENCES worker.command_registry(command);

-- Create index for scheduled tasks
CREATE INDEX idx_tasks_scheduled_at ON worker.tasks (scheduled_at)
WHERE state = 'pending'::worker.task_state AND scheduled_at IS NOT NULL;


-- Create command handler for task_cleanup
-- Removes completed and failed tasks older than the specified retention period
CREATE FUNCTION worker.command_task_cleanup(
    payload JSONB
)
RETURNS void
SECURITY DEFINER
LANGUAGE plpgsql
AS $function$
DECLARE
    v_completed_retention_days INT = COALESCE((payload->>'completed_retention_days')::int, 7);
    v_failed_retention_days INT = COALESCE((payload->>'failed_retention_days')::int, 30);
BEGIN
    -- Delete completed tasks older than retention period
    DELETE FROM worker.tasks
    WHERE state = 'completed'::worker.task_state
      AND processed_at < (now() - (v_completed_retention_days || ' days')::interval);

    -- Delete failed tasks older than retention period
    DELETE FROM worker.tasks
    WHERE state = 'failed'::worker.task_state
      AND processed_at < (now() - (v_failed_retention_days || ' days')::interval);

    -- Schedule to run again in 24 hours
    PERFORM worker.enqueue_task_cleanup(
      v_completed_retention_days,
      v_failed_retention_days
    );
END;
$function$;

-- For task_cleanup command
CREATE FUNCTION worker.enqueue_task_cleanup(
  p_completed_retention_days INT DEFAULT 7,
  p_failed_retention_days INT DEFAULT 30
) RETURNS BIGINT
LANGUAGE plpgsql
AS $function$
DECLARE
  v_task_id BIGINT;
  v_payload JSONB;
BEGIN
  -- Create payload
  v_payload := jsonb_build_object(
    'completed_retention_days', p_completed_retention_days,
    'failed_retention_days', p_failed_retention_days
  );

  -- Insert with ON CONFLICT for this specific command type
  INSERT INTO worker.tasks (
    command,
    payload,
    scheduled_at
  ) VALUES (
    'task_cleanup',
    v_payload,
    now() + interval '24 hours'
  )
  ON CONFLICT (command) WHERE command = 'task_cleanup' AND state = 'pending'::worker.task_state
  DO UPDATE SET
    state = 'pending'::worker.task_state,
    processed_at = NULL,
    error_message = NULL
  RETURNING id INTO v_task_id;

  -- Notify worker of new task with queue information
  PERFORM pg_notify('worker_tasks', 'maintenance');

  RETURN v_task_id;
END;
$function$;

-- Create function to notify about queue changes
CREATE FUNCTION worker.notify_worker_queue_change()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  PERFORM pg_notify('worker_queue_change', NEW.queue);
  RETURN NEW;
END;
$function$;

-- Create trigger for command registry changes
CREATE TRIGGER command_registry_queue_change_trigger
AFTER INSERT OR UPDATE OF queue ON worker.command_registry
FOR EACH ROW
EXECUTE FUNCTION worker.notify_worker_queue_change();

-- Create tasks table access
GRANT SELECT ON worker.last_processed TO authenticated;
GRANT SELECT ON worker.command_registry TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON worker.tasks TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE worker.tasks_id_seq TO authenticated;


-- Create trigger functions for changes and deletes
CREATE FUNCTION worker.notify_worker_about_changes()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  PERFORM worker.enqueue_check_table(
    p_table_name := TG_TABLE_NAME,
    p_transaction_id := txid_current()
  );
  RETURN NULL;
END;
$function$;

CREATE FUNCTION worker.notify_worker_about_deletes()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
  establishment_id_value int;
  legal_unit_id_value int;
  enterprise_id_value int;
  valid_after_value date;
  valid_to_value date;
BEGIN
  -- Set values based on table name
  CASE TG_TABLE_NAME
    WHEN 'establishment' THEN
      establishment_id_value := OLD.id;
      legal_unit_id_value := OLD.legal_unit_id;
      enterprise_id_value := OLD.enterprise_id;
      valid_after_value := OLD.valid_after;
      valid_to_value := OLD.valid_to;
    WHEN 'legal_unit' THEN
      establishment_id_value := NULL;
      legal_unit_id_value := OLD.id;
      enterprise_id_value := OLD.enterprise_id;
      valid_after_value := OLD.valid_after;
      valid_to_value := OLD.valid_to;
    WHEN 'enterprise' THEN
      establishment_id_value := NULL;
      legal_unit_id_value := NULL;
      enterprise_id_value := OLD.id;
      valid_after_value := NULL;
      valid_to_value := NULL;
    WHEN 'activity','location','contact','stat_for_unit' THEN
      establishment_id_value := OLD.establishment_id;
      legal_unit_id_value := OLD.legal_unit_id;
      enterprise_id_value := NULL;
      valid_after_value := OLD.valid_after;
      valid_to_value := OLD.valid_to;
    ELSE
      RAISE EXCEPTION 'Unexpected table name in delete trigger: %', TG_TABLE_NAME;
  END CASE;

  -- Enqueue deleted row task
  PERFORM worker.enqueue_deleted_row(
    p_table_name := TG_TABLE_NAME,
    p_establishment_id := establishment_id_value,
    p_legal_unit_id := legal_unit_id_value,
    p_enterprise_id := enterprise_id_value,
    p_valid_after := valid_after_value,
    p_valid_to := valid_to_value
  );

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

  -- Create the initial cleanup_tasks task to run daily
  PERFORM worker.enqueue_task_cleanup();
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
