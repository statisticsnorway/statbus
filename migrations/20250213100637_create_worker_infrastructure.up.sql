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
  handler_procedure TEXT NOT NULL,
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

CREATE SEQUENCE IF NOT EXISTS public.worker_task_priority_seq AS BIGINT;

-- Create tasks table for batch processing
CREATE TABLE worker.tasks (
  id BIGSERIAL PRIMARY KEY,
  command TEXT NOT NULL REFERENCES worker.command_registry(command),
  priority BIGINT DEFAULT nextval('public.worker_task_priority_seq'),
  created_at TIMESTAMPTZ DEFAULT now(),
  state worker.task_state DEFAULT 'pending',
  processed_at TIMESTAMPTZ,
  duration_ms NUMERIC,
  error TEXT,
  scheduled_at TIMESTAMPTZ, -- When this task should be processed, if delayed.
  payload JSONB,
  CONSTRAINT "consistent_command_in_payload" CHECK (command = payload->>'command'),
  CONSTRAINT check_payload_type
  CHECK (payload IS NULL OR jsonb_typeof(payload) = 'object' OR jsonb_typeof(payload) = 'null'),
  CONSTRAINT error_required_when_failed CHECK (
    CASE state
    WHEN 'failed'::worker.task_state THEN error IS NOT NULL
    ELSE error IS NULL
    END
  )
);

-- Create partial unique indexes for each command type using payload fields
-- For check_table: deduplicate by table_name
CREATE UNIQUE INDEX idx_tasks_check_table_dedup
ON worker.tasks ((payload->>'table_name'))
WHERE command = 'check_table' AND state = 'pending'::worker.task_state;

-- For deleted_row: deduplicate by table_name only
CREATE UNIQUE INDEX idx_tasks_deleted_row_dedup
ON worker.tasks ((payload->>'table_name'))
WHERE command = 'deleted_row' AND state = 'pending'::worker.task_state;

-- For statistical_unit_refresh: only one pending task at a time
CREATE UNIQUE INDEX idx_tasks_statistical_unit_refresh_dedup
ON worker.tasks (command)
WHERE command = 'statistical_unit_refresh' AND state = 'pending'::worker.task_state;

-- For timesegments_refresh: only one pending task at a time
CREATE UNIQUE INDEX idx_tasks_timesegments_refresh_dedup
ON worker.tasks (command)
WHERE command = 'timesegments_refresh' AND state = 'pending'::worker.task_state;

-- For timeline_establishment_refresh: only one pending task at a time
CREATE UNIQUE INDEX idx_tasks_timeline_establishment_refresh_dedup
ON worker.tasks (command)
WHERE command = 'timeline_establishment_refresh' AND state = 'pending'::worker.task_state;

-- For timeline_legal_unit_refresh: only one pending task at a time
CREATE UNIQUE INDEX idx_tasks_timeline_legal_unit_refresh_dedup
ON worker.tasks (command)
WHERE command = 'timeline_legal_unit_refresh' AND state = 'pending'::worker.task_state;

-- For timeline_enterprise_refresh: only one pending task at a time
CREATE UNIQUE INDEX idx_tasks_timeline_enterprise_refresh_dedup
ON worker.tasks (command)
WHERE command = 'timeline_enterprise_refresh' AND state = 'pending'::worker.task_state;

-- For refresh_derived_data: only one pending task at a time
CREATE UNIQUE INDEX idx_tasks_refresh_derived_data_dedup
ON worker.tasks (command)
WHERE command = 'refresh_derived_data' AND state = 'pending'::worker.task_state;

-- For task_cleanup: only one pending task at a time
CREATE UNIQUE INDEX idx_tasks_task_cleanup_dedup
ON worker.tasks (command)
WHERE command = 'task_cleanup' AND state = 'pending'::worker.task_state;

