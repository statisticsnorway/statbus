```sql
                    View "public.timepoints_years_def"
 Column |  Type   | Collation | Nullable | Default | Storage | Description 
--------+---------+-----------+----------+---------+---------+-------------
 year   | integer |           |          |         | plain   | 
View definition:
 SELECT DISTINCT year
   FROM ( SELECT EXTRACT(year FROM
                CASE
                    WHEN EXTRACT(month FROM timepoints.timepoint) = 1::numeric AND EXTRACT(day FROM timepoints.timepoint) = 1::numeric THEN timepoints.timepoint - '1 day'::interval
                    ELSE timepoints.timepoint::timestamp without time zone
                END)::integer AS year
           FROM timepoints
          WHERE timepoints.timepoint IS NOT NULL AND timepoints.timepoint <> 'infinity'::date
        UNION
         SELECT EXTRACT(year FROM now())::integer AS "extract") all_years
  ORDER BY year;

```
