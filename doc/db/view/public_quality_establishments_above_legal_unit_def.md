```sql
                   View "public.quality_establishments_above_legal_unit_def"
   Column    |         Type          | Collation | Nullable | Default | Storage  | Description 
-------------+-----------------------+-----------+----------+---------+----------+-------------
 unit_type   | statistical_unit_type |           |          |         | plain    | 
 unit_id     | integer               |           |          |         | plain    | 
 valid_from  | date                  |           |          |         | plain    | 
 valid_until | date                  |           |          |         | plain    | 
 stats       | jsonb                 |           |          |         | extended | 
View definition:
 SELECT unit_type,
    unit_id,
    valid_from,
    valid_until,
    jsonb_object_agg(stat_code, jsonb_build_object('legal_unit', legal_unit_value, 'establishments_sum', establishments_sum, 'establishments', establishment_count)) AS stats
   FROM legal_unit_establishment_stat_comparison c
  WHERE legal_unit_value < establishments_sum
  GROUP BY unit_type, unit_id, valid_from, valid_until;
Options: security_invoker=on

```

**Comment:** The rule of the quality check public.quality_establishments_above_legal_unit: a summed stat where the legal unit's own value is below its counted establishments' sum.
