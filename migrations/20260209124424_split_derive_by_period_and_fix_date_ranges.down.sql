-- Down Migration 20260209124424: split_derive_by_period_and_fix_date_ranges
BEGIN;

-- ============================================================================
-- DOWN: Restore original procedures and drop new objects
-- ============================================================================

-- Drop new period handler procedures
DROP PROCEDURE IF EXISTS worker.derive_statistical_history_period(jsonb);

-- Remove new command registry entries
DELETE FROM worker.command_registry
WHERE command IN ('derive_statistical_history_period');

-- Note: derive_statistical_unit_facet_period was dropped in the up migration
-- but the down restores the monolithic DSUF procedure below, which is the
-- pre-migration state. The period procedure did not exist before this migration.

-- Restore original command_check_table (enterprise + external_ident combined with NULL dates)
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
  CASE v_table_name
    WHEN 'enterprise', 'external_ident' THEN
      v_valid_columns := 'NULL::DATE AS valid_from, NULL::DATE AS valid_to, NULL::DATE AS valid_until';
    WHEN 'establishment', 'legal_unit', 'activity', 'location', 'contact', 'stat_for_unit' THEN
      v_valid_columns := 'valid_from, valid_to, valid_until';
    ELSE
      RAISE EXCEPTION 'Unknown table: %', v_table_name;
  END CASE;

  -- Find changed rows using a wraparound-safe check.
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
    PERFORM worker.enqueue_derive_statistical_unit(
      p_establishment_id_ranges := public.array_to_int4multirange(v_establishment_ids),
      p_legal_unit_id_ranges := public.array_to_int4multirange(v_legal_unit_ids),
      p_enterprise_id_ranges := public.array_to_int4multirange(v_enterprise_ids),
      p_valid_from := v_valid_from,
      p_valid_until := v_valid_until
    );
  END IF;

  INSERT INTO worker.last_processed (table_name, transaction_id)
  VALUES (v_table_name, txid_current())
  ON CONFLICT (table_name)
  DO UPDATE SET transaction_id = EXCLUDED.transaction_id;
END;
$command_check_table$;

-- Restore original derive_statistical_history (monolithic)
CREATE OR REPLACE PROCEDURE worker.derive_statistical_history(IN payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $derive_statistical_history$
DECLARE
    v_valid_from date = (payload->>'valid_from')::date;
    v_valid_until date = (payload->>'valid_until')::date;
BEGIN
  PERFORM public.statistical_history_derive(
    p_valid_from := v_valid_from,
    p_valid_until := v_valid_until
  );

  -- Enqueue the next phase
  PERFORM worker.enqueue_derive_statistical_unit_facet(
    p_valid_from => v_valid_from,
    p_valid_until => v_valid_until
  );
END;
$derive_statistical_history$;

-- Restore original derive_statistical_unit_facet (monolithic)
CREATE OR REPLACE PROCEDURE worker.derive_statistical_unit_facet(IN payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $derive_statistical_unit_facet$
DECLARE
    v_valid_from date = (payload->>'valid_from')::date;
    v_valid_until date = (payload->>'valid_until')::date;
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

-- Restore original derive_statistical_history_facet (enqueue-based, not spawn-based)
CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_facet(IN payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $derive_statistical_history_facet$
DECLARE
    v_valid_from date := COALESCE((payload->>'valid_from')::date, '-infinity'::date);
    v_valid_until date := COALESCE((payload->>'valid_until')::date, 'infinity'::date);
    v_period RECORD;
    v_enqueued_count integer := 0;
BEGIN
    RAISE DEBUG 'Enqueueing statistical_history_facet periods for valid_from=%, valid_until=%',
                 v_valid_from, v_valid_until;

    -- Enqueue a task for each period
    FOR v_period IN
        SELECT resolution, year, month
        FROM public.get_statistical_history_periods(
            p_resolution := null::public.history_resolution,
            p_valid_from := v_valid_from,
            p_valid_until := v_valid_until
        )
    LOOP
        PERFORM worker.enqueue_derive_statistical_history_facet_period(
            v_period.resolution,
            v_period.year,
            v_period.month
        );
        v_enqueued_count := v_enqueued_count + 1;
    END LOOP;

    RAISE DEBUG 'Enqueued % period tasks for statistical_history_facet', v_enqueued_count;
END;
$derive_statistical_history_facet$;

END;
