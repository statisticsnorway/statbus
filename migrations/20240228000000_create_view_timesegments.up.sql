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
