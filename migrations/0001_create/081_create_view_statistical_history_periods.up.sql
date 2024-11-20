\echo public.history_resolution
CREATE TYPE public.history_resolution AS ENUM('year','year-month');

\echo public.statistical_history_periods
CREATE VIEW public.statistical_history_periods AS
WITH year_range AS (
  SELECT
      min(valid_from) AS start_year,
      least(max(valid_to), current_date) AS stop_year
  FROM public.statistical_unit
)
SELECT 'year'::public.history_resolution AS resolution
     , EXTRACT(YEAR FROM curr_start)::INT AS year
     , NULL::INTEGER AS month
     , (series.curr_start - interval '1 day')::DATE AS prev_stop
     , series.curr_start::DATE
     , (series.curr_start + interval '1 year' - interval '1 day')::DATE AS curr_stop
FROM year_range,
LATERAL generate_series(
    date_trunc('year', year_range.start_year)::DATE,
    date_trunc('year', year_range.stop_year)::DATE,
    interval '1 year'
) AS series(curr_start)
UNION ALL
SELECT 'year-month'::public.history_resolution AS resolution
     , EXTRACT(YEAR FROM curr_start)::INT AS year
     , EXTRACT(MONTH FROM curr_start)::INT AS month
     , (series.curr_start - interval '1 day')::DATE AS prev_stop
     , series.curr_start::DATE
     , (series.curr_start + interval '1 month' - interval '1 day')::DATE AS curr_stop
FROM year_range,
LATERAL generate_series(
    date_trunc('month', year_range.start_year)::DATE,
    date_trunc('month', year_range.stop_year)::DATE,
    interval '1 month'
) AS series(curr_start)
;