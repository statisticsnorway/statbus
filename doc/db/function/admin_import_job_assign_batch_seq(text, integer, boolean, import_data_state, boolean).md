```sql
CREATE OR REPLACE FUNCTION admin.import_job_assign_batch_seq(p_data_table_name text, p_batch_size integer, p_for_processing boolean DEFAULT false, p_new_state import_data_state DEFAULT NULL::import_data_state, p_reset_priority boolean DEFAULT false)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_total_rows INTEGER;
    v_extra_sets TEXT := '';
    v_group_key TEXT;
    v_job_mode public.import_mode;
BEGIN
    -- Build optional SET clauses for atomic multi-column update.
    IF p_new_state IS NOT NULL THEN
        v_extra_sets := v_extra_sets || format(', state = %L', p_new_state);
    END IF;
    IF p_reset_priority THEN
        v_extra_sets := v_extra_sets || ', last_completed_priority = 0';
    END IF;

    IF p_for_processing THEN
        EXECUTE format($$UPDATE public.%1$I SET batch_seq = NULL, state = 'error' WHERE action IS DISTINCT FROM 'use' AND state != 'error'$$, p_data_table_name);

        SELECT (job.definition_snapshot#>>'{import_definition,mode}')::public.import_mode
          INTO v_job_mode
          FROM public.import_job AS job
         WHERE job.data_table_name = p_data_table_name
         ORDER BY job.id DESC
         LIMIT 1;

        -- Primary-LU demotion writes other LUs of the enterprise, so that is the LU job's
        -- shared dependency. Formal ES rows share primary selection at their LU parent.
        -- Informal ES rows share primary selection at their enterprise parent. New units
        -- without an existing parent retain their founding-row dependency.
        SELECT 'COALESCE(' || string_agg(format('%L || %I', c.prefix, c.column_name), ', ' ORDER BY
                   CASE WHEN v_job_mode IN ('legal_unit', 'establishment_informal')
                        THEN CASE c.column_name WHEN 'enterprise_id' THEN 1 WHEN 'legal_unit_id' THEN 2 ELSE c.ord END
                        ELSE c.ord END)
               || ', ''row:'' || row_id)'
          INTO v_group_key
          FROM (VALUES (1, 'legal_unit_id', 'lu:'), (2, 'enterprise_id', 'en:'), (3, 'founding_row_id', 'unit:'))
               AS c(ord, column_name, prefix)
         WHERE EXISTS (SELECT 1 FROM information_schema.columns AS ic
                        WHERE ic.table_schema = 'public' AND ic.table_name = p_data_table_name
                          AND ic.column_name = c.column_name);
        v_group_key := COALESCE(v_group_key, '''row:'' || row_id');

        -- Refresh accepted-row estimates at the analysis/processing boundary.
        EXECUTE format($$ANALYZE public.%1$I (action)$$, p_data_table_name);

        -- Pack whole stable slots, including oversized dependencies, toward the row target.
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
