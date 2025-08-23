```sql
                   View "public.timesegments_years_def"
 Column |  Type   | Collation | Nullable | Default | Storage | Description 
--------+---------+-----------+----------+---------+---------+-------------
 year   | integer |           |          |         | plain   | 
View definition:
 SELECT DISTINCT year
   FROM ( SELECT generate_series(EXTRACT(year FROM timesegments.valid_after + '1 day'::interval), EXTRACT(year FROM LEAST(timesegments.valid_to, now()::date)), 1::numeric)::integer AS year
           FROM timesegments
          WHERE timesegments.valid_after IS NOT NULL AND timesegments.valid_to IS NOT NULL
        UNION
         SELECT EXTRACT(year FROM now())::integer AS "extract") all_years
  ORDER BY year;

```
