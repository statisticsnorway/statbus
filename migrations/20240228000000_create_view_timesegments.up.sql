BEGIN;

-- Create the definition view that contains the logic for generating timesegments
CREATE OR REPLACE VIEW public.timesegments_def AS
  WITH timesegments_with_trailing_point AS (
      SELECT
          unit_type,
          unit_id,
          timepoint AS valid_from,
          -- The LEAD window function looks ahead to the next row in the ordered partition
          -- and returns the value of timepoint from that row.
          -- PARTITION BY unit_type, unit_id: Groups rows by unit_type and unit_id
          -- ORDER BY timepoint: Orders rows within each partition by timepoint
          -- This creates time segments where valid_until is the start time of the next segment,
          -- effectively making each segment valid from valid_from until valid_until
          LEAD(timepoint) OVER (PARTITION BY unit_type, unit_id ORDER BY timepoint) AS valid_until
      FROM public.timepoints
  )
  -- Remove the last lonely started but unfinished segment.
  SELECT *
  FROM timesegments_with_trailing_point
  WHERE valid_until IS NOT NULL
  ORDER BY unit_type, unit_id, valid_from;


DROP TABLE IF EXISTS public.timesegments;
-- Create the physical table to store timesegments
CREATE TABLE public.timesegments AS
SELECT * FROM public.timesegments_def
WHERE FALSE;

-- Add constraints and structure to the table
ALTER TABLE public.timesegments
    ALTER COLUMN unit_type SET NOT NULL,
    ALTER COLUMN unit_id SET NOT NULL,
    ALTER COLUMN valid_from SET NOT NULL,
    ALTER COLUMN valid_until SET NOT NULL,
    ADD PRIMARY KEY (unit_type, unit_id, valid_from);

-- Create indices to optimize queries
-- This composite index is more efficient for queries that filter by unit_type and unit_id along with the date range.
CREATE INDEX IF NOT EXISTS idx_timesegments_unit_daterange ON public.timesegments
    USING gist (daterange(valid_from, valid_until, '[)'), unit_type, unit_id);
CREATE INDEX IF NOT EXISTS idx_timesegments_unit_type_id_valid_from ON public.timesegments
    (unit_type, unit_id, valid_from);
CREATE INDEX IF NOT EXISTS idx_timesegments_unit_type_id_period ON public.timesegments
    (unit_type, unit_id, valid_from, valid_until);
CREATE INDEX IF NOT EXISTS idx_timesegments_unit_type_unit_id ON public.timesegments
    (unit_type, unit_id);
CREATE INDEX IF NOT EXISTS idx_timesegments_unit_type ON public.timesegments
    (unit_type);

-- Create a function to refresh the timesegments table
CREATE OR REPLACE PROCEDURE public.timesegments_refresh(
    p_establishment_id_ranges int4multirange DEFAULT NULL,
    p_legal_unit_id_ranges int4multirange DEFAULT NULL,
    p_enterprise_id_ranges int4multirange DEFAULT NULL
)
LANGUAGE plpgsql AS $procedure$
BEGIN
    ANALYZE public.timepoints;

    IF p_establishment_id_ranges IS NULL AND p_legal_unit_id_ranges IS NULL AND p_enterprise_id_ranges IS NULL THEN
        -- Full refresh
        DELETE FROM public.timesegments;
        INSERT INTO public.timesegments SELECT * FROM public.timesegments_def;
    ELSE
        -- Partial refresh
        IF p_establishment_id_ranges IS NOT NULL THEN
            DELETE FROM public.timesegments WHERE unit_type = 'establishment' AND unit_id <@ p_establishment_id_ranges;
            INSERT INTO public.timesegments SELECT * FROM public.timesegments_def WHERE unit_type = 'establishment' AND unit_id <@ p_establishment_id_ranges;
        END IF;
        IF p_legal_unit_id_ranges IS NOT NULL THEN
            DELETE FROM public.timesegments WHERE unit_type = 'legal_unit' AND unit_id <@ p_legal_unit_id_ranges;
            INSERT INTO public.timesegments SELECT * FROM public.timesegments_def WHERE unit_type = 'legal_unit' AND unit_id <@ p_legal_unit_id_ranges;
        END IF;
        IF p_enterprise_id_ranges IS NOT NULL THEN
            DELETE FROM public.timesegments WHERE unit_type = 'enterprise' AND unit_id <@ p_enterprise_id_ranges;
            INSERT INTO public.timesegments SELECT * FROM public.timesegments_def WHERE unit_type = 'enterprise' AND unit_id <@ p_enterprise_id_ranges;
        END IF;
    END IF;

    ANALYZE public.timesegments;
END;
$procedure$;

-- Initial population of the timesegments table
CALL public.timesegments_refresh();

--
-- timesegments_years
--
CREATE OR REPLACE VIEW public.timesegments_years_def AS
SELECT DISTINCT year
FROM (
    SELECT generate_series(
        EXTRACT(YEAR FROM valid_from), -- Segment starts on valid_from (inclusive)
        EXTRACT(YEAR FROM LEAST(valid_until - interval '1 day', now()::date)),   -- Up to current year for open segments
        1
    )::integer AS year
    FROM public.timesegments
    WHERE valid_from IS NOT NULL AND valid_until IS NOT NULL
    UNION
    -- Ensure the current year is always included in the list
    SELECT EXTRACT(YEAR FROM now())::integer
) AS all_years
ORDER BY year;

CREATE TABLE public.timesegments_years (year INTEGER PRIMARY KEY);

CREATE OR REPLACE PROCEDURE public.timesegments_years_refresh()
LANGUAGE plpgsql AS $procedure$
BEGIN
    -- Create a temporary table with the new data from the definition view
    CREATE TEMPORARY TABLE temp_timesegments_years ON COMMIT DROP AS
    SELECT * FROM public.timesegments_years_def;

    -- Delete years that are in the main table but not in the new set
    DELETE FROM public.timesegments_years t
    WHERE NOT EXISTS (
        SELECT 1 FROM temp_timesegments_years tt
        WHERE tt.year = t.year
    );

    -- Insert new years that are in the new set but not in the main table
    INSERT INTO public.timesegments_years (year)
    SELECT tt.year
    FROM temp_timesegments_years tt
    WHERE NOT EXISTS (
        SELECT 1 FROM public.timesegments_years t
        WHERE t.year = tt.year
    );

    -- The temporary table is dropped automatically on commit, but we drop it
    -- explicitly to be safe in transactional testing environments.
    DROP TABLE temp_timesegments_years;
END;
$procedure$;

CALL public.timesegments_years_refresh();

END;
