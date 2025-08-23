```sql
CREATE OR REPLACE FUNCTION public.timesegments_refresh(p_valid_after date DEFAULT NULL::date, p_valid_to date DEFAULT NULL::date)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_batch_size INT := 50000;
    v_offset INT;
    v_unit_type public.statistical_unit_type;
    v_table_name TEXT;
    v_unit_ids INT[];
BEGIN
    TRUNCATE public.timesegments;

    FOREACH v_unit_type IN ARRAY ARRAY['establishment', 'legal_unit', 'enterprise']::public.statistical_unit_type[]
    LOOP
        v_table_name := v_unit_type::text;

        v_offset := 0;
        LOOP
            -- Get a batch of unit IDs
            EXECUTE format('SELECT array_agg(id) FROM (SELECT id FROM public.%I ORDER BY id LIMIT %s OFFSET %s) AS sub', v_table_name, v_batch_size, v_offset)
            INTO v_unit_ids;

            -- If no IDs are returned, we are done with this unit type
            IF v_unit_ids IS NULL OR cardinality(v_unit_ids) = 0 THEN
                EXIT;
            END IF;

            -- Generate and insert timesegments for this batch
            INSERT INTO public.timesegments
            SELECT *
            FROM public.timesegments_def
            WHERE unit_type = v_unit_type AND unit_id = ANY(v_unit_ids);

            v_offset := v_offset + v_batch_size;
        END LOOP;
    END LOOP;
END;
$function$
```
