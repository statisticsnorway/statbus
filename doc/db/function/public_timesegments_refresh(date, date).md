```sql
CREATE OR REPLACE FUNCTION public.timesegments_refresh(p_valid_after date DEFAULT NULL::date, p_valid_to date DEFAULT NULL::date)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_valid_after date;
    v_valid_to date;
    v_batch_size INT := 5000;
    v_offset INT;
    v_unit_type public.statistical_unit_type;
    v_table_name TEXT;
    v_unit_ids INT[];
BEGIN
    -- Set the date range variables for filtering, defaulting to unbounded
    v_valid_after := COALESCE(p_valid_after, '-infinity'::date);
    v_valid_to := COALESCE(p_valid_to, 'infinity'::date);

    -- Iterate over each statistical unit type
    FOREACH v_unit_type IN ARRAY ARRAY['establishment', 'legal_unit', 'enterprise']::public.statistical_unit_type[]
    LOOP
        v_table_name := v_unit_type::text;
        v_offset := 0;

        -- Process units in batches to manage memory and transaction size
        LOOP
            -- Get a batch of unit IDs to process
            EXECUTE format('SELECT array_agg(id) FROM (SELECT id FROM public.%I ORDER BY id LIMIT %s OFFSET %s) AS sub', v_table_name, v_batch_size, v_offset)
            INTO v_unit_ids;

            -- Exit loop if no more units of this type
            IF v_unit_ids IS NULL OR cardinality(v_unit_ids) = 0 THEN
                EXIT;
            END IF;

            -- Use MERGE to atomically sync the timesegments table with the definition view for the current batch.
            -- This single command handles INSERTs, UPDATEs, and DELETEs.
            MERGE INTO public.timesegments AS t
            USING (
                -- Source: The calculated, correct timesegments from the definition view for this batch.
                SELECT * FROM public.timesegments_def
                WHERE
                    unit_type = v_unit_type
                    AND unit_id = ANY(v_unit_ids)
            ) AS s
            ON (t.unit_type = s.unit_type AND t.unit_id = s.unit_id AND t.valid_after = s.valid_after)
            -- Case 1: The segment exists but its end date has changed. UPDATE it.
            WHEN MATCHED AND t.valid_to IS DISTINCT FROM s.valid_to THEN
                UPDATE SET valid_to = s.valid_to
            -- Case 2: The calculated segment does not exist in the table. INSERT it.
            WHEN NOT MATCHED THEN
                INSERT (unit_type, unit_id, valid_after, valid_to)
                VALUES (s.unit_type, s.unit_id, s.valid_after, s.valid_to)
            -- Case 3: A segment exists in the table but not in the calculated source. DELETE it.
            -- This is scoped to the current batch and the refresh window to avoid unintended deletions.
            WHEN NOT MATCHED BY SOURCE
                AND t.unit_type = v_unit_type
                AND t.unit_id = ANY(v_unit_ids)
                AND daterange(t.valid_after, t.valid_to, '(]') && daterange(v_valid_after, v_valid_to, '(]')
            THEN
                DELETE;

            -- Move to the next batch
            v_offset := v_offset + v_batch_size;
        END LOOP;
    END LOOP;
END;
$function$
```
