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


-- Notice that presence of queues is required for logically dependent tasks,
-- where a task can produce multiple new tasks, but they must all be processed in order.
CREATE TABLE worker.queue_registry (
  queue TEXT PRIMARY KEY,
  description TEXT,
  default_concurrency INT NOT NULL DEFAULT 1
);
COMMENT ON TABLE worker.queue_registry IS 'Defines available task queues. The system runs as a single worker process, which processes each queue serially to ensure task order. However, it uses concurrent fibers to process different queues (e.g., ''analytics'' and ''import'') at the same time.';
COMMENT ON COLUMN worker.queue_registry.default_concurrency IS 'Number of parallel workers for this queue. 1=serial (default). Higher values used for child task processing in structured concurrency mode.';

INSERT INTO worker.queue_registry (queue, description)
VALUES ('analytics', 'Serial queue for analysing and deriving data')
,('maintenance', 'Serial queue for maintenance tasks');

-- Create command registry table for dynamic command handling
CREATE TABLE worker.command_registry (
  command TEXT PRIMARY KEY,
  handler_procedure TEXT NOT NULL,
  before_procedure TEXT NULL, -- Optional procedure to call before handler_procedure
  after_procedure TEXT NULL,  -- Optional procedure to call after handler_procedure
  description TEXT,
  queue TEXT NOT NULL REFERENCES worker.queue_registry(queue),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- Create index for efficient queue lookups
CREATE INDEX idx_command_registry_queue ON worker.command_registry(queue);


CREATE TYPE worker.task_state AS ENUM (
  'pending',
  'processing',
  'waiting',   -- Parent task waiting for children to complete
  'completed',
  'failed'
);

CREATE SEQUENCE IF NOT EXISTS public.worker_task_priority_seq AS BIGINT;
GRANT USAGE ON SEQUENCE public.worker_task_priority_seq TO authenticated;

-- Create tasks table for batch processing
CREATE TABLE worker.tasks (
  id BIGSERIAL PRIMARY KEY,
  command TEXT NOT NULL REFERENCES worker.command_registry(command),
  priority BIGINT DEFAULT nextval('public.worker_task_priority_seq'),
  created_at TIMESTAMPTZ DEFAULT now(),
  state worker.task_state DEFAULT 'pending',
  processed_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,  -- When task finished (completed, failed, or waiting)
  duration_ms NUMERIC,
  error TEXT,
  scheduled_at TIMESTAMPTZ, -- When this task should be processed, if delayed.
  worker_pid INTEGER,
  payload JSONB,
  parent_id BIGINT REFERENCES worker.tasks(id),  -- For structured concurrency: children point to parent
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

-- Index for efficient child task lookup
CREATE INDEX idx_tasks_parent_id ON worker.tasks(parent_id) WHERE parent_id IS NOT NULL;

-- Index for finding waiting parents efficiently
CREATE INDEX idx_tasks_waiting ON worker.tasks(state) WHERE state = 'waiting'::worker.task_state;

-- Create partial unique indexes for each command type using payload fields
-- For check_table: deduplicate by table_name
CREATE UNIQUE INDEX idx_tasks_check_table_dedup
ON worker.tasks ((payload->>'table_name'))
WHERE command = 'check_table' AND state = 'pending'::worker.task_state;

-- For deleted_row: deduplicate by table_name only
CREATE UNIQUE INDEX idx_tasks_deleted_row_dedup
ON worker.tasks ((payload->>'table_name'))
WHERE command = 'deleted_row' AND state = 'pending'::worker.task_state;

-- For derive: only one pending task at a time
CREATE UNIQUE INDEX idx_tasks_derive_dedup
ON worker.tasks (command)
WHERE command = 'derive_statistical_unit' AND state = 'pending'::worker.task_state;

-- For task_cleanup: only one pending task at a time
CREATE UNIQUE INDEX idx_tasks_task_cleanup_dedup
ON worker.tasks (command)
WHERE command = 'task_cleanup' AND state = 'pending'::worker.task_state;

-- For derive_reports: only one pending task at a time
CREATE UNIQUE INDEX idx_tasks_derive_reports_dedup
ON worker.tasks (command)
WHERE command = 'derive_reports' AND state = 'pending'::worker.task_state;

-- For import_job_cleanup: only one pending task at a time
CREATE UNIQUE INDEX idx_tasks_import_job_cleanup_dedup
ON worker.tasks (command)
WHERE command = 'import_job_cleanup' AND state = 'pending'::worker.task_state;


-- Create statistical unit refresh function (part 1: core units)
CREATE OR REPLACE FUNCTION worker.derive_statistical_unit(
  p_establishment_id_ranges int4multirange DEFAULT NULL,
  p_legal_unit_id_ranges int4multirange DEFAULT NULL,
  p_enterprise_id_ranges int4multirange DEFAULT NULL,
  p_valid_from date DEFAULT NULL,
  p_valid_until date DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
AS $derive_statistical_unit$
DECLARE
    v_all_establishment_ids int[];
    v_all_legal_unit_ids int[];
    v_all_enterprise_ids int[];
BEGIN
    IF p_establishment_id_ranges IS NULL AND p_legal_unit_id_ranges IS NULL AND p_enterprise_id_ranges IS NULL THEN
        -- Full refresh
        CALL public.timepoints_refresh();
        CALL public.timesegments_refresh();
        CALL public.timesegments_years_refresh();
        CALL public.timeline_establishment_refresh();
        CALL public.timeline_legal_unit_refresh();
        CALL public.timeline_enterprise_refresh();
        CALL public.statistical_unit_refresh();
    ELSE
        -- Partial Refresh Logic:
        -- This block gathers the complete set of all units affected by an initial change.
        -- It starts with a small set of IDs, finds all related units (parents, children, historical),
        -- and passes the final, complete set to the refresh procedures.
        DECLARE
            -- Step 1: Convert input multiranges to initial arrays.
            -- The recursive CTE requires arrays of individual IDs to start its traversal. This conversion
            -- is necessary because recursive queries in SQL are designed to work with sets of rows, not by
            -- manipulating aggregate types like multiranges. Each step of the recursion joins the *rows*
            -- from the previous step to find new related rows.
            --
            -- For example, a simplified recursive term looks like:
            --   SELECT child.id FROM current_set c JOIN child_table child ON c.id = child.parent_id
            -- This is a natural row-based operation.
            --
            -- Attempting this with multiranges would require complex and unidiomatic logic inside the
            -- recursive term, such as unnesting the range, finding related IDs, and then re-aggregating
            -- them back into a new multirange to be unioned with the previous one, which is not how
            -- recursive CTEs are designed to function.
            initial_es_ids INT[] := ARRAY(SELECT generate_series(lower(r), upper(r)-1) FROM unnest(COALESCE(p_establishment_id_ranges, '{}'::int4multirange)) AS t(r));
            initial_lu_ids INT[] := ARRAY(SELECT generate_series(lower(r), upper(r)-1) FROM unnest(COALESCE(p_legal_unit_id_ranges,    '{}'::int4multirange)) AS t(r));
            initial_en_ids INT[] := ARRAY(SELECT generate_series(lower(r), upper(r)-1) FROM unnest(COALESCE(p_enterprise_id_ranges,    '{}'::int4multirange)) AS t(r));
        BEGIN
            -- Step 2: Use a recursive CTE to traverse the unit hierarchy.
            -- This finds all *currently* related parents and children.
            WITH RECURSIVE all_affected_units(id, type) AS (
                -- Base case: Start with the initial set of changed units.
                (
                    SELECT id, 'establishment'::public.statistical_unit_type AS type FROM unnest(initial_es_ids) AS t(id)
                    UNION ALL
                    SELECT id, 'legal_unit' FROM unnest(initial_lu_ids) AS t(id)
                    UNION ALL
                    SELECT id, 'enterprise' FROM unnest(initial_en_ids) AS t(id)
                )
                UNION
                -- Recursive step: Find all parents (up) AND children (down) of the units found so far.
                SELECT related.id, related.type
                FROM all_affected_units a
                JOIN LATERAL (
                    -- Find parents by traversing up the hierarchy.
                    SELECT es.legal_unit_id AS id, 'legal_unit'::public.statistical_unit_type AS type FROM public.establishment es WHERE a.type = 'establishment' AND a.id = es.id AND es.legal_unit_id IS NOT NULL
                    UNION ALL
                    SELECT es.enterprise_id, 'enterprise' FROM public.establishment es WHERE a.type = 'establishment' AND a.id = es.id AND es.enterprise_id IS NOT NULL
                    UNION ALL
                    SELECT lu.enterprise_id, 'enterprise' FROM public.legal_unit lu WHERE a.type = 'legal_unit' AND a.id = lu.id AND lu.enterprise_id IS NOT NULL
                    UNION ALL
                    -- Find children by traversing down the hierarchy.
                    SELECT lu.id, 'legal_unit' FROM public.legal_unit lu WHERE a.type = 'enterprise' AND a.id = lu.enterprise_id
                    UNION ALL
                    SELECT es.id, 'establishment' FROM public.establishment es WHERE a.type = 'enterprise' AND a.id = es.enterprise_id
                    UNION ALL
                    SELECT es.id, 'establishment' FROM public.establishment es WHERE a.type = 'legal_unit' AND a.id = es.legal_unit_id
                ) AS related ON true
            )
            -- Step 3: Aggregate the results of the traversal into arrays.
            SELECT
                array_agg(id) FILTER (WHERE type = 'establishment'),
                array_agg(id) FILTER (WHERE type = 'legal_unit'),
                array_agg(id) FILTER (WHERE type = 'enterprise')
            INTO
                v_all_establishment_ids,
                v_all_legal_unit_ids,
                v_all_enterprise_ids
            FROM all_affected_units;

            -- Step 4: Expand the set to include *historically* related units from the denormalized table.
            -- This is crucial for handling re-parenting cases (e.g., an establishment moved to a new legal unit).
            v_all_establishment_ids := array_cat(v_all_establishment_ids, COALESCE((SELECT array_agg(DISTINCT unnest) FROM (SELECT unnest(related_establishment_ids) FROM public.statistical_unit WHERE related_establishment_ids && v_all_establishment_ids) x), '{}'));
            v_all_legal_unit_ids := array_cat(v_all_legal_unit_ids, COALESCE((SELECT array_agg(DISTINCT unnest) FROM (SELECT unnest(related_legal_unit_ids) FROM public.statistical_unit WHERE related_legal_unit_ids && v_all_legal_unit_ids) x), '{}'));
            v_all_enterprise_ids := array_cat(v_all_enterprise_ids, COALESCE((SELECT array_agg(DISTINCT unnest) FROM (SELECT unnest(related_enterprise_ids) FROM public.statistical_unit WHERE related_enterprise_ids && v_all_enterprise_ids) x), '{}'));

            -- Step 5: Final deduplication and NULL removal.
            -- The v_all_*_ids arrays now contain the complete set of all affected units.
            v_all_establishment_ids := ARRAY(SELECT DISTINCT e FROM unnest(v_all_establishment_ids) e WHERE e IS NOT NULL);
            v_all_legal_unit_ids    := ARRAY(SELECT DISTINCT l FROM unnest(v_all_legal_unit_ids) l WHERE l IS NOT NULL);
            v_all_enterprise_ids    := ARRAY(SELECT DISTINCT en FROM unnest(v_all_enterprise_ids) en WHERE en IS NOT NULL);
        END;

        -- Step 6: Call the refresh procedures.
        -- The complete arrays are converted back to multiranges for efficient processing by the downstream procedures.
        CALL public.timepoints_refresh(
            p_establishment_id_ranges => public.array_to_int4multirange(v_all_establishment_ids),
            p_legal_unit_id_ranges => public.array_to_int4multirange(v_all_legal_unit_ids),
            p_enterprise_id_ranges => public.array_to_int4multirange(v_all_enterprise_ids)
        );

        CALL public.timesegments_refresh(
            p_establishment_id_ranges => public.array_to_int4multirange(v_all_establishment_ids),
            p_legal_unit_id_ranges => public.array_to_int4multirange(v_all_legal_unit_ids),
            p_enterprise_id_ranges => public.array_to_int4multirange(v_all_enterprise_ids)
        );

        CALL public.timesegments_years_refresh();

        CALL public.timeline_establishment_refresh(p_unit_id_ranges => public.array_to_int4multirange(v_all_establishment_ids));
        CALL public.timeline_legal_unit_refresh(p_unit_id_ranges => public.array_to_int4multirange(v_all_legal_unit_ids));
        CALL public.timeline_enterprise_refresh(p_unit_id_ranges => public.array_to_int4multirange(v_all_enterprise_ids));

        CALL public.statistical_unit_refresh(
            p_establishment_id_ranges => public.array_to_int4multirange(v_all_establishment_ids),
            p_legal_unit_id_ranges => public.array_to_int4multirange(v_all_legal_unit_ids),
            p_enterprise_id_ranges => public.array_to_int4multirange(v_all_enterprise_ids)
        );
    END IF;

    -- Refresh derived data (used flags) - these are always full refreshes for now
  PERFORM public.activity_category_used_derive();
  PERFORM public.region_used_derive();
  PERFORM public.sector_used_derive();
  PERFORM public.data_source_used_derive();
  PERFORM public.legal_form_used_derive();
  PERFORM public.country_used_derive();

  -- After the core units are refreshed, enqueue the follow-up task to derive reports.
  PERFORM worker.enqueue_derive_reports(
    p_valid_from => derive_statistical_unit.p_valid_from,
    p_valid_until => derive_statistical_unit.p_valid_until
  );
END;
$derive_statistical_unit$;

-- Create command handler for derive_statistical_unit
-- Refreshes core statistical units based on provided IDs and date range
CREATE PROCEDURE worker.derive_statistical_unit(
    payload JSONB
)
SECURITY DEFINER
LANGUAGE plpgsql
AS $derive_statistical_unit$
DECLARE
    v_establishment_id_ranges int4multirange = (payload->>'establishment_id_ranges')::int4multirange;
    v_legal_unit_id_ranges int4multirange = (payload->>'legal_unit_id_ranges')::int4multirange;
    v_enterprise_id_ranges int4multirange = (payload->>'enterprise_id_ranges')::int4multirange;
    v_valid_from date = (payload->>'valid_from')::date;
    v_valid_until date = (payload->>'valid_until')::date;
BEGIN
  -- Call the statistical unit refresh function with the extracted parameters
  PERFORM worker.derive_statistical_unit(
    p_establishment_id_ranges := v_establishment_id_ranges,
    p_legal_unit_id_ranges := v_legal_unit_id_ranges,
    p_enterprise_id_ranges := v_enterprise_id_ranges,
    p_valid_from := v_valid_from,
    p_valid_until := v_valid_until
  );
END;
$derive_statistical_unit$;

-- Procedure to notify about derive_statistical_unit start
CREATE PROCEDURE worker.notify_is_deriving_statistical_units_start()
LANGUAGE plpgsql AS $procedure$
BEGIN
  PERFORM pg_notify('worker_status', json_build_object('type', 'is_deriving_statistical_units', 'status', true)::text);
END;
$procedure$;

-- Procedure to notify about derive_statistical_unit stop
CREATE PROCEDURE worker.notify_is_deriving_statistical_units_stop()
LANGUAGE plpgsql AS $procedure$
BEGIN
  PERFORM pg_notify('worker_status', json_build_object('type', 'is_deriving_statistical_units', 'status', false)::text);
END;
$procedure$;


-- Create statistical unit refresh function (part 2: reports and facets)
CREATE FUNCTION worker.derive_reports(
  p_valid_from date DEFAULT NULL,
  p_valid_until date DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
AS $derive_reports$
BEGIN
  -- Refresh derived data (facets and history)
  PERFORM public.statistical_history_derive(p_valid_from => p_valid_from, p_valid_until => p_valid_until);
  PERFORM public.statistical_unit_facet_derive(p_valid_from => p_valid_from, p_valid_until => p_valid_until);
  PERFORM public.statistical_history_facet_derive(p_valid_from => p_valid_from, p_valid_until => p_valid_until);
END;
$derive_reports$;


-- Create command handler for derive_reports
-- Refreshes reports and facets based on date range
CREATE PROCEDURE worker.derive_reports(
    payload JSONB
)
SECURITY DEFINER
LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_valid_from date = (payload->>'valid_from')::date;
    v_valid_until date = (payload->>'valid_until')::date;
BEGIN
  -- Call the reports refresh function with the extracted parameters
  PERFORM worker.derive_reports(
    p_valid_from := v_valid_from,
    p_valid_until := v_valid_until
  );
END;
$procedure$;

-- Procedure to notify about derive_reports start
CREATE PROCEDURE worker.notify_is_deriving_reports_start()
LANGUAGE plpgsql AS $procedure$
BEGIN
  PERFORM pg_notify('worker_status', json_build_object('type', 'is_deriving_reports', 'status', true)::text);
END;
$procedure$;

-- Procedure to notify about derive_reports stop
CREATE PROCEDURE worker.notify_is_deriving_reports_stop()
LANGUAGE plpgsql AS $procedure$
BEGIN
  PERFORM pg_notify('worker_status', json_build_object('type', 'is_deriving_reports', 'status', false)::text);
END;
$procedure$;


-- Command handler for check_table
-- Processes all changes in a table since the last run.
CREATE PROCEDURE worker.command_check_table(
    payload JSONB
)
SECURITY DEFINER
LANGUAGE plpgsql
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
  CASE v_table_name
    WHEN 'enterprise', 'external_ident' THEN
      v_valid_columns := 'NULL::DATE AS valid_from, NULL::DATE AS valid_to, NULL::DATE AS valid_until';
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
--     CALL worker.process_tasks();
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

-- For deleted_row command
CREATE FUNCTION worker.enqueue_deleted_row(
  p_table_name TEXT,
  p_establishment_id INT DEFAULT NULL,
  p_legal_unit_id INT DEFAULT NULL,
  p_enterprise_id INT DEFAULT NULL,
  p_valid_from DATE DEFAULT NULL,
  p_valid_until DATE DEFAULT NULL
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


-- For derive_statistical_unit command
CREATE FUNCTION worker.enqueue_derive_statistical_unit(
  p_establishment_id_ranges int4multirange DEFAULT NULL,
  p_legal_unit_id_ranges int4multirange DEFAULT NULL,
  p_enterprise_id_ranges int4multirange DEFAULT NULL,
  p_valid_from date DEFAULT NULL,
  p_valid_until date DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql
AS $function$
DECLARE
  v_task_id BIGINT;
  v_payload JSONB;
  v_establishment_id_ranges int4multirange := COALESCE(p_establishment_id_ranges, '{}'::int4multirange);
  v_legal_unit_id_ranges int4multirange := COALESCE(p_legal_unit_id_ranges, '{}'::int4multirange);
  v_enterprise_id_ranges int4multirange := COALESCE(p_enterprise_id_ranges, '{}'::int4multirange);
  v_valid_from DATE := COALESCE(p_valid_from, '-infinity'::DATE);
  v_valid_until DATE := COALESCE(p_valid_until, 'infinity'::DATE);
BEGIN
  -- Create payload with multiranges
  v_payload := jsonb_build_object(
    'command', 'derive_statistical_unit',
    'establishment_id_ranges', v_establishment_id_ranges,
    'legal_unit_id_ranges', v_legal_unit_id_ranges,
    'enterprise_id_ranges', v_enterprise_id_ranges,
    'valid_from', v_valid_from,
    'valid_until', v_valid_until
  );

  -- Use the unique index on command for deduplication
  INSERT INTO worker.tasks AS t (
    command, payload
  ) VALUES ('derive_statistical_unit', v_payload)
  ON CONFLICT (command)
  WHERE command = 'derive_statistical_unit' AND state = 'pending'::worker.task_state
  DO UPDATE SET
    payload = jsonb_build_object(
      'command', 'derive_statistical_unit',
      -- Merge multiranges using the union operator
      'establishment_id_ranges', (t.payload->>'establishment_id_ranges')::int4multirange + (EXCLUDED.payload->>'establishment_id_ranges')::int4multirange,
      'legal_unit_id_ranges', (t.payload->>'legal_unit_id_ranges')::int4multirange + (EXCLUDED.payload->>'legal_unit_id_ranges')::int4multirange,
      'enterprise_id_ranges', (t.payload->>'enterprise_id_ranges')::int4multirange + (EXCLUDED.payload->>'enterprise_id_ranges')::int4multirange,
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


-- For derive_reports command
CREATE FUNCTION worker.enqueue_derive_reports(
  p_valid_from date DEFAULT NULL,
  p_valid_until date DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql
AS $function$
DECLARE
  v_task_id BIGINT;
  v_payload JSONB;
  v_valid_from DATE := COALESCE(p_valid_from, '-infinity'::DATE);
  v_valid_until DATE := COALESCE(p_valid_until, 'infinity'::DATE);
BEGIN
  -- Create payload
  v_payload := jsonb_build_object(
    'command', 'derive_reports',
    'valid_from', v_valid_from,
    'valid_until', v_valid_until
  );

  -- Use the unique index on command for deduplication
  INSERT INTO worker.tasks AS t (
    command, payload
  ) VALUES ('derive_reports', v_payload)
  ON CONFLICT (command)
  WHERE command = 'derive_reports' AND state = 'pending'::worker.task_state
  DO UPDATE SET
    payload = jsonb_build_object(
      'command', 'derive_reports',
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


-- ============================================================================
-- STRUCTURED CONCURRENCY SUPPORT
-- ============================================================================
-- Based on Trio's nursery pattern: https://vorpus.org/blog/notes-on-structured-concurrency-or-go-statement-considered-harmful/
-- 
-- Key concepts:
-- - Parent tasks can spawn children (tasks with parent_id pointing to them)
-- - Parent goes to 'waiting' state when it has pending children
-- - Children can spawn siblings (same parent_id) or uncles (parent_id = NULL)
-- - When all children complete: parent completes (or fails if any child failed)
-- - Scheduler switches mode based on waiting task presence:
--   - No waiting task: serial mode (one task at a time)
--   - Waiting task exists: concurrent mode (process children)
-- ============================================================================

-- Spawn a new task (child if parent_id provided, uncle/top-level if NULL)
CREATE FUNCTION worker.spawn(
    p_command TEXT,
    p_payload JSONB DEFAULT '{}'::jsonb,
    p_parent_id BIGINT DEFAULT NULL,
    p_priority BIGINT DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql
AS $spawn$
DECLARE
    v_task_id BIGINT;
    v_priority BIGINT;
BEGIN
    -- Use provided priority or get default from command registry
    IF p_priority IS NOT NULL THEN
        v_priority := p_priority;
    ELSE
        v_priority := nextval('public.worker_task_priority_seq');
    END IF;
    
    -- Add command to payload if not present
    IF p_payload IS NULL OR p_payload = '{}'::jsonb THEN
        p_payload := jsonb_build_object('command', p_command);
    ELSIF p_payload->>'command' IS NULL THEN
        p_payload := p_payload || jsonb_build_object('command', p_command);
    END IF;
    
    INSERT INTO worker.tasks (command, payload, parent_id, priority)
    VALUES (p_command, p_payload, p_parent_id, v_priority)
    RETURNING id INTO v_task_id;
    
    -- Get the queue for notification
    PERFORM pg_notify('worker_tasks', (
        SELECT queue FROM worker.command_registry WHERE command = p_command
    ));
    
    RETURN v_task_id;
END;
$spawn$;

COMMENT ON FUNCTION worker.spawn(TEXT, JSONB, BIGINT, BIGINT) IS
'Spawn a new task. If p_parent_id is provided, creates a child task (runs concurrently with siblings).
If p_parent_id is NULL, creates a top-level/uncle task (runs after any waiting parent completes).';


-- Check if a task has any pending children
CREATE FUNCTION worker.has_pending_children(p_task_id BIGINT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $has_pending_children$
    SELECT EXISTS (
        SELECT 1 FROM worker.tasks 
        WHERE parent_id = p_task_id 
          AND state IN ('pending', 'processing', 'waiting')
    );
$has_pending_children$;


-- Check if a task has any failed siblings (same parent)
CREATE FUNCTION worker.has_failed_siblings(p_task_id BIGINT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $has_failed_siblings$
    SELECT EXISTS (
        SELECT 1 FROM worker.tasks t
        JOIN worker.tasks self ON self.id = p_task_id
        WHERE t.parent_id = self.parent_id 
          AND t.id != p_task_id
          AND t.state = 'failed'
    );
$has_failed_siblings$;


-- Complete a parent task if all its children are done
-- Called after a child task completes
CREATE FUNCTION worker.complete_parent_if_ready(p_child_task_id BIGINT)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $complete_parent_if_ready$
DECLARE
    v_parent_id BIGINT;
    v_parent_completed BOOLEAN := FALSE;
    v_any_failed BOOLEAN;
BEGIN
    -- Get the parent_id from the child task
    SELECT parent_id INTO v_parent_id
    FROM worker.tasks
    WHERE id = p_child_task_id;
    
    -- If no parent, nothing to do
    IF v_parent_id IS NULL THEN
        RETURN FALSE;
    END IF;
    
    -- Check if parent still has pending children
    IF worker.has_pending_children(v_parent_id) THEN
        RETURN FALSE;
    END IF;
    
    -- All children done - check for failures
    SELECT EXISTS (
        SELECT 1 FROM worker.tasks 
        WHERE parent_id = v_parent_id AND state = 'failed'
    ) INTO v_any_failed;
    
    IF v_any_failed THEN
        -- Parent fails because a child failed
        UPDATE worker.tasks 
        SET state = 'failed',
            completed_at = clock_timestamp(),
            error = 'One or more child tasks failed'
        WHERE id = v_parent_id AND state = 'waiting';
    ELSE
        -- All children succeeded - parent completes
        UPDATE worker.tasks 
        SET state = 'completed',
            completed_at = clock_timestamp()
        WHERE id = v_parent_id AND state = 'waiting';
    END IF;
    
    IF FOUND THEN
        v_parent_completed := TRUE;
        RAISE DEBUG 'complete_parent_if_ready: Parent task % completed (failed=%)', v_parent_id, v_any_failed;
    END IF;
    
    RETURN v_parent_completed;
END;
$complete_parent_if_ready$;

COMMENT ON FUNCTION worker.complete_parent_if_ready(BIGINT) IS
'Called after a child task completes. Checks if all siblings are done and, if so, 
completes the parent (or fails it if any child failed).';


-- Trigger to prevent grandchildren (enforce single-level parent-child)
CREATE FUNCTION worker.enforce_no_grandchildren()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $enforce_no_grandchildren$
DECLARE
    v_grandparent_id BIGINT;
BEGIN
    IF NEW.parent_id IS NOT NULL THEN
        -- Check if the parent itself has a parent
        SELECT parent_id INTO v_grandparent_id
        FROM worker.tasks
        WHERE id = NEW.parent_id;
        
        IF v_grandparent_id IS NOT NULL THEN
            RAISE EXCEPTION 'Cannot create grandchild tasks. Parent task % already has parent %. Children can only spawn siblings (same parent_id) or uncles (parent_id = NULL).', 
                NEW.parent_id, v_grandparent_id;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$enforce_no_grandchildren$;

CREATE TRIGGER tasks_enforce_no_grandchildren
BEFORE INSERT ON worker.tasks
FOR EACH ROW
WHEN (NEW.parent_id IS NOT NULL)
EXECUTE FUNCTION worker.enforce_no_grandchildren();


-- Create unified task processing procedure with structured concurrency support
-- Processes pending tasks in batches with time limits
-- 
-- STRUCTURED CONCURRENCY BEHAVIOR:
-- - If a 'waiting' task exists: pick children of that waiting parent (concurrent mode)
-- - If no 'waiting' task: pick top-level tasks one at a time (serial mode)
-- - After handler runs: if task spawned children → state = 'waiting'
-- - After child completes: check if parent is ready to complete
--
-- Parameters:
--   p_batch_size: Maximum number of tasks to process (NULL = until queue is stable)
--   p_max_runtime_ms: Maximum runtime in milliseconds before stopping
--   p_queue: Process only tasks in this queue (NULL for all queues)
--   p_max_priority: Only process tasks with priority <= this value
CREATE PROCEDURE worker.process_tasks(
  p_batch_size INT DEFAULT NULL,
  p_max_runtime_ms INT DEFAULT NULL,
  p_queue TEXT DEFAULT NULL,
  p_max_priority BIGINT DEFAULT NULL
)
LANGUAGE plpgsql
AS $process_tasks$
DECLARE
  task_record RECORD;
  start_time TIMESTAMPTZ;
  batch_start_time TIMESTAMPTZ;
  elapsed_ms NUMERIC;
  processed_count INT := 0;
  v_inside_transaction BOOLEAN;
  v_waiting_parent_id BIGINT;
BEGIN
  -- Check if we're inside a transaction
  SELECT pg_current_xact_id_if_assigned() IS NOT NULL INTO v_inside_transaction;
  RAISE DEBUG 'Running worker.process_tasks inside transaction: %, queue: %', v_inside_transaction, p_queue;

  batch_start_time := clock_timestamp();

  -- Process tasks in a loop until we hit limits or run out of tasks
  LOOP
    -- Check for time limit
    IF p_max_runtime_ms IS NOT NULL AND
       EXTRACT(EPOCH FROM (clock_timestamp() - batch_start_time)) * 1000 > p_max_runtime_ms THEN
      RAISE DEBUG 'Exiting worker loop: Time limit of % ms reached', p_max_runtime_ms;
      EXIT;
    END IF;

    -- STRUCTURED CONCURRENCY: Check if there's a waiting parent task
    -- If so, we're in concurrent mode and should pick its children
    SELECT t.id INTO v_waiting_parent_id
    FROM worker.tasks t
    JOIN worker.command_registry cr ON t.command = cr.command
    WHERE t.state = 'waiting'::worker.task_state
      AND (p_queue IS NULL OR cr.queue = p_queue)
    ORDER BY t.priority, t.id
    LIMIT 1;

    IF v_waiting_parent_id IS NOT NULL THEN
      -- CONCURRENT MODE: Pick a pending child of the waiting parent
      RAISE DEBUG 'Concurrent mode: picking child of waiting parent %', v_waiting_parent_id;
      
      SELECT t.*, cr.handler_procedure, cr.before_procedure, cr.after_procedure, cr.queue
      INTO task_record
      FROM worker.tasks t
      JOIN worker.command_registry cr ON t.command = cr.command
      WHERE t.state = 'pending'::worker.task_state
        AND t.parent_id = v_waiting_parent_id
        AND (t.scheduled_at IS NULL OR t.scheduled_at <= clock_timestamp())
        AND (p_max_priority IS NULL OR t.priority <= p_max_priority)
      ORDER BY t.priority ASC NULLS LAST, t.id
      LIMIT 1
      FOR UPDATE OF t SKIP LOCKED;
    ELSE
      -- SERIAL MODE: Pick a top-level pending task (parent_id IS NULL)
      RAISE DEBUG 'Serial mode: picking top-level task';
      
      SELECT t.*, cr.handler_procedure, cr.before_procedure, cr.after_procedure, cr.queue
      INTO task_record
      FROM worker.tasks t
      JOIN worker.command_registry cr ON t.command = cr.command
      WHERE t.state = 'pending'::worker.task_state
        AND t.parent_id IS NULL
        AND (t.scheduled_at IS NULL OR t.scheduled_at <= clock_timestamp())
        AND (p_queue IS NULL OR cr.queue = p_queue)
        AND (p_max_priority IS NULL OR t.priority <= p_max_priority)
      ORDER BY
        CASE WHEN t.scheduled_at IS NULL THEN 0 ELSE 1 END,
        t.scheduled_at,
        t.priority ASC NULLS LAST,
        t.id
      LIMIT 1
      FOR UPDATE OF t SKIP LOCKED;
    END IF;

    -- Exit if no more tasks
    IF NOT FOUND THEN
      RAISE DEBUG 'Exiting worker loop: No more pending tasks found';
      EXIT;
    END IF;

    -- Process the task
    start_time := clock_timestamp();

    -- Mark as processing and record the current backend PID
    UPDATE worker.tasks AS t
    SET state = 'processing'::worker.task_state,
        worker_pid = pg_backend_pid()
    WHERE t.id = task_record.id;

    -- Call before_procedure if defined
    IF task_record.before_procedure IS NOT NULL THEN
      BEGIN
        RAISE DEBUG 'Calling before_procedure: % for task % (%)', task_record.before_procedure, task_record.id, task_record.command;
        EXECUTE format('CALL %s()', task_record.before_procedure);
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Error in before_procedure % for task %: %', task_record.before_procedure, task_record.id, SQLERRM;
      END;
    END IF;

    -- Commit to see state change (only if not in a test transaction)
    IF NOT v_inside_transaction THEN
      COMMIT;
    END IF;

    DECLARE
      v_state worker.task_state;
      v_processed_at TIMESTAMPTZ;
      v_completed_at TIMESTAMPTZ;
      v_duration_ms NUMERIC;
      v_error TEXT DEFAULT NULL;
      v_has_children BOOLEAN;
    BEGIN
      DECLARE
        v_message_text TEXT;
        v_pg_exception_detail TEXT;
        v_pg_exception_hint TEXT;
        v_pg_exception_context TEXT;
      BEGIN
        -- Execute the handler procedure
        IF task_record.handler_procedure IS NOT NULL THEN
          EXECUTE format('CALL %s($1)', task_record.handler_procedure)
          USING task_record.payload;
        ELSE
          RAISE EXCEPTION 'No handler procedure found for command: %', task_record.command;
        END IF;

        -- Handler completed successfully
        elapsed_ms := EXTRACT(EPOCH FROM (clock_timestamp() - start_time)) * 1000;
        v_processed_at := clock_timestamp();
        v_duration_ms := elapsed_ms;

        -- STRUCTURED CONCURRENCY: Check if handler spawned children
        SELECT EXISTS (
          SELECT 1 FROM worker.tasks WHERE parent_id = task_record.id
        ) INTO v_has_children;

        IF v_has_children THEN
          -- Task spawned children: go to 'waiting' state
          v_state := 'waiting'::worker.task_state;
          v_completed_at := NULL;  -- Not completed yet, waiting for children
          RAISE DEBUG 'Task % (%) spawned children, entering waiting state', task_record.id, task_record.command;
        ELSE
          -- No children: task is completed
          v_state := 'completed'::worker.task_state;
          v_completed_at := clock_timestamp();
          RAISE DEBUG 'Task % (%) completed in % ms', task_record.id, task_record.command, elapsed_ms;
        END IF;

      EXCEPTION WHEN OTHERS THEN
        elapsed_ms := EXTRACT(EPOCH FROM (clock_timestamp() - start_time)) * 1000;
        v_state := 'failed'::worker.task_state;
        v_processed_at := clock_timestamp();
        v_completed_at := clock_timestamp();
        v_duration_ms := elapsed_ms;

        GET STACKED DIAGNOSTICS
          v_message_text = MESSAGE_TEXT,
          v_pg_exception_detail = PG_EXCEPTION_DETAIL,
          v_pg_exception_hint = PG_EXCEPTION_HINT,
          v_pg_exception_context = PG_EXCEPTION_CONTEXT;

        v_error := format(
          'Error: %s%sContext: %s%sDetail: %s%sHint: %s',
          v_message_text, E'\n',
          v_pg_exception_context, E'\n',
          COALESCE(v_pg_exception_detail, ''), E'\n',
          COALESCE(v_pg_exception_hint, '')
        );

        RAISE WARNING 'Task % (%) failed in % ms: %', task_record.id, task_record.command, elapsed_ms, v_error;
      END;

      -- Update the task with results
      UPDATE worker.tasks AS t
      SET state = v_state,
          processed_at = v_processed_at,
          completed_at = v_completed_at,
          duration_ms = v_duration_ms,
          error = v_error
      WHERE t.id = task_record.id;

      -- STRUCTURED CONCURRENCY: If this was a child and it completed/failed, check parent
      IF task_record.parent_id IS NOT NULL AND v_state IN ('completed', 'failed') THEN
        PERFORM worker.complete_parent_if_ready(task_record.id);
      END IF;

      -- Call after_procedure if defined
      IF task_record.after_procedure IS NOT NULL THEN
        BEGIN
          RAISE DEBUG 'Calling after_procedure: % for task % (%)', task_record.after_procedure, task_record.id, task_record.command;
          EXECUTE format('CALL %s()', task_record.after_procedure);
        EXCEPTION WHEN OTHERS THEN
          RAISE WARNING 'Error in after_procedure % for task %: %', task_record.after_procedure, task_record.id, SQLERRM;
        END;
      END IF;

      -- Commit if not in transaction
      IF NOT v_inside_transaction THEN
        COMMIT;
      END IF;
    END;

    -- Increment processed count and check batch limit
    processed_count := processed_count + 1;
    IF p_batch_size IS NOT NULL AND processed_count >= p_batch_size THEN
      RAISE DEBUG 'Exiting worker loop: Batch size limit of % reached', p_batch_size;
      EXIT;
    END IF;
  END LOOP;
END;
$process_tasks$;


-- Register built-in commands, linking notification procedures
INSERT INTO worker.command_registry (queue, command, handler_procedure, before_procedure, after_procedure, description)
VALUES
  ('analytics', 'check_table', 'worker.command_check_table', NULL, NULL, 'Process changes in a table since a specific transaction ID'),
  ('analytics', 'deleted_row', 'worker.command_deleted_row', NULL, NULL, 'Handle deletion of rows from statistical unit tables'),
  ('analytics', 'derive_statistical_unit', 'worker.derive_statistical_unit', 'worker.notify_is_deriving_statistical_units_start', 'worker.notify_is_deriving_statistical_units_stop', 'Refresh core timeline tables and statistical units'),
  ('analytics', 'derive_reports', 'worker.derive_reports', 'worker.notify_is_deriving_reports_start', 'worker.notify_is_deriving_reports_stop', 'Refresh derived reports, facets, and history'),
  ('maintenance', 'task_cleanup', 'worker.command_task_cleanup', NULL, NULL, 'Clean up old completed and failed tasks'),
  ('maintenance', 'import_job_cleanup', 'worker.command_import_job_cleanup', NULL, NULL, 'Clean up expired import jobs and their associated data');


-- Add foreign key constraint to ensure command exists in command registry
ALTER TABLE worker.tasks ADD CONSTRAINT fk_tasks_command
FOREIGN KEY (command) REFERENCES worker.command_registry(command);

-- Create index for scheduled tasks
CREATE INDEX idx_tasks_scheduled_at ON worker.tasks (scheduled_at)
WHERE state = 'pending'::worker.task_state AND scheduled_at IS NOT NULL;

-- Create missing composite index for efficient pending task selection
CREATE INDEX idx_worker_tasks_pending_priority 
ON worker.tasks (state, priority) 
WHERE state = 'pending'::worker.task_state;


-- Function to reset abandoned processing tasks
-- This is used when the worker starts to reset any tasks that were left in 'processing' state
-- from a previous worker instance that crashed or was terminated unexpectedly
CREATE OR REPLACE FUNCTION worker.reset_abandoned_processing_tasks()
RETURNS int
LANGUAGE plpgsql
AS $function$
DECLARE
  v_reset_count int := 0;
  v_task RECORD;
  v_stale_pid INT;
BEGIN
  -- Terminate all other lingering worker backends.
  -- The current worker holds the global advisory lock, so any other process with
  -- application_name = 'worker' is a stale remnant from a previous crash.
  FOR v_stale_pid IN
    SELECT pid FROM pg_stat_activity
    WHERE application_name = 'worker' AND pid <> pg_backend_pid()
  LOOP
    RAISE LOG 'Terminating stale worker PID %', v_stale_pid;
    PERFORM pg_terminate_backend(v_stale_pid);
  END LOOP;

  -- Find tasks stuck in 'processing' and reset their status to 'pending'.
  -- The backends have already been terminated above.
  FOR v_task IN
    SELECT id FROM worker.tasks WHERE state = 'processing'::worker.task_state FOR UPDATE
  LOOP
    -- Reset the task to pending state.
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

-- Create command handler for import_job_cleanup
-- Removes expired import jobs and their associated data tables
CREATE PROCEDURE worker.command_import_job_cleanup(
    payload JSONB -- Payload is not used but kept for command handler consistency
)
SECURITY DEFINER
LANGUAGE plpgsql
AS $command_import_job_cleanup$
DECLARE
    v_job_record RECORD;
    v_deleted_count INTEGER := 0;
BEGIN
    RAISE DEBUG 'Running worker.command_import_job_cleanup';

    FOR v_job_record IN
        SELECT id, slug FROM public.import_job WHERE expires_at <= now()
    LOOP
        RAISE DEBUG '[Job % (Slug: %)] Expired, attempting deletion.', v_job_record.id, v_job_record.slug;
        BEGIN
            DELETE FROM public.import_job WHERE id = v_job_record.id;
            v_deleted_count := v_deleted_count + 1;
            RAISE DEBUG '[Job % (Slug: %)] Successfully deleted.', v_job_record.id, v_job_record.slug;
        EXCEPTION
            WHEN OTHERS THEN
                RAISE WARNING '[Job % (Slug: %)] Failed to delete expired import job: %', v_job_record.id, v_job_record.slug, SQLERRM;
                -- Optionally, update the job with an error or take other action
                -- For now, we just log and continue, so other jobs can be processed.
        END;
    END LOOP;

    RAISE DEBUG 'Finished worker.command_import_job_cleanup. Deleted % expired jobs.', v_deleted_count;

    -- Schedule to run again in 24 hours
    PERFORM worker.enqueue_import_job_cleanup();
END;
$command_import_job_cleanup$;

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

-- For import_job_cleanup command
CREATE FUNCTION worker.enqueue_import_job_cleanup()
RETURNS BIGINT
LANGUAGE plpgsql
AS $enqueue_import_job_cleanup$
DECLARE
  v_task_id BIGINT;
BEGIN
  -- Insert with ON CONFLICT for this specific command type
  INSERT INTO worker.tasks (
    command,
    payload,
    scheduled_at
  ) VALUES (
    'import_job_cleanup',
    '{}'::jsonb, -- No payload needed as expiry is on the job itself
    now() + interval '24 hours'
  )
  ON CONFLICT (command) WHERE command = 'import_job_cleanup' AND state = 'pending'::worker.task_state
  DO UPDATE SET
    payload = EXCLUDED.payload,
    scheduled_at = EXCLUDED.scheduled_at, -- Update to the new scheduled time
    state = 'pending'::worker.task_state,
    priority = EXCLUDED.priority,
    processed_at = NULL,
    error = NULL
  RETURNING id INTO v_task_id;

  -- Notify worker of new task with queue information
  PERFORM pg_notify('worker_tasks', 'maintenance');

  RETURN v_task_id;
END;
$enqueue_import_job_cleanup$;

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

-- STATEMENT-level trigger function for INSERT/UPDATE
CREATE FUNCTION worker.notify_worker_about_statement_changes()
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

-- ROW-level trigger function for UPDATE
CREATE FUNCTION worker.notify_worker_about_row_changes()
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


CREATE FUNCTION worker.notify_worker_about_deletes()
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


CREATE PROCEDURE worker.setup()
LANGUAGE plpgsql
AS $procedure$
BEGIN
  -- Create STATEMENT-level triggers for INSERT or UPDATE
  -- These will enqueue a 'check_table' task for any modification.
  CALL worker.setup_statement_triggers(ARRAY[
    'enterprise', 'external_ident', 'legal_unit', 'establishment',
    'activity', 'location', 'contact', 'stat_for_unit'
  ]);

  -- Create ROW-level triggers for UPDATE to handle re-parenting.
  -- Each trigger has a WHEN clause to fire only when parent FKs change.
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

CREATE PROCEDURE worker.teardown()
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


-- Helper procedure to create statement-level triggers
CREATE PROCEDURE worker.setup_statement_triggers(p_table_names TEXT[])
LANGUAGE plpgsql AS $$
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
$$;

-- Helper procedure to create row-level triggers for updates
CREATE PROCEDURE worker.setup_row_level_triggers()
LANGUAGE plpgsql AS $$
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
$$;


-- Helper procedure to create delete triggers
CREATE PROCEDURE worker.setup_delete_triggers(p_table_names TEXT[])
LANGUAGE plpgsql AS $$
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
$$;


-- Call setup to create triggers
CALL worker.setup();

END;
