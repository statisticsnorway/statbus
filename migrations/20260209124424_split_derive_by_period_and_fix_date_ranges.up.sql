-- Migration 20260209124424: split_derive_by_period_and_fix_date_ranges
--
-- Fix 1: Derive dates for enterprise/external_ident in command_check_table
--         (prevents NULL dates → -infinity/infinity → full refresh of all periods)
-- Fix 2: Split derive_statistical_history by period using worker.spawn()
-- Fix 2b: Convert derive_statistical_history_facet from enqueue to spawn
-- Fix 3: Analytics queue concurrency already at 4 (verified, no change needed)
BEGIN;

-- ============================================================================
-- Fix 1: Derive dates for enterprise/external_ident in command_check_table
-- ============================================================================
-- Enterprise has no temporal columns, but its establishments do.
-- External_ident links to establishment/legal_unit which have temporal columns.
-- Using correlated subqueries on indexed columns (enterprise_id, valid_range).

CREATE OR REPLACE PROCEDURE worker.command_check_table(IN payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $command_check_table$
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
$command_check_table$;

-- ============================================================================
-- Fix 2: New command registry entries for period handlers
-- ============================================================================

INSERT INTO worker.command_registry (command, handler_procedure, queue, description)
VALUES
  ('derive_statistical_history_period',
   'worker.derive_statistical_history_period',
   'analytics',
   'Derive statistical history for a single period (resolution/year/month)')
ON CONFLICT (command) DO NOTHING;

-- ============================================================================
-- Fix 2: New handler — derive_statistical_history_period (child)
-- ============================================================================
-- Each child handles one (resolution, year, month) period.
-- DELETE + INSERT with ON CONFLICT for concurrent safety.

CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_period(IN payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $derive_statistical_history_period$
DECLARE
    v_resolution public.history_resolution := (payload->>'resolution')::public.history_resolution;
    v_year integer := (payload->>'year')::integer;
    v_month integer := (payload->>'month')::integer;  -- NULL for year resolution
BEGIN
    RAISE DEBUG 'Processing statistical_history for resolution=%, year=%, month=%',
                 v_resolution, v_year, v_month;

    -- Delete existing data for this specific period
    DELETE FROM public.statistical_history
    WHERE resolution = v_resolution
      AND year = v_year
      AND month IS NOT DISTINCT FROM v_month;

    -- Insert new data with ON CONFLICT for concurrent safety
    IF v_resolution = 'year' THEN
        INSERT INTO public.statistical_history
        SELECT h.*
        FROM public.statistical_history_def(v_resolution, v_year, v_month) AS h
        ON CONFLICT (resolution, year, unit_type) WHERE resolution = 'year'::public.history_resolution
        DO UPDATE SET
            exists_count = EXCLUDED.exists_count,
            exists_change = EXCLUDED.exists_change,
            exists_added_count = EXCLUDED.exists_added_count,
            exists_removed_count = EXCLUDED.exists_removed_count,
            countable_count = EXCLUDED.countable_count,
            countable_change = EXCLUDED.countable_change,
            countable_added_count = EXCLUDED.countable_added_count,
            countable_removed_count = EXCLUDED.countable_removed_count,
            births = EXCLUDED.births,
            deaths = EXCLUDED.deaths,
            name_change_count = EXCLUDED.name_change_count,
            primary_activity_category_change_count = EXCLUDED.primary_activity_category_change_count,
            secondary_activity_category_change_count = EXCLUDED.secondary_activity_category_change_count,
            sector_change_count = EXCLUDED.sector_change_count,
            legal_form_change_count = EXCLUDED.legal_form_change_count,
            physical_region_change_count = EXCLUDED.physical_region_change_count,
            physical_country_change_count = EXCLUDED.physical_country_change_count,
            physical_address_change_count = EXCLUDED.physical_address_change_count,
            stats_summary = EXCLUDED.stats_summary;
    ELSIF v_resolution = 'year-month' THEN
        INSERT INTO public.statistical_history
        SELECT h.*
        FROM public.statistical_history_def(v_resolution, v_year, v_month) AS h
        ON CONFLICT (resolution, year, month, unit_type) WHERE resolution = 'year-month'::public.history_resolution
        DO UPDATE SET
            exists_count = EXCLUDED.exists_count,
            exists_change = EXCLUDED.exists_change,
            exists_added_count = EXCLUDED.exists_added_count,
            exists_removed_count = EXCLUDED.exists_removed_count,
            countable_count = EXCLUDED.countable_count,
            countable_change = EXCLUDED.countable_change,
            countable_added_count = EXCLUDED.countable_added_count,
            countable_removed_count = EXCLUDED.countable_removed_count,
            births = EXCLUDED.births,
            deaths = EXCLUDED.deaths,
            name_change_count = EXCLUDED.name_change_count,
            primary_activity_category_change_count = EXCLUDED.primary_activity_category_change_count,
            secondary_activity_category_change_count = EXCLUDED.secondary_activity_category_change_count,
            sector_change_count = EXCLUDED.sector_change_count,
            legal_form_change_count = EXCLUDED.legal_form_change_count,
            physical_region_change_count = EXCLUDED.physical_region_change_count,
            physical_country_change_count = EXCLUDED.physical_country_change_count,
            physical_address_change_count = EXCLUDED.physical_address_change_count,
            stats_summary = EXCLUDED.stats_summary;
    END IF;

    RAISE DEBUG 'Completed statistical_history for resolution=%, year=%, month=%',
                 v_resolution, v_year, v_month;
END;
$derive_statistical_history_period$;

-- ============================================================================
-- Fix 2: Replace derive_statistical_history with spawn-based coordinator
-- ============================================================================
-- Instead of calling statistical_history_derive() monolithically (29s),
-- spawn one child per period for concurrent execution.
-- The parent enters 'waiting' state; when all children complete, the
-- next phase (DSUF) is picked up by the top fiber.

CREATE OR REPLACE PROCEDURE worker.derive_statistical_history(IN payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $derive_statistical_history$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
    v_task_id bigint;
    v_period record;
    v_child_count integer := 0;
BEGIN
    -- Get own task_id for spawning children
    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY id DESC LIMIT 1;

    RAISE DEBUG 'derive_statistical_history: task_id=%, valid_from=%, valid_until=%',
                 v_task_id, v_valid_from, v_valid_until;

    -- Enqueue next phase first (stays pending while DSH is 'waiting')
    PERFORM worker.enqueue_derive_statistical_unit_facet(
        p_valid_from => v_valid_from,
        p_valid_until => v_valid_until
    );

    -- Spawn one child per period for concurrent execution
    FOR v_period IN
        SELECT resolution, year, month
        FROM public.get_statistical_history_periods(
            p_resolution := null::public.history_resolution,
            p_valid_from := v_valid_from,
            p_valid_until := v_valid_until
        )
    LOOP
        PERFORM worker.spawn(
            p_command := 'derive_statistical_history_period',
            p_payload := jsonb_build_object(
                'resolution', v_period.resolution::text,
                'year', v_period.year,
                'month', v_period.month
            ),
            p_parent_id := v_task_id
        );
        v_child_count := v_child_count + 1;
    END LOOP;

    RAISE DEBUG 'derive_statistical_history: spawned % period children', v_child_count;
    -- Returns → process_tasks detects children → state='waiting'
END;
$derive_statistical_history$;

-- ============================================================================
-- Cleanup: Remove DSUF period-splitting (data model mismatch)
-- ============================================================================
-- The statistical_unit_facet table is keyed by (valid_from, valid_to, valid_until),
-- NOT by (resolution, year, month). Period splitting causes a facet row spanning
-- N years to be redundantly DELETE/INSERT'd across all overlapping periods.
-- Drop the period procedure and command_registry entry if they exist.

DROP PROCEDURE IF EXISTS worker.derive_statistical_unit_facet_period(jsonb);
DELETE FROM worker.command_registry WHERE command = 'derive_statistical_unit_facet_period';

-- ============================================================================
-- Fix 2b: Keep derive_statistical_unit_facet monolithic
-- ============================================================================
-- DSUF is keyed by (valid_from, valid_to, valid_until), NOT by period.
-- Period splitting causes redundant work: a facet row spanning 5 years
-- overlaps 65 periods, so it would be DELETE/INSERT'd 65 times.
-- At ~1.2s monolithic, parallelism is unnecessary. Revisit with
-- unit_type/unit_id partitioning (Option D) if DSUF exceeds ~5s.

CREATE OR REPLACE PROCEDURE worker.derive_statistical_unit_facet(IN payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $derive_statistical_unit_facet$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
BEGIN
    PERFORM public.statistical_unit_facet_derive(
        p_valid_from := v_valid_from,
        p_valid_until := v_valid_until
    );

    -- Enqueue the next phase
    PERFORM worker.enqueue_derive_statistical_history_facet(
        p_valid_from => v_valid_from,
        p_valid_until => v_valid_until
    );
END;
$derive_statistical_unit_facet$;

-- ============================================================================
-- Fix 2b: Replace derive_statistical_history_facet enqueue with spawn
-- ============================================================================
-- DSHF already splits by period, but uses enqueue (top-level, serial).
-- Convert to spawn() for concurrent child execution.
-- The derive_statistical_history_facet_period handler already exists.

CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_facet(IN payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $derive_statistical_history_facet$
DECLARE
    v_valid_from date := COALESCE((payload->>'valid_from')::date, '-infinity'::date);
    v_valid_until date := COALESCE((payload->>'valid_until')::date, 'infinity'::date);
    v_task_id bigint;
    v_period record;
    v_child_count integer := 0;
BEGIN
    -- Get own task_id for spawning children
    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY id DESC LIMIT 1;

    RAISE DEBUG 'derive_statistical_history_facet: task_id=%, valid_from=%, valid_until=%',
                 v_task_id, v_valid_from, v_valid_until;

    -- No next phase to enqueue (DSHF is the last step in the analytics chain)

    -- Spawn one child per period for concurrent execution
    FOR v_period IN
        SELECT resolution, year, month
        FROM public.get_statistical_history_periods(
            p_resolution := null::public.history_resolution,
            p_valid_from := v_valid_from,
            p_valid_until := v_valid_until
        )
    LOOP
        PERFORM worker.spawn(
            p_command := 'derive_statistical_history_facet_period',
            p_payload := jsonb_build_object(
                'resolution', v_period.resolution::text,
                'year', v_period.year,
                'month', v_period.month
            ),
            p_parent_id := v_task_id
        );
        v_child_count := v_child_count + 1;
    END LOOP;

    RAISE DEBUG 'derive_statistical_history_facet: spawned % period children', v_child_count;
    -- Returns → process_tasks detects children → state='waiting'
END;
$derive_statistical_history_facet$;

END;
