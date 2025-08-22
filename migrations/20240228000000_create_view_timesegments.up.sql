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
$timesegments_refresh$;

-- Initial population of the timesegments table
SELECT public.timesegments_refresh();

--
-- timesegments_years
--
CREATE OR REPLACE VIEW public.timesegments_years_def AS
SELECT DISTINCT year
FROM (
    SELECT generate_series(
        EXTRACT(YEAR FROM valid_after + interval '1 day'), -- Segment starts the day after valid_after
        EXTRACT(YEAR FROM LEAST(valid_to, now()::date)),   -- Up to current year for open segments
        1
    )::integer AS year
    FROM public.timesegments
    WHERE valid_after IS NOT NULL AND valid_to IS NOT NULL
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
