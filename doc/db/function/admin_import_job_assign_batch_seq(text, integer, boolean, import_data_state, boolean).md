```sql
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
        
        -- Re-assign batch_seq to 'use' rows, optionally updating state and priority atomically.
        -- A batch holds whole groups (STATBUS-591): each batch is one transaction that temporal_merges its
        -- units and demotes a legal unit's or enterprise's primary establishment, so two batches must not
        -- share a group. Rows are ordered by the group key's slot (the 16,384 slots derive hashes units
        -- into), then group, then row; a batch closes at the first group boundary at or after p_batch_size
        -- rows, so a batch is a run of slots and no group is split.
        EXECUTE format($$
            WITH keyed AS (
                SELECT row_id, %4$s AS group_key
                FROM public.%1$I
                WHERE action = 'use'
            ), ordered AS (
                SELECT row_id, group_key,
                       row_number() OVER (ORDER BY abs(hashtext(group_key)) %% 16384, group_key, row_id) AS rn
                FROM keyed
            ), groups AS (
                SELECT group_key, min(rn) AS first_rn, count(*) AS n
                FROM ordered GROUP BY group_key
            ), batched AS (
                -- A group's batch: the rows of all groups before it, divided by p_batch_size. A batch can
                -- exceed p_batch_size by less than one group.
                SELECT g.group_key,
                       sum(g.n) OVER (ORDER BY g.first_rn) - g.n AS rows_before
                FROM groups AS g
            ), numbered AS (
                SELECT o.row_id, (b.rows_before / %2$L + 1)::INTEGER AS batch_num
                FROM ordered AS o JOIN batched AS b USING (group_key)
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
```
