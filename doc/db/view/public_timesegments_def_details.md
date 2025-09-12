```sql
                                View "public.timesegments_def"
   Column    |         Type          | Collation | Nullable | Default | Storage | Description 
-------------+-----------------------+-----------+----------+---------+---------+-------------
 unit_type   | statistical_unit_type |           |          |         | plain   | 
 unit_id     | integer               |           |          |         | plain   | 
 valid_from  | date                  |           |          |         | plain   | 
 valid_until | date                  |           |          |         | plain   | 
View definition:
 WITH timesegments_with_trailing_point AS (
         SELECT timepoints.unit_type,
            timepoints.unit_id,
            timepoints.timepoint AS valid_from,
            lead(timepoints.timepoint) OVER (PARTITION BY timepoints.unit_type, timepoints.unit_id ORDER BY timepoints.timepoint) AS valid_until
           FROM timepoints
        )
 SELECT unit_type,
    unit_id,
    valid_from,
    valid_until
   FROM timesegments_with_trailing_point
  WHERE valid_until IS NOT NULL
  ORDER BY unit_type, unit_id, valid_from;

```
