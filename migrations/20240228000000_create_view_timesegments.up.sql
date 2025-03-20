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
CREATE INDEX IF NOT EXISTS idx_timesegments_unit_type_valid_after ON public.timesegments
    (unit_type, valid_after);
CREATE INDEX IF NOT EXISTS idx_timesegments_valid_period ON public.timesegments
    (valid_after, valid_to);
CREATE INDEX IF NOT EXISTS idx_timesegments_unit_type_unit_id ON public.timesegments
    (unit_type, unit_id);

-- Create a function to refresh the timesegments table
CREATE OR REPLACE FUNCTION public.timesegments_refresh(
    p_valid_after date DEFAULT NULL,
    p_valid_to date DEFAULT NULL
) RETURNS void LANGUAGE plpgsql AS $timesegments_refresh$
BEGIN
    -- Incremental refresh: delete affected records from the main table
    DELETE FROM public.timesegments
    WHERE (p_valid_after IS NULL OR valid_after >= p_valid_after OR valid_to >= p_valid_after)
    AND (p_valid_to IS NULL OR valid_after <= p_valid_to OR valid_to <= p_valid_to);

    -- Insert directly from the definition view with filtering
    INSERT INTO public.timesegments
    SELECT * FROM public.timesegments_def
    WHERE (p_valid_after IS NULL OR valid_after >= p_valid_after OR valid_to >= p_valid_after)
    AND (p_valid_to IS NULL OR valid_after <= p_valid_to OR valid_to <= p_valid_to);
END;
$timesegments_refresh$;

-- Initial population of the timesegments table
SELECT public.timesegments_refresh();

END;
