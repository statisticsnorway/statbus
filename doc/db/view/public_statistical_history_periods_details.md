```sql
                        View "public.statistical_history_periods"
   Column   |        Type        | Collation | Nullable | Default | Storage | Description 
------------+--------------------+-----------+----------+---------+---------+-------------
 resolution | history_resolution |           |          |         | plain   | 
 year       | integer            |           |          |         | plain   | 
 month      | integer            |           |          |         | plain   | 
 prev_stop  | date               |           |          |         | plain   | 
 curr_start | date               |           |          |         | plain   | 
 curr_stop  | date               |           |          |         | plain   | 
View definition:
 WITH year_range AS (
         SELECT min(statistical_unit.valid_from) AS start_year,
            LEAST(max(statistical_unit.valid_to), CURRENT_DATE) AS stop_year
           FROM statistical_unit
        )
 SELECT 'year'::history_resolution AS resolution,
    EXTRACT(year FROM series.curr_start)::integer AS year,
    NULL::integer AS month,
    (series.curr_start - '1 day'::interval)::date AS prev_stop,
    series.curr_start::date AS curr_start,
    (series.curr_start + '1 year'::interval - '1 day'::interval)::date AS curr_stop
   FROM year_range,
    LATERAL generate_series(date_trunc('year'::text, year_range.start_year::timestamp with time zone)::date::timestamp with time zone, date_trunc('year'::text, year_range.stop_year::timestamp with time zone)::date::timestamp with time zone, '1 year'::interval) series(curr_start)
UNION ALL
 SELECT 'year-month'::history_resolution AS resolution,
    EXTRACT(year FROM series.curr_start)::integer AS year,
    EXTRACT(month FROM series.curr_start)::integer AS month,
    (series.curr_start - '1 day'::interval)::date AS prev_stop,
    series.curr_start::date AS curr_start,
    (series.curr_start + '1 mon'::interval - '1 day'::interval)::date AS curr_stop
   FROM year_range,
    LATERAL generate_series(date_trunc('month'::text, year_range.start_year::timestamp with time zone)::date::timestamp with time zone, date_trunc('month'::text, year_range.stop_year::timestamp with time zone)::date::timestamp with time zone, '1 mon'::interval) series(curr_start);

```
