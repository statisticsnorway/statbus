BEGIN;

CREATE OR REPLACE VIEW public.relative_period_with_time AS
WITH base_periods AS (
    SELECT
        id,
        code,
        name_when_query,
        name_when_input,
        scope,
        active,
        CASE code
            WHEN 'today' THEN current_date
            WHEN 'year_prev' THEN date_trunc('year', current_date) - interval '1 day'
            WHEN 'year_prev_only' THEN date_trunc('year', current_date) - interval '1 day'
            WHEN 'year_curr' THEN current_date
            WHEN 'year_curr_only' THEN current_date
            WHEN 'start_of_week_curr' THEN date_trunc('week', current_date)
            WHEN 'stop_of_week_prev' THEN date_trunc('week', current_date) - interval '1 day'
            WHEN 'start_of_week_prev' THEN date_trunc('week', current_date - interval '1 week')
            WHEN 'start_of_month_curr' THEN date_trunc('month', current_date)
            WHEN 'stop_of_month_prev' THEN (date_trunc('month', current_date) - interval '1 day')
            WHEN 'start_of_month_prev' THEN date_trunc('month', current_date - interval '1 month')
            WHEN 'start_of_quarter_curr' THEN date_trunc('quarter', current_date)
            WHEN 'stop_of_quarter_prev' THEN (date_trunc('quarter', current_date) - interval '1 day')
            WHEN 'start_of_quarter_prev' THEN date_trunc('quarter', current_date - interval '3 months')
            WHEN 'start_of_semester_curr' THEN
                CASE
                    WHEN EXTRACT(month FROM current_date) <= 6 THEN date_trunc('year', current_date)
                    ELSE date_trunc('year', current_date) + interval '6 months'
                END
            WHEN 'stop_of_semester_prev' THEN
                CASE
                    WHEN EXTRACT(month FROM current_date) <= 6 THEN date_trunc('year', current_date) - interval '1 day'
                    ELSE date_trunc('year', current_date) + interval '6 months' - interval '1 day'
                END
            WHEN 'start_of_semester_prev' THEN
                CASE
                    WHEN EXTRACT(month FROM current_date) <= 6 THEN date_trunc('year', current_date) - interval '6 months'
                    ELSE date_trunc('year', current_date)
                END
            WHEN 'start_of_year_curr' THEN date_trunc('year', current_date)
            WHEN 'stop_of_year_prev' THEN (date_trunc('year', current_date) - interval '1 day')
            WHEN 'start_of_year_prev' THEN date_trunc('year', current_date - interval '1 year')
            WHEN 'start_of_quinquennial_curr' THEN date_trunc('year', current_date - interval '1 year' * (EXTRACT(year FROM current_date)::int % 5))
            WHEN 'stop_of_quinquennial_prev' THEN date_trunc('year', current_date - interval '1 year' * (EXTRACT(year FROM current_date)::int % 5)) - interval '1 day'
            WHEN 'start_of_quinquennial_prev' THEN date_trunc('year', current_date - interval '1 year' * (EXTRACT(year FROM current_date)::int % 5)) - interval '5 years'
            WHEN 'start_of_decade_curr' THEN date_trunc('year', current_date - interval '1 year' * (EXTRACT(year FROM current_date)::int % 10))
            WHEN 'stop_of_decade_prev' THEN date_trunc('year', current_date - interval '1 year' * (EXTRACT(year FROM current_date)::int % 10)) - interval '1 day'
            WHEN 'start_of_decade_prev' THEN date_trunc('year', current_date - interval '1 year' * (EXTRACT(year FROM current_date)::int % 10)) - interval '10 years'
            ELSE NULL
        END::DATE AS valid_on,
        CASE code
            WHEN 'today' THEN current_date
            WHEN 'year_prev' THEN date_trunc('year', current_date - interval '1 year')::DATE
            WHEN 'year_curr' THEN date_trunc('year', current_date)::DATE
            WHEN 'year_prev_only' THEN date_trunc('year', current_date - interval '1 year')::DATE
            WHEN 'year_curr_only' THEN date_trunc('year', current_date)::DATE
            ELSE NULL
        END::DATE AS valid_from,
        CASE code
            WHEN 'today' THEN 'infinity'::DATE
            WHEN 'year_prev' THEN 'infinity'::DATE
            WHEN 'year_curr' THEN 'infinity'::DATE
            WHEN 'year_prev_only' THEN date_trunc('year', current_date)::DATE - interval '1 day'
            WHEN 'year_curr_only' THEN date_trunc('year', current_date + interval '1 year')::DATE - interval '1 day'
            ELSE NULL
        END::DATE as valid_to
    FROM public.relative_period
),
dynamic_year_periods AS (
    WITH settings AS (
        SELECT COALESCE((SELECT s.relative_period_input_years_count FROM public.settings s LIMIT 1), 5) AS relative_period_input_years_count
    ), years AS (
        SELECT
            ty.year,
            COALESCE((SELECT MAX(year) FROM public.timepoints_years), date_part('year', now())::int) AS max_year
        FROM public.timepoints_years ty
    )
    SELECT
        NULL::integer AS id,
        NULL::public.relative_period_code AS code,
        y.year::text AS name_when_query,
        CASE
            WHEN y.year >= y.max_year - s.relative_period_input_years_count + 1 THEN y.year::text
            ELSE NULL
        END AS name_when_input,
        CASE
            WHEN y.year >= y.max_year - s.relative_period_input_years_count + 1 THEN 'input_and_query'::public.relative_period_scope
            ELSE 'query'::public.relative_period_scope
        END AS scope,
        true AS active,
        make_date(y.year, 12, 31) AS valid_on,
        make_date(y.year, 1, 1) AS valid_from,
        make_date(y.year, 12, 31) AS valid_to
    FROM years y, settings s
)
SELECT * FROM base_periods
UNION ALL
SELECT * FROM dynamic_year_periods;

END;
