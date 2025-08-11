BEGIN;

-- Create the definition view that contains the logic for generating timesegments
CREATE OR REPLACE VIEW public.timesegments_def AS
  WITH timesegments_with_trailing_point AS (
      SELECT
          unit_type,
          unit_id,
          timepoint AS valid_after,
          -- The LEAD window function looks ahead to the next row in the ordered partition
          -- and returns the value of timepoint from that row.
          -- PARTITION BY unit_type, unit_id: Groups rows by unit_type and unit_id
          -- ORDER BY timepoint: Orders rows within each partition by timepoint
          -- This creates time segments where valid_to is the start time of the next segment,
          -- effectively making each segment valid from valid_after until valid_to
          LEAD(timepoint) OVER (PARTITION BY unit_type, unit_id ORDER BY timepoint) AS valid_to
      FROM public.timepoints
  )
  -- Remove the last lonely started but unfinished segment.
  SELECT *
  FROM timesegments_with_trailing_point
  WHERE valid_to IS NOT NULL
  ORDER BY unit_type, unit_id, valid_after;


DROP TABLE IF EXISTS public.timesegments;
-- Create the physical table to store timesegments
CREATE TABLE public.timesegments AS
SELECT * FROM public.timesegments_def
WHERE FALSE;

-- Add constraints and structure to the table
ALTER TABLE public.timesegments
    ALTER COLUMN unit_type SET NOT NULL,
    ALTER COLUMN unit_id SET NOT NULL,
    ALTER COLUMN valid_after SET NOT NULL,
    ALTER COLUMN valid_to SET NOT NULL,
    ADD PRIMARY KEY (unit_type, unit_id, valid_after);

-- Create indices to optimize queries
CREATE INDEX IF NOT EXISTS idx_timesegments_daterange ON public.timesegments
    USING gist (daterange(valid_after, valid_to, '(]'));
CREATE INDEX IF NOT EXISTS idx_timesegments_unit_type_id_valid_after ON public.timesegments
    (unit_type, unit_id, valid_after);
CREATE INDEX IF NOT EXISTS idx_timesegments_unit_type_id_period ON public.timesegments
    (unit_type, unit_id, valid_after, valid_to);
CREATE INDEX IF NOT EXISTS idx_timesegments_unit_type_unit_id ON public.timesegments
    (unit_type, unit_id);
CREATE INDEX IF NOT EXISTS idx_timesegments_unit_type ON public.timesegments
    (unit_type);

-- Create a function to refresh the timesegments table
CREATE OR REPLACE FUNCTION public.timesegments_refresh(
    p_valid_after date DEFAULT NULL,
    p_valid_to date DEFAULT NULL
) RETURNS void LANGUAGE plpgsql AS $timesegments_refresh$
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
$timesegments_refresh$;

-- Initial population of the timesegments table
SELECT public.timesegments_refresh();

END;
