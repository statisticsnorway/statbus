BEGIN;

CREATE VIEW public.timesegments AS
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
  ORDER BY unit_type, unit_id, valid_after
;

END;
