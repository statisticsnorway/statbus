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
CREATE INDEX IF NOT EXISTS idx_timesegments_daterange ON public.timesegments
    USING gist (daterange(valid_from, valid_until, '[)'));
CREATE INDEX IF NOT EXISTS idx_timesegments_unit_type_id_valid_from ON public.timesegments
    (unit_type, unit_id, valid_from);
CREATE INDEX IF NOT EXISTS idx_timesegments_unit_type_id_period ON public.timesegments
    (unit_type, unit_id, valid_from, valid_until);
CREATE INDEX IF NOT EXISTS idx_timesegments_unit_type_unit_id ON public.timesegments
    (unit_type, unit_id);
CREATE INDEX IF NOT EXISTS idx_timesegments_unit_type ON public.timesegments
    (unit_type);

-- Create a function to refresh the timesegments table
CREATE OR REPLACE PROCEDURE public.timesegments_refresh(p_unit_ids int[] DEFAULT NULL, p_unit_type public.statistical_unit_type DEFAULT NULL)
LANGUAGE plpgsql AS $procedure$
DECLARE
    v_batch_size INT := 50000; v_unit_type public.statistical_unit_type;
    v_min_id int; v_max_id int; v_start_id int; v_end_id int;
BEGIN
    IF p_unit_ids IS NULL AND p_unit_type IS NULL THEN TRUNCATE public.timesegments; END IF;
    FOREACH v_unit_type IN ARRAY ARRAY['establishment', 'legal_unit', 'enterprise']::public.statistical_unit_type[] LOOP
        IF p_unit_type IS NOT NULL AND v_unit_type IS DISTINCT FROM p_unit_type THEN CONTINUE; END IF;

        SELECT MIN(unit_id), MAX(unit_id) INTO v_min_id, v_max_id FROM public.timepoints WHERE unit_type = v_unit_type;
        IF v_min_id IS NULL THEN CONTINUE; END IF;

        FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_start_id := i;
            v_end_id := i + v_batch_size - 1;

            DELETE FROM public.timesegments WHERE unit_type = v_unit_type AND unit_id BETWEEN v_start_id AND v_end_id;
            INSERT INTO public.timesegments SELECT * FROM public.timesegments_def
            WHERE unit_type = v_unit_type AND unit_id BETWEEN v_start_id AND v_end_id AND valid_until IS NOT NULL;
        END LOOP;
    END LOOP;
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

CREATE OR REPLACE FUNCTION public.timesegments_years_refresh()
RETURNS void LANGUAGE plpgsql AS $function$
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
$function$;

SELECT public.timesegments_years_refresh();

END;
