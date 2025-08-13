```sql
                    View "public.timepoints_years_def"
 Column |  Type   | Collation | Nullable | Default | Storage | Description 
--------+---------+-----------+----------+---------+---------+-------------
 year   | integer |           |          |         | plain   | 
View definition:
 SELECT DISTINCT EXTRACT(year FROM timepoint)::integer AS year
   FROM timepoints
  WHERE timepoint IS NOT NULL AND timepoint <> 'infinity'::date
  ORDER BY (EXTRACT(year FROM timepoint)::integer);

```
