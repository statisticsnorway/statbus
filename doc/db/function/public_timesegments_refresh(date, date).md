```sql
CREATE OR REPLACE FUNCTION public.timesegments_refresh(p_valid_after date DEFAULT NULL::date, p_valid_to date DEFAULT NULL::date)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_valid_after date;
    v_valid_to date;
BEGIN
    -- Set the date range variables for filtering
    v_valid_after := COALESCE(p_valid_after, '-infinity'::date);
    v_valid_to := COALESCE(p_valid_to, 'infinity'::date);
    
    -- Create a temporary table with the new data
    CREATE TEMPORARY TABLE temp_timesegments ON COMMIT DROP AS
    SELECT * FROM public.timesegments_def
    WHERE after_to_overlaps(valid_after, valid_to, v_valid_after, v_valid_to);
    
    -- Delete records that exist in the main table but not in the temp table
    DELETE FROM public.timesegments ts
    WHERE after_to_overlaps(ts.valid_after, ts.valid_to, v_valid_after, v_valid_to)
    AND NOT EXISTS (
        SELECT 1 FROM temp_timesegments tts
        WHERE tts.unit_type = ts.unit_type
        AND tts.unit_id = ts.unit_id
        AND tts.valid_after = ts.valid_after
        AND tts.valid_to = ts.valid_to
    );
    
    -- Insert records that exist in the temp table but not in the main table
    INSERT INTO public.timesegments
    SELECT tts.* FROM temp_timesegments tts
    WHERE NOT EXISTS (
        SELECT 1 FROM public.timesegments ts
        WHERE ts.unit_type = tts.unit_type
        AND ts.unit_id = tts.unit_id
        AND ts.valid_after = tts.valid_after
        AND ts.valid_to = ts.valid_to
    );
    
    -- Drop the temporary table
    DROP TABLE temp_timesegments;
END;
$function$
```
