```sql
                     View "public.pipeline_step_weight"
 Column |  Type   | Collation | Nullable | Default | Storage  | Description 
--------+---------+-----------+----------+---------+----------+-------------
 phase  | text    |           |          |         | extended | 
 step   | text    |           |          |         | extended | 
 weight | integer |           |          |         | plain    | 
 seq    | integer |           |          |         | plain    | 
View definition:
 SELECT pipeline_step_weight.phase::text AS phase,
    pipeline_step_weight.step,
    pipeline_step_weight.weight,
    pipeline_step_weight.seq
   FROM worker.pipeline_step_weight
UNION ALL
 SELECT NULL::text AS phase,
    NULL::text AS step,
    NULL::integer AS weight,
    NULL::integer AS seq
  WHERE false;
Options: security_invoker=on

```
