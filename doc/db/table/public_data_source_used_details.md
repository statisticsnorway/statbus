```sql
                               Materialized view "public.data_source_used"
 Column |  Type   | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
--------+---------+-----------+----------+---------+----------+-------------+--------------+-------------
 id     | integer |           |          |         | plain    |             |              | 
 code   | text    |           |          |         | extended |             |              | 
 name   | text    |           |          |         | extended |             |              | 
Indexes:
    "data_source_used_key" UNIQUE, btree (code)
View definition:
 SELECT s.id,
    s.code,
    s.name
   FROM data_source s
  WHERE (s.id IN ( SELECT unnest(array_distinct_concat(statistical_unit.data_source_ids)) AS unnest
           FROM statistical_unit
          WHERE statistical_unit.data_source_ids IS NOT NULL)) AND s.active
  ORDER BY s.code;
Access method: heap

```
