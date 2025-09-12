```sql
                   View "public.timesegments_years_def"
 Column |  Type   | Collation | Nullable | Default | Storage | Description 
--------+---------+-----------+----------+---------+---------+-------------
 year   | integer |           |          |         | plain   | 
View definition:
 SELECT DISTINCT year
   FROM ( SELECT generate_series(EXTRACT(year FROM timesegments.valid_from), EXTRACT(year FROM LEAST(timesegments.valid_until - '1 day'::interval, now()::date::timestamp without time zone)), 1::numeric)::integer AS year
           FROM timesegments
          WHERE timesegments.valid_from IS NOT NULL AND timesegments.valid_until IS NOT NULL
        UNION
         SELECT EXTRACT(year FROM now())::integer AS "extract") all_years
  ORDER BY year;

```
