```sql
                              View "public.relative_period_with_time"
     Column      |         Type          | Collation | Nullable | Default | Storage  | Description 
-----------------+-----------------------+-----------+----------+---------+----------+-------------
 id              | integer               |           |          |         | plain    | 
 code            | relative_period_code  |           |          |         | plain    | 
 name_when_query | character varying     |           |          |         | extended | 
 name_when_input | character varying     |           |          |         | extended | 
 scope           | relative_period_scope |           |          |         | plain    | 
 active          | boolean               |           |          |         | plain    | 
 valid_on        | date                  |           |          |         | plain    | 
 valid_from      | date                  |           |          |         | plain    | 
 valid_to        | date                  |           |          |         | plain    | 
View definition:
 WITH base_periods AS (
         SELECT relative_period.id,
            relative_period.code,
            relative_period.name_when_query,
            relative_period.name_when_input,
            relative_period.scope,
            relative_period.active,
                CASE relative_period.code
                    WHEN 'today'::relative_period_code THEN CURRENT_DATE::timestamp with time zone
                    WHEN 'year_prev'::relative_period_code THEN date_trunc('year'::text, CURRENT_DATE::timestamp with time zone) - '1 day'::interval
                    WHEN 'year_prev_only'::relative_period_code THEN date_trunc('year'::text, CURRENT_DATE::timestamp with time zone) - '1 day'::interval
                    WHEN 'year_curr'::relative_period_code THEN CURRENT_DATE::timestamp with time zone
                    WHEN 'year_curr_only'::relative_period_code THEN CURRENT_DATE::timestamp with time zone
                    WHEN 'start_of_week_curr'::relative_period_code THEN date_trunc('week'::text, CURRENT_DATE::timestamp with time zone)
                    WHEN 'stop_of_week_prev'::relative_period_code THEN date_trunc('week'::text, CURRENT_DATE::timestamp with time zone) - '1 day'::interval
                    WHEN 'start_of_week_prev'::relative_period_code THEN date_trunc('week'::text, CURRENT_DATE - '7 days'::interval)::timestamp with time zone
                    WHEN 'start_of_month_curr'::relative_period_code THEN date_trunc('month'::text, CURRENT_DATE::timestamp with time zone)
                    WHEN 'stop_of_month_prev'::relative_period_code THEN date_trunc('month'::text, CURRENT_DATE::timestamp with time zone) - '1 day'::interval
                    WHEN 'start_of_month_prev'::relative_period_code THEN date_trunc('month'::text, CURRENT_DATE - '1 mon'::interval)::timestamp with time zone
                    WHEN 'start_of_quarter_curr'::relative_period_code THEN date_trunc('quarter'::text, CURRENT_DATE::timestamp with time zone)
                    WHEN 'stop_of_quarter_prev'::relative_period_code THEN date_trunc('quarter'::text, CURRENT_DATE::timestamp with time zone) - '1 day'::interval
                    WHEN 'start_of_quarter_prev'::relative_period_code THEN date_trunc('quarter'::text, CURRENT_DATE - '3 mons'::interval)::timestamp with time zone
                    WHEN 'start_of_semester_curr'::relative_period_code THEN
                    CASE
                        WHEN EXTRACT(month FROM CURRENT_DATE) <= 6::numeric THEN date_trunc('year'::text, CURRENT_DATE::timestamp with time zone)
                        ELSE date_trunc('year'::text, CURRENT_DATE::timestamp with time zone) + '6 mons'::interval
                    END
                    WHEN 'stop_of_semester_prev'::relative_period_code THEN
                    CASE
                        WHEN EXTRACT(month FROM CURRENT_DATE) <= 6::numeric THEN date_trunc('year'::text, CURRENT_DATE::timestamp with time zone) - '1 day'::interval
                        ELSE date_trunc('year'::text, CURRENT_DATE::timestamp with time zone) + '6 mons'::interval - '1 day'::interval
                    END
                    WHEN 'start_of_semester_prev'::relative_period_code THEN
                    CASE
                        WHEN EXTRACT(month FROM CURRENT_DATE) <= 6::numeric THEN date_trunc('year'::text, CURRENT_DATE::timestamp with time zone) - '6 mons'::interval
                        ELSE date_trunc('year'::text, CURRENT_DATE::timestamp with time zone)
                    END
                    WHEN 'start_of_year_curr'::relative_period_code THEN date_trunc('year'::text, CURRENT_DATE::timestamp with time zone)
                    WHEN 'stop_of_year_prev'::relative_period_code THEN date_trunc('year'::text, CURRENT_DATE::timestamp with time zone) - '1 day'::interval
                    WHEN 'start_of_year_prev'::relative_period_code THEN date_trunc('year'::text, CURRENT_DATE - '1 year'::interval)::timestamp with time zone
                    WHEN 'start_of_quinquennial_curr'::relative_period_code THEN date_trunc('year'::text, CURRENT_DATE - '1 year'::interval * (EXTRACT(year FROM CURRENT_DATE)::integer % 5)::double precision)::timestamp with time zone
                    WHEN 'stop_of_quinquennial_prev'::relative_period_code THEN (date_trunc('year'::text, CURRENT_DATE - '1 year'::interval * (EXTRACT(year FROM CURRENT_DATE)::integer % 5)::double precision) - '1 day'::interval)::timestamp with time zone
                    WHEN 'start_of_quinquennial_prev'::relative_period_code THEN (date_trunc('year'::text, CURRENT_DATE - '1 year'::interval * (EXTRACT(year FROM CURRENT_DATE)::integer % 5)::double precision) - '5 years'::interval)::timestamp with time zone
                    WHEN 'start_of_decade_curr'::relative_period_code THEN date_trunc('year'::text, CURRENT_DATE - '1 year'::interval * (EXTRACT(year FROM CURRENT_DATE)::integer % 10)::double precision)::timestamp with time zone
                    WHEN 'stop_of_decade_prev'::relative_period_code THEN (date_trunc('year'::text, CURRENT_DATE - '1 year'::interval * (EXTRACT(year FROM CURRENT_DATE)::integer % 10)::double precision) - '1 day'::interval)::timestamp with time zone
                    WHEN 'start_of_decade_prev'::relative_period_code THEN (date_trunc('year'::text, CURRENT_DATE - '1 year'::interval * (EXTRACT(year FROM CURRENT_DATE)::integer % 10)::double precision) - '10 years'::interval)::timestamp with time zone
                    ELSE NULL::timestamp with time zone
                END::date AS valid_on,
                CASE relative_period.code
                    WHEN 'today'::relative_period_code THEN CURRENT_DATE
                    WHEN 'year_prev'::relative_period_code THEN date_trunc('year'::text, CURRENT_DATE - '1 year'::interval)::date
                    WHEN 'year_curr'::relative_period_code THEN date_trunc('year'::text, CURRENT_DATE::timestamp with time zone)::date
                    WHEN 'year_prev_only'::relative_period_code THEN date_trunc('year'::text, CURRENT_DATE - '1 year'::interval)::date
                    WHEN 'year_curr_only'::relative_period_code THEN date_trunc('year'::text, CURRENT_DATE::timestamp with time zone)::date
                    ELSE NULL::date
                END AS valid_from,
                CASE relative_period.code
                    WHEN 'today'::relative_period_code THEN 'infinity'::date::timestamp without time zone
                    WHEN 'year_prev'::relative_period_code THEN 'infinity'::date::timestamp without time zone
                    WHEN 'year_curr'::relative_period_code THEN 'infinity'::date::timestamp without time zone
                    WHEN 'year_prev_only'::relative_period_code THEN date_trunc('year'::text, CURRENT_DATE::timestamp with time zone)::date - '1 day'::interval
                    WHEN 'year_curr_only'::relative_period_code THEN date_trunc('year'::text, CURRENT_DATE + '1 year'::interval)::date - '1 day'::interval
                    ELSE NULL::timestamp without time zone
                END::date AS valid_to
           FROM relative_period
        ), dynamic_year_periods AS (
         WITH settings AS (
                 SELECT COALESCE(( SELECT s_1.relative_period_input_years_count
                           FROM public.settings s_1
                         LIMIT 1), 5) AS relative_period_input_years_count
                ), years AS (
                 SELECT ty.year,
                    COALESCE(( SELECT max(timepoints_years.year) AS max
                           FROM timepoints_years), date_part('year'::text, now())::integer) AS max_year
                   FROM timepoints_years ty
                )
         SELECT NULL::integer AS id,
            NULL::relative_period_code AS code,
            y.year::text AS name_when_query,
                CASE
                    WHEN y.year >= (y.max_year - s.relative_period_input_years_count + 1) THEN y.year::text
                    ELSE NULL::text
                END AS name_when_input,
                CASE
                    WHEN y.year >= (y.max_year - s.relative_period_input_years_count + 1) THEN 'input_and_query'::relative_period_scope
                    ELSE 'query'::relative_period_scope
                END AS scope,
            true AS active,
            make_date(y.year, 12, 31) AS valid_on,
            make_date(y.year, 1, 1) AS valid_from,
            make_date(y.year, 12, 31) AS valid_to
           FROM years y,
            settings s
        )
 SELECT base_periods.id,
    base_periods.code,
    base_periods.name_when_query,
    base_periods.name_when_input,
    base_periods.scope,
    base_periods.active,
    base_periods.valid_on,
    base_periods.valid_from,
    base_periods.valid_to
   FROM base_periods
UNION ALL
 SELECT dynamic_year_periods.id,
    dynamic_year_periods.code,
    dynamic_year_periods.name_when_query,
    dynamic_year_periods.name_when_input,
    dynamic_year_periods.scope,
    dynamic_year_periods.active,
    dynamic_year_periods.valid_on,
    dynamic_year_periods.valid_from,
    dynamic_year_periods.valid_to
   FROM dynamic_year_periods;

```