-- Create statistical unit refresh function
CREATE FUNCTION worker.statistical_unit_refresh(
  p_establishment_ids int[] DEFAULT NULL,
  p_legal_unit_ids int[] DEFAULT NULL,
  p_enterprise_ids int[] DEFAULT NULL,
  p_valid_after date DEFAULT NULL,
  p_valid_to date DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
AS $statistical_unit_refresh$
DECLARE
  v_affected_count int;
BEGIN
  -- Create a temporary table to store the new data to ensure consistency
  CREATE TEMPORARY TABLE temp_statistical_unit AS
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

  -- Delete any data that would overlap with the new data in the temporary table
  DELETE FROM public.statistical_unit AS su
  WHERE EXISTS (
    SELECT 1 FROM temp_statistical_unit AS tnu
    WHERE su.unit_type = tnu.unit_type
    AND su.unit_id = tnu.unit_id
    AND daterange(su.valid_from, su.valid_to, '(]') &&
        daterange(tnu.valid_from, tnu.valid_to, '(]')
  );

  -- Insert new entries from the temporary table
  -- No conflict handling needed as we've deleted all potential conflicts
  INSERT INTO public.statistical_unit
  SELECT * FROM temp_statistical_unit;

  -- Drop the temporary table
  DROP TABLE temp_statistical_unit;

  -- Enqueue refresh derived data task
  PERFORM worker.enqueue_refresh_derived_data(
    p_valid_after := p_valid_after,
    p_valid_to := p_valid_to
  );
END;
$statistical_unit_refresh$;

-- Create command handler for statistical_unit_refresh
-- Refreshes statistical units based on provided IDs and date range
CREATE PROCEDURE worker.command_statistical_unit_refresh(
    payload JSONB
)
SECURITY DEFINER
LANGUAGE plpgsql
AS $procedure$
DECLARE
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
    v_valid_after date = (payload->>'valid_after')::date;
    v_valid_to date = (payload->>'valid_to')::date;
BEGIN
  -- Call the statistical unit refresh function with the extracted parameters
  PERFORM worker.statistical_unit_refresh(
    p_establishment_ids := v_establishment_ids,
    p_legal_unit_ids := v_legal_unit_ids,
    p_enterprise_ids := v_enterprise_ids,
    p_valid_after := v_valid_after,
    p_valid_to := v_valid_to
  );
END;
$procedure$;

-- Create command handlers
-- Command handler for refresh_derived_data
-- Refreshes all derived data tables within the specified date range
-- This includes activity categories, regions, sectors, and statistical unit facets
CREATE PROCEDURE worker.command_refresh_derived_data(
    payload JSONB
)
SECURITY DEFINER
LANGUAGE plpgsql
AS $procedure$
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
$procedure$;

-- Command handler for check_table
-- Processes changes in a table since a specific transaction ID
-- and refreshes affected statistical units
CREATE PROCEDURE worker.command_check_table(
    payload JSONB
)
SECURITY DEFINER
LANGUAGE plpgsql
AS $procedure$
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
    -- Enqueue timesegments refresh which will then trigger statistical unit refresh
    PERFORM worker.enqueue_timesegments_refresh(
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
$procedure$;

-- Command handler for deleted_row
-- Handles the deletion of rows from statistical unit tables
-- by refreshing affected units and their relationships
CREATE PROCEDURE worker.command_deleted_row(
    payload JSONB
)
SECURITY DEFINER
LANGUAGE plpgsql
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
    v_valid_after date = (payload->>'valid_after')::date;
    v_valid_to date = (payload->>'valid_to')::date;
BEGIN

  -- Handle deleted row by refreshing affected units
  -- First refresh timesegments which will then trigger statistical unit refresh
  PERFORM worker.enqueue_timesegments_refresh(
    p_establishment_ids := v_establishment_ids,
    p_legal_unit_ids := v_legal_unit_ids,
    p_enterprise_ids := v_enterprise_ids,
    p_valid_after := v_valid_after,
    p_valid_to := v_valid_to
  );
END;
$procedure$;


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
    priority = EXCLUDED.priority,  -- Use the new priority to push queue position
    processed_at = NULL,
    error = NULL
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
    'valid_after', p_valid_after,
    'valid_to', p_valid_to
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
      'valid_after', LEAST(
        (t.payload->>'valid_after')::date,
        (EXCLUDED.payload->>'valid_after')::date
      ),
      'valid_to', GREATEST(
        (t.payload->>'valid_to')::date,
        (EXCLUDED.payload->>'valid_to')::date
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


-- For timesegments_refresh command
CREATE FUNCTION worker.enqueue_timesegments_refresh(
  p_establishment_ids int[] DEFAULT NULL,
  p_legal_unit_ids int[] DEFAULT NULL,
  p_enterprise_ids int[] DEFAULT NULL,
  p_valid_after date DEFAULT NULL,
  p_valid_to date DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql
AS $function$
DECLARE
  v_task_id BIGINT;
  v_payload JSONB;
  v_establishment_ids INT[] := COALESCE(p_establishment_ids, ARRAY[]::INT[]);
  v_legal_unit_ids INT[] := COALESCE(p_legal_unit_ids, ARRAY[]::INT[]);
  v_enterprise_ids INT[] := COALESCE(p_enterprise_ids, ARRAY[]::INT[]);
  v_valid_after DATE := COALESCE(p_valid_after, '-infinity'::DATE);
  v_valid_to DATE := COALESCE(p_valid_to, 'infinity'::DATE);
BEGIN
  -- Create payload with arrays
  v_payload := jsonb_build_object(
    'command', 'timesegments_refresh',
    'establishment_ids', to_jsonb(v_establishment_ids),
    'legal_unit_ids', to_jsonb(v_legal_unit_ids),
    'enterprise_ids', to_jsonb(v_enterprise_ids),
    'valid_after', v_valid_after,
    'valid_to', v_valid_to
  );

  -- Create a unique index on a combination of all ID arrays and date range
  -- This ensures we only have one pending task for the same set of IDs and date range
  INSERT INTO worker.tasks AS t (
    command, payload
  ) VALUES ('timesegments_refresh', v_payload)
  ON CONFLICT (command)
  WHERE command = 'timesegments_refresh' AND state = 'pending'::worker.task_state
  DO UPDATE SET
    payload = jsonb_build_object(
      'command', 'timesegments_refresh',
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
      'valid_after', LEAST(
        (t.payload->>'valid_after')::date,
        (EXCLUDED.payload->>'valid_after')::date
      ),
      'valid_to', GREATEST(
        (t.payload->>'valid_to')::date,
        (EXCLUDED.payload->>'valid_to')::date
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

-- Create command handler for timesegments_refresh
CREATE PROCEDURE worker.command_timesegments_refresh(
    payload JSONB
)
SECURITY DEFINER
LANGUAGE plpgsql
AS $procedure$
DECLARE
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
    v_valid_after date = (payload->>'valid_after')::date;
    v_valid_to date = (payload->>'valid_to')::date;
BEGIN
  -- First refresh the timesegments
  PERFORM public.timesegments_refresh(
    p_valid_after := v_valid_after,
    p_valid_to := v_valid_to
  );

  -- Then enqueue timeline_establishment_refresh with the same parameters
  PERFORM worker.enqueue_timeline_establishment_refresh(
    p_establishment_ids := v_establishment_ids,
    p_legal_unit_ids := v_legal_unit_ids,
    p_enterprise_ids := v_enterprise_ids,
    p_valid_after := v_valid_after,
    p_valid_to := v_valid_to
  );
END;
$procedure$;

-- For timeline_establishment_refresh command
CREATE FUNCTION worker.enqueue_timeline_establishment_refresh(
  p_establishment_ids int[] DEFAULT NULL,
  p_legal_unit_ids int[] DEFAULT NULL,
  p_enterprise_ids int[] DEFAULT NULL,
  p_valid_after date DEFAULT NULL,
  p_valid_to date DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql
AS $function$
DECLARE
  v_task_id BIGINT;
  v_payload JSONB;
  v_establishment_ids INT[] := COALESCE(p_establishment_ids, ARRAY[]::INT[]);
  v_legal_unit_ids INT[] := COALESCE(p_legal_unit_ids, ARRAY[]::INT[]);
  v_enterprise_ids INT[] := COALESCE(p_enterprise_ids, ARRAY[]::INT[]);
  v_valid_after DATE := COALESCE(p_valid_after, '-infinity'::DATE);
  v_valid_to DATE := COALESCE(p_valid_to, 'infinity'::DATE);
BEGIN
  -- Create payload with arrays
  v_payload := jsonb_build_object(
    'command', 'timeline_establishment_refresh',
    'establishment_ids', to_jsonb(v_establishment_ids),
    'legal_unit_ids', to_jsonb(v_legal_unit_ids),
    'enterprise_ids', to_jsonb(v_enterprise_ids),
    'valid_after', v_valid_after,
    'valid_to', v_valid_to
  );

  -- Create a unique index on a combination of all ID arrays and date range
  -- This ensures we only have one pending task for the same set of IDs and date range
  INSERT INTO worker.tasks AS t (
    command, payload
  ) VALUES ('timeline_establishment_refresh', v_payload)
  ON CONFLICT (command)
  WHERE command = 'timeline_establishment_refresh' AND state = 'pending'::worker.task_state
  DO UPDATE SET
    payload = jsonb_build_object(
      'command', 'timeline_establishment_refresh',
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
      'valid_after', LEAST(
        (t.payload->>'valid_after')::date,
        (EXCLUDED.payload->>'valid_after')::date
      ),
      'valid_to', GREATEST(
        (t.payload->>'valid_to')::date,
        (EXCLUDED.payload->>'valid_to')::date
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

-- Create command handler for timeline_establishment_refresh
CREATE PROCEDURE worker.command_timeline_establishment_refresh(
    payload JSONB
)
SECURITY DEFINER
LANGUAGE plpgsql
AS $procedure$
DECLARE
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
    v_valid_after date = (payload->>'valid_after')::date;
    v_valid_to date = (payload->>'valid_to')::date;
BEGIN
  -- First refresh the timeline_establishment table
  PERFORM public.timeline_establishment_refresh(
    p_valid_after := v_valid_after,
    p_valid_to := v_valid_to
  );
  
  -- Then enqueue timeline_legal_unit_refresh with the same parameters
  PERFORM worker.enqueue_timeline_legal_unit_refresh(
    p_establishment_ids := v_establishment_ids,
    p_legal_unit_ids := v_legal_unit_ids,
    p_enterprise_ids := v_enterprise_ids,
    p_valid_after := v_valid_after,
    p_valid_to := v_valid_to
  );
END;
$procedure$;

-- For timeline_legal_unit_refresh command
CREATE FUNCTION worker.enqueue_timeline_legal_unit_refresh(
  p_establishment_ids int[] DEFAULT NULL,
  p_legal_unit_ids int[] DEFAULT NULL,
  p_enterprise_ids int[] DEFAULT NULL,
  p_valid_after date DEFAULT NULL,
  p_valid_to date DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql
AS $function$
DECLARE
  v_task_id BIGINT;
  v_payload JSONB;
  v_establishment_ids INT[] := COALESCE(p_establishment_ids, ARRAY[]::INT[]);
  v_legal_unit_ids INT[] := COALESCE(p_legal_unit_ids, ARRAY[]::INT[]);
  v_enterprise_ids INT[] := COALESCE(p_enterprise_ids, ARRAY[]::INT[]);
  v_valid_after DATE := COALESCE(p_valid_after, '-infinity'::DATE);
  v_valid_to DATE := COALESCE(p_valid_to, 'infinity'::DATE);
BEGIN
  -- Create payload with arrays
  v_payload := jsonb_build_object(
    'command', 'timeline_legal_unit_refresh',
    'establishment_ids', to_jsonb(v_establishment_ids),
    'legal_unit_ids', to_jsonb(v_legal_unit_ids),
    'enterprise_ids', to_jsonb(v_enterprise_ids),
    'valid_after', v_valid_after,
    'valid_to', v_valid_to
  );

  -- Create a unique index on a combination of all ID arrays and date range
  -- This ensures we only have one pending task for the same set of IDs and date range
  INSERT INTO worker.tasks AS t (
    command, payload
  ) VALUES ('timeline_legal_unit_refresh', v_payload)
  ON CONFLICT (command)
  WHERE command = 'timeline_legal_unit_refresh' AND state = 'pending'::worker.task_state
  DO UPDATE SET
    payload = jsonb_build_object(
      'command', 'timeline_legal_unit_refresh',
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
      'valid_after', LEAST(
        (t.payload->>'valid_after')::date,
        (EXCLUDED.payload->>'valid_after')::date
      ),
      'valid_to', GREATEST(
        (t.payload->>'valid_to')::date,
        (EXCLUDED.payload->>'valid_to')::date
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

-- Create command handler for timeline_legal_unit_refresh
CREATE PROCEDURE worker.command_timeline_legal_unit_refresh(
    payload JSONB
)
SECURITY DEFINER
LANGUAGE plpgsql
AS $procedure$
DECLARE
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
    v_valid_after date = (payload->>'valid_after')::date;
    v_valid_to date = (payload->>'valid_to')::date;
BEGIN
  -- First refresh the timeline_legal_unit table
  PERFORM public.timeline_legal_unit_refresh(
    p_valid_after := v_valid_after,
    p_valid_to := v_valid_to
  );
  
  -- Then enqueue timeline_enterprise_refresh with the same parameters
  PERFORM worker.enqueue_timeline_enterprise_refresh(
    p_establishment_ids := v_establishment_ids,
    p_legal_unit_ids := v_legal_unit_ids,
    p_enterprise_ids := v_enterprise_ids,
    p_valid_after := v_valid_after,
    p_valid_to := v_valid_to
  );
END;
$procedure$;

-- For timeline_enterprise_refresh command
CREATE FUNCTION worker.enqueue_timeline_enterprise_refresh(
  p_establishment_ids int[] DEFAULT NULL,
  p_legal_unit_ids int[] DEFAULT NULL,
  p_enterprise_ids int[] DEFAULT NULL,
  p_valid_after date DEFAULT NULL,
  p_valid_to date DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql
AS $function$
DECLARE
  v_task_id BIGINT;
  v_payload JSONB;
  v_establishment_ids INT[] := COALESCE(p_establishment_ids, ARRAY[]::INT[]);
  v_legal_unit_ids INT[] := COALESCE(p_legal_unit_ids, ARRAY[]::INT[]);
  v_enterprise_ids INT[] := COALESCE(p_enterprise_ids, ARRAY[]::INT[]);
  v_valid_after DATE := COALESCE(p_valid_after, '-infinity'::DATE);
  v_valid_to DATE := COALESCE(p_valid_to, 'infinity'::DATE);
BEGIN
  -- Create payload with arrays
  v_payload := jsonb_build_object(
    'command', 'timeline_enterprise_refresh',
    'establishment_ids', to_jsonb(v_establishment_ids),
    'legal_unit_ids', to_jsonb(v_legal_unit_ids),
    'enterprise_ids', to_jsonb(v_enterprise_ids),
    'valid_after', v_valid_after,
    'valid_to', v_valid_to
  );

  -- Create a unique index on a combination of all ID arrays and date range
  -- This ensures we only have one pending task for the same set of IDs and date range
  INSERT INTO worker.tasks AS t (
    command, payload
  ) VALUES ('timeline_enterprise_refresh', v_payload)
  ON CONFLICT (command)
  WHERE command = 'timeline_enterprise_refresh' AND state = 'pending'::worker.task_state
  DO UPDATE SET
    payload = jsonb_build_object(
      'command', 'timeline_enterprise_refresh',
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
      'valid_after', LEAST(
        (t.payload->>'valid_after')::date,
        (EXCLUDED.payload->>'valid_after')::date
      ),
      'valid_to', GREATEST(
        (t.payload->>'valid_to')::date,
        (EXCLUDED.payload->>'valid_to')::date
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

-- Create command handler for timeline_enterprise_refresh
CREATE PROCEDURE worker.command_timeline_enterprise_refresh(
    payload JSONB
)
SECURITY DEFINER
LANGUAGE plpgsql
AS $procedure$
DECLARE
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
    v_valid_after date = (payload->>'valid_after')::date;
    v_valid_to date = (payload->>'valid_to')::date;
BEGIN
  -- First refresh the timeline_enterprise table
  PERFORM public.timeline_enterprise_refresh(
    p_valid_after := v_valid_after,
    p_valid_to := v_valid_to
  );
  
  -- Then enqueue statistical_unit_refresh with the same parameters
  PERFORM worker.enqueue_statistical_unit_refresh(
    p_establishment_ids := v_establishment_ids,
    p_legal_unit_ids := v_legal_unit_ids,
    p_enterprise_ids := v_enterprise_ids,
    p_valid_after := v_valid_after,
    p_valid_to := v_valid_to
  );
END;
$procedure$;

-- For statistical_unit_refresh command
CREATE FUNCTION worker.enqueue_statistical_unit_refresh(
  p_establishment_ids int[] DEFAULT NULL,
  p_legal_unit_ids int[] DEFAULT NULL,
  p_enterprise_ids int[] DEFAULT NULL,
  p_valid_after date DEFAULT NULL,
  p_valid_to date DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql
AS $function$
DECLARE
  v_task_id BIGINT;
  v_payload JSONB;
  v_establishment_ids INT[] := COALESCE(p_establishment_ids, ARRAY[]::INT[]);
  v_legal_unit_ids INT[] := COALESCE(p_legal_unit_ids, ARRAY[]::INT[]);
  v_enterprise_ids INT[] := COALESCE(p_enterprise_ids, ARRAY[]::INT[]);
  v_valid_after DATE := COALESCE(p_valid_after, '-infinity'::DATE);
  v_valid_to DATE := COALESCE(p_valid_to, 'infinity'::DATE);
BEGIN
  -- Create payload with arrays
  v_payload := jsonb_build_object(
    'command', 'statistical_unit_refresh',
    'establishment_ids', to_jsonb(v_establishment_ids),
    'legal_unit_ids', to_jsonb(v_legal_unit_ids),
    'enterprise_ids', to_jsonb(v_enterprise_ids),
    'valid_after', v_valid_after,
    'valid_to', v_valid_to
  );

  -- Create a unique index on a combination of all ID arrays and date range
  -- This ensures we only have one pending task for the same set of IDs and date range
  INSERT INTO worker.tasks AS t (
    command, payload
  ) VALUES ('statistical_unit_refresh', v_payload)
  ON CONFLICT (command)
  WHERE command = 'statistical_unit_refresh' AND state = 'pending'::worker.task_state
  DO UPDATE SET
    payload = jsonb_build_object(
      'command', 'statistical_unit_refresh',
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
      'valid_after', LEAST(
        (t.payload->>'valid_after')::date,
        (EXCLUDED.payload->>'valid_after')::date
      ),
      'valid_to', GREATEST(
        (t.payload->>'valid_to')::date,
        (EXCLUDED.payload->>'valid_to')::date
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
    priority = EXCLUDED.priority,  -- Use the new priority to push queue position
    processed_at = NULL,
    error = NULL
  RETURNING id INTO v_task_id;

  PERFORM pg_notify('worker_tasks', 'analytics');

  RETURN v_task_id;
END;
$function$;


-- Create unified task processing procedure
-- Processes pending tasks in batches with time limits
-- Parameters:
--   batch_size: Maximum number of tasks to process in one call
--   max_runtime_ms: Maximum runtime in milliseconds before stopping
--   queue: Process only tasks in this queue (NULL for all queues)
CREATE PROCEDURE worker.process_tasks(
  p_batch_size INT DEFAULT NULL,
  p_max_runtime_ms INT DEFAULT NULL,
  p_queue TEXT DEFAULT NULL
)
LANGUAGE plpgsql
AS $procedure$
DECLARE
  task_record RECORD;
  start_time TIMESTAMPTZ;
  batch_start_time TIMESTAMPTZ;
  elapsed_ms NUMERIC;
  processed_count INT := 0;
  v_inside_transaction BOOLEAN;
  v_result_row RECORD;
BEGIN
  -- Check if we're inside a transaction
  SELECT txid_current_if_assigned() IS NOT NULL INTO v_inside_transaction;
  RAISE DEBUG 'Running worker.process_tasks inside transaction: %', v_inside_transaction;

  batch_start_time := clock_timestamp();

  -- Process tasks in a loop until we hit time limit or run out of tasks
  LOOP
    -- Claim a task with FOR UPDATE SKIP LOCKED to prevent concurrent processing
    SELECT t.*, cr.handler_procedure, cr.queue INTO task_record
    FROM worker.tasks t
    JOIN worker.command_registry cr ON t.command = cr.command
    WHERE t.state = 'pending'::worker.task_state
      AND (t.scheduled_at IS NULL OR t.scheduled_at <= clock_timestamp())
      AND (p_queue IS NULL OR cr.queue = p_queue)
    ORDER BY
      CASE WHEN t.scheduled_at IS NULL THEN 0 ELSE 1 END, -- Non-scheduled tasks next
      t.scheduled_at, -- Then by scheduled time (earliest first)
      t.priority ASC NULLS LAST, -- Then by priority (smaller numbers first so primary key id or epoch time can be used naturally)
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
    start_time := clock_timestamp();

    -- Mark as processing
    UPDATE worker.tasks AS t
    SET state = 'processing'::worker.task_state
    WHERE t.id = task_record.id;

    -- Commit to see state change of task. The COMMIT automatically ends the transaction,
    -- and starts a new one, there is no PL/PGSQL BEGIN to start a new transaction.
    IF NOT v_inside_transaction THEN
      COMMIT;
    END IF;

    DECLARE
      v_state worker.task_state;
      v_processed_at TIMESTAMPTZ;
      v_duration_ms NUMERIC;
      v_error TEXT DEFAULT NULL;
    BEGIN -- Block for variables, there is not CATCH that creates sub-transactions
      DECLARE -- Block for catching exceptions, introduces sub-transactions.
        v_message_text TEXT;
        v_pg_exception_detail TEXT;
        v_pg_exception_hint TEXT;
        v_pg_exception_context TEXT;
      BEGIN
        -- Process using dynamic dispatch with payload for all commands
        IF task_record.handler_procedure IS NOT NULL THEN
          -- Execute the handler procedure with the payload
          EXECUTE format('CALL %s($1)', task_record.handler_procedure)
          USING task_record.payload;
        ELSE
          RAISE EXCEPTION 'No handler procedure found for command: %', task_record.command;
        END IF;

        -- Mark as completed
        elapsed_ms := EXTRACT(EPOCH FROM (clock_timestamp() - start_time)) * 1000;
        v_state := 'completed'::worker.task_state;
        v_processed_at := clock_timestamp();
        v_duration_ms := elapsed_ms;

        -- Log success
        RAISE DEBUG 'Task % (%) completed in % ms',
          task_record.id, task_record.command, elapsed_ms;

      EXCEPTION WHEN OTHERS THEN
        elapsed_ms := EXTRACT(EPOCH FROM (clock_timestamp() - start_time)) * 1000;
        v_state := 'failed'::worker.task_state;
        v_processed_at := clock_timestamp();
        v_duration_ms := elapsed_ms;

        GET STACKED DIAGNOSTICS
          v_message_text = MESSAGE_TEXT,
          v_pg_exception_detail = PG_EXCEPTION_DETAIL,
          v_pg_exception_hint = PG_EXCEPTION_HINT,
          v_pg_exception_context = PG_EXCEPTION_CONTEXT;

        v_error := format(
          'Error: %s%sContext: %s%sDetail: %s%sHint: %s',
          v_message_text,
          E'\n',
          v_pg_exception_context,
          E'\n',
          COALESCE(v_pg_exception_detail, ''),
          E'\n',
          COALESCE(v_pg_exception_hint, '')
        );

        -- Log failure
        RAISE WARNING 'Task % (%) failed in % ms: %',
          task_record.id, task_record.command, elapsed_ms, v_error;
      END;

      -- Update the task with the results
      UPDATE worker.tasks AS t
      SET state = v_state,
          processed_at = v_processed_at,
          duration_ms = v_duration_ms,
          error = v_error
      WHERE t.id = task_record.id;

      -- Commit to see state change of task. The COMMIT automatically ends the transaction,
      -- and starts a new one, there is no PL/PGSQL BEGIN to start a new transaction.
      IF NOT v_inside_transaction THEN
        COMMIT;
      END IF;

    END;

    -- Increment processed count
    processed_count := processed_count + 1;
    -- Check if we've hit the batch size limit (if p_batch_size is set)
    IF p_batch_size IS NOT NULL AND processed_count >= p_batch_size THEN
      RAISE DEBUG 'Exiting worker loop: Batch size limit of % reached', p_batch_size;
      EXIT;
    END IF;
  END LOOP;
END;
$procedure$;


-- Register built-in commands
INSERT INTO worker.command_registry (queue, command, handler_procedure, description)
VALUES
  ('analytics', 'check_table', 'worker.command_check_table', 'Process changes in a table since a specific transaction ID'),
  ('analytics', 'deleted_row', 'worker.command_deleted_row', 'Handle deletion of rows from statistical unit tables'),
  ('analytics', 'timesegments_refresh', 'worker.command_timesegments_refresh', 'Refresh timesegments and then statistical units'),
  ('analytics', 'timeline_establishment_refresh', 'worker.command_timeline_establishment_refresh', 'Refresh timeline_establishment table'),
  ('analytics', 'timeline_legal_unit_refresh', 'worker.command_timeline_legal_unit_refresh', 'Refresh timeline_legal_unit table'),
  ('analytics', 'timeline_enterprise_refresh', 'worker.command_timeline_enterprise_refresh', 'Refresh timeline_enterprise table'),
  ('analytics', 'statistical_unit_refresh', 'worker.command_statistical_unit_refresh', 'Refresh statistical units'),
  ('analytics', 'refresh_derived_data', 'worker.command_refresh_derived_data', 'Refresh derived data tables'),
  ('maintenance', 'task_cleanup', 'worker.command_task_cleanup', 'Clean up old completed and failed tasks');


-- Add foreign key constraint to ensure command exists in command registry
ALTER TABLE worker.tasks ADD CONSTRAINT fk_tasks_command
FOREIGN KEY (command) REFERENCES worker.command_registry(command);

-- Create index for scheduled tasks
CREATE INDEX idx_tasks_scheduled_at ON worker.tasks (scheduled_at)
WHERE state = 'pending'::worker.task_state AND scheduled_at IS NOT NULL;


-- Function to reset abandoned processing tasks
-- This is used when the worker starts to reset any tasks that were left in 'processing' state
-- from a previous worker instance that crashed or was terminated unexpectedly
CREATE OR REPLACE FUNCTION worker.reset_abandoned_processing_tasks()
RETURNS int
LANGUAGE plpgsql
AS $function$
DECLARE
  v_count int := 0;
  v_task record;
  v_merged_count int := 0;
BEGIN
  -- First, identify all tasks that are stuck in 'processing' state
  FOR v_task IN
    SELECT id, command, payload
    FROM worker.tasks
    WHERE state = 'processing'::worker.task_state
  LOOP
    BEGIN
      -- Try to update the task to pending state
      UPDATE worker.tasks
      SET state = 'pending'::worker.task_state,
          processed_at = NULL,
          error = NULL
      WHERE id = v_task.id;

      v_count := v_count + 1;
    EXCEPTION WHEN unique_violation THEN
      -- If we hit a unique constraint violation, it means there's already a pending task
      -- for this command with the same deduplication key. In this case, we'll mark the
      -- processing task as failed and note that it was merged.
      UPDATE worker.tasks
      SET state = 'failed'::worker.task_state,
          processed_at = now(),
          error = 'Task automatically merged with existing pending task during worker restart'
      WHERE id = v_task.id;

      v_merged_count := v_merged_count + 1;
    END;
  END LOOP;

  -- Return the total number of tasks that were reset or merged
  RETURN v_count + v_merged_count;
END;
$function$;

-- Create command handler for task_cleanup
-- Removes completed and failed tasks older than the specified retention period
CREATE PROCEDURE worker.command_task_cleanup(
    payload JSONB
)
SECURITY DEFINER
LANGUAGE plpgsql
AS $procedure$
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
$procedure$;

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
    priority = EXCLUDED.priority,  -- Use the new priority to push queue position
    processed_at = NULL,
    error = NULL
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
