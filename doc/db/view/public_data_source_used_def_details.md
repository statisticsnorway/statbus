```sql
                     View "public.data_source_used_def"
 Column |  Type   | Collation | Nullable | Default | Storage  | Description 
--------+---------+-----------+----------+---------+----------+-------------
 id     | integer |           |          |         | plain    | 
 code   | text    |           |          |         | extended | 
 name   | text    |           |          |         | extended | 
View definition:
 SELECT s.id,
    s.code,
    s.name
   FROM data_source s
  WHERE (s.id IN ( SELECT unnest(array_distinct_concat(statistical_unit.data_source_ids)) AS unnest
           FROM statistical_unit
          WHERE statistical_unit.data_source_ids IS NOT NULL)) AND s.active
  ORDER BY s.code;

```
