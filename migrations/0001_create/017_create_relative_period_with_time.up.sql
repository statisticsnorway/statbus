\echo public.relative_period_with_time
CREATE VIEW public.relative_period_with_time AS
-- Notice that all input types also has a valid_on date for query,
-- that matches the valid_from if one swiches from input to query
-- that can be used.
SELECT *,
       --
       CASE code
           --
           WHEN 'today' THEN current_date
           WHEN 'year_prev' THEN date_trunc('year', current_date) - interval '1 day'
           WHEN 'year_prev_only'           THEN date_trunc('year', current_date) - interval '1 day'
           WHEN 'year_curr' THEN current_date
           WHEN 'year_curr_only'           THEN current_date
           --
           WHEN 'today' THEN current_date
           WHEN 'start_of_week_curr'     THEN date_trunc('week', current_date)
           WHEN 'stop_of_week_prev'      THEN date_trunc('week', current_date) - interval '1 day'
           WHEN 'start_of_week_prev'     THEN date_trunc('week', current_date - interval '1 week')
           WHEN 'start_of_month_curr'    THEN date_trunc('month', current_date)
           WHEN 'stop_of_month_prev'     THEN (date_trunc('month', current_date) - interval '1 day')
           WHEN 'start_of_month_prev'    THEN date_trunc('month', current_date - interval '1 month')
           WHEN 'start_of_quarter_curr'  THEN date_trunc('quarter', current_date)
           WHEN 'stop_of_quarter_prev'   THEN (date_trunc('quarter', current_date) - interval '1 day')
           WHEN 'start_of_quarter_prev'  THEN date_trunc('quarter', current_date - interval '3 months')
           WHEN 'start_of_semester_curr' THEN
               CASE
                   WHEN EXTRACT(month FROM current_date) <= 6
                   THEN date_trunc('year', current_date)
                   ELSE date_trunc('year', current_date) + interval '6 months'
               END
            WHEN 'stop_of_semester_prev' THEN
                CASE
                    WHEN EXTRACT(month FROM current_date) <= 6
                    THEN date_trunc('year', current_date) - interval '1 day' -- End of December last year
                    ELSE date_trunc('year', current_date) + interval '6 months' - interval '1 day' -- End of June current year
                END
           WHEN 'start_of_semester_prev' THEN
               CASE
                   WHEN EXTRACT(month FROM current_date) <= 6 THEN date_trunc('year', current_date) - interval '6 months'
                   ELSE date_trunc('year', current_date)
               END
           WHEN 'start_of_year_curr'         THEN  date_trunc('year', current_date)
           WHEN 'stop_of_year_prev'          THEN (date_trunc('year', current_date) - interval '1 day')
           WHEN 'start_of_year_prev'         THEN  date_trunc('year', current_date - interval '1 year')

           WHEN 'start_of_quinquennial_curr' THEN date_trunc('year', current_date - interval '1 year' * (EXTRACT(year FROM current_date)::int % 5))
           WHEN 'stop_of_quinquennial_prev'  THEN date_trunc('year', current_date - interval '1 year' * (EXTRACT(year FROM current_date)::int % 5)) - interval '1 day'
           WHEN 'start_of_quinquennial_prev' THEN date_trunc('year', current_date - interval '1 year' * (EXTRACT(year FROM current_date)::int % 5)) - interval '5 years'

           WHEN 'start_of_decade_curr' THEN date_trunc('year', current_date - interval '1 year' * (EXTRACT(year FROM current_date)::int % 10))
           WHEN 'stop_of_decade_prev'  THEN date_trunc('year', current_date - interval '1 year' * (EXTRACT(year FROM current_date)::int % 10)) - interval '1 day'
           WHEN 'start_of_decade_prev' THEN date_trunc('year', current_date - interval '1 year' * (EXTRACT(year FROM current_date)::int % 10)) - interval '10 years'
           ELSE NULL
       END::DATE AS valid_on,
       --
       CASE code
           WHEN 'today'          THEN current_date
           WHEN 'year_prev'      THEN date_trunc('year', current_date - interval '1 year')::DATE
           WHEN 'year_curr'      THEN date_trunc('year', current_date)::DATE
           WHEN 'year_prev_only' THEN date_trunc('year', current_date - interval '1 year')::DATE
           WHEN 'year_curr_only' THEN date_trunc('year', current_date)::DATE
           --
           ELSE NULL
       END::DATE AS valid_from,
       --
       CASE code
           WHEN 'today'          THEN 'infinity'::DATE
           WHEN 'year_prev'      THEN 'infinity'::DATE
           WHEN 'year_curr'      THEN 'infinity'::DATE
           WHEN 'year_prev_only' THEN date_trunc('year', current_date)::DATE - interval '1 day'
           WHEN 'year_curr_only' THEN date_trunc('year', current_date + interval '1 year')::DATE - interval '1 day'
           ELSE NULL
       END::DATE as valid_to
       --
FROM public.relative_period;