\echo public.timesegments
CREATE VIEW public.timesegments AS
  WITH timesegments_with_trailing_point AS (
      SELECT
          unit_type,
          unit_id,
          timepoint AS valid_after,
          LEAD(timepoint) OVER (PARTITION BY unit_type, unit_id ORDER BY timepoint) AS valid_to
      FROM public.timepoints
  )
  -- Remove the last lonely started but unfinished segment.
  SELECT *
  FROM timesegments_with_trailing_point
  WHERE valid_to IS NOT NULL
  ORDER BY unit_type, unit_id, valid_after
;