```sql
CREATE OR REPLACE FUNCTION admin.import_job_assign_batch_seq(p_data_table_name text, p_batch_size integer, p_for_processing boolean DEFAULT false)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_total_rows INTEGER;
BEGIN
    IF p_for_processing THEN
        -- For processing phase: assign batch_seq only to rows with action = 'use'.
        -- First NULL out all batch_seq, then re-assign to relevant rows.
        EXECUTE format($$UPDATE public.%1$I SET batch_seq = NULL$$, p_data_table_name);
        
        EXECUTE format($$
            WITH numbered AS (
                SELECT row_id, 
                       ((row_number() OVER (ORDER BY row_id) - 1) / %2$L + 1)::INTEGER as batch_num
                FROM public.%1$I
                WHERE action = 'use'
            )
            UPDATE public.%1$I dt
            SET batch_seq = numbered.batch_num
            FROM numbered
            WHERE dt.row_id = numbered.row_id
        $$, p_data_table_name, p_batch_size);
    ELSE
        -- For analysis phase: assign batch_seq to ALL rows.
        EXECUTE format($$
            UPDATE public.%1$I
            SET batch_seq = ((row_id - 1) / %2$L + 1)::INTEGER
        $$, p_data_table_name, p_batch_size);
    END IF;
    
    GET DIAGNOSTICS v_total_rows = ROW_COUNT;
    RETURN v_total_rows;
END;
$function$
```
