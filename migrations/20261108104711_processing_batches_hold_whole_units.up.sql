BEGIN;

CREATE OR REPLACE FUNCTION admin.import_job_assign_batch_seq(p_data_table_name text, p_batch_size integer, p_for_processing boolean DEFAULT false, p_new_state import_data_state DEFAULT NULL::import_data_state, p_reset_priority boolean DEFAULT false)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_total_rows INTEGER;
    v_extra_sets TEXT := '';
    v_group_key TEXT;
BEGIN
    -- Build optional SET clauses for atomic multi-column update
    IF p_new_state IS NOT NULL THEN
        v_extra_sets := v_extra_sets || format(', state = %L', p_new_state);
    END IF;
    IF p_reset_priority THEN
        v_extra_sets := v_extra_sets || ', last_completed_priority = 0';
    END IF;

    IF p_for_processing THEN
        -- For processing phase: assign batch_seq only to rows with action = 'use'.
        -- NULL out batch_seq for non-'use' rows. These rows should already be in 'error' state
        -- (set by analyse_external_idents when action='skip'), but we defensively ensure it here
        -- to satisfy the CHECK constraint (which requires batch_seq IS NOT NULL for 'analysing' state).
        EXECUTE format($$UPDATE public.%1$I SET batch_seq = NULL, state = 'error' WHERE action IS DISTINCT FROM 'use' AND state != 'error'$$, p_data_table_name);

        -- The group key a batch keeps whole: the row's legal unit when it has one (an existing legal unit's
        -- rows, and all establishment rows of one legal unit, which share its primary establishment), else
        -- its enterprise (informal establishments share the enterprise's primary), else its unit's
        -- founding_row_id (a new unit's rows). Built from the columns the job's data table has.
        SELECT 'COALESCE(' || string_agg(format('%L || %I', c.prefix, c.column_name), ', ' ORDER BY c.ord)
               || ', ''row:'' || row_id)'
          INTO v_group_key
          FROM (VALUES (1, 'legal_unit_id', 'lu:'), (2, 'enterprise_id', 'en:'), (3, 'founding_row_id', 'unit:'))
               AS c(ord, column_name, prefix)
         WHERE EXISTS (SELECT 1 FROM information_schema.columns AS ic
                        WHERE ic.table_schema = 'public' AND ic.table_name = p_data_table_name
                          AND ic.column_name = c.column_name);
        v_group_key := COALESCE(v_group_key, '''row:'' || row_id');
        
        -- Analysis has populated action since upload-time statistics were collected.
        -- Refresh this column so slot packing plans for the accepted row count.
        -- This phase boundary precedes dispatch of the job's processing batches.
        EXECUTE format($$ANALYZE public.%1$I (action)$$, p_data_table_name);

        -- Each dependency group hashes to one stable import slot. Pack whole slots into row-sized batches:
        -- a large group or slot stays whole even when it exceeds the target batch size. Import group keys
        -- differ from derive unit keys, so sharing its 16,384-slot space does not imply derive locality.
        EXECUTE format($$
            WITH keyed AS (
                SELECT row_id, %4$s AS group_key
                FROM public.%1$I
                WHERE action = 'use'
            ), slotted AS (
                SELECT row_id, abs(hashtext(group_key)::bigint) %% 16384 AS slot
                FROM keyed
            ), slots AS (
                SELECT slot, count(*) AS n
                FROM slotted GROUP BY slot
            ), batched AS (
                SELECT s.slot,
                       floor((sum(s.n) OVER (ORDER BY s.slot) - s.n) / %2$L) + 1 AS batch_num
                FROM slots AS s
            ), numbered AS (
                SELECT s.row_id, b.batch_num::integer
                FROM slotted AS s JOIN batched AS b USING (slot)
            )
            UPDATE public.%1$I dt
            SET batch_seq = numbered.batch_num %3$s
            FROM numbered
            WHERE dt.row_id = numbered.row_id
        $$, p_data_table_name, p_batch_size, v_extra_sets, v_group_key);
    ELSE
        -- For analysis phase: assign batch_seq to ALL rows, optionally updating state atomically.
        EXECUTE format($$
            UPDATE public.%1$I
            SET batch_seq = ((row_id - 1) / %2$L + 1)::INTEGER %3$s
        $$, p_data_table_name, p_batch_size, v_extra_sets);
    END IF;
    
    GET DIAGNOSTICS v_total_rows = ROW_COUNT;
    RETURN v_total_rows;
END;
$function$
;

END;
