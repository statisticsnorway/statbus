```sql
                                      Materialized view "public.sector_used"
 Column |       Type        | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
--------+-------------------+-----------+----------+---------+----------+-------------+--------------+-------------
 id     | integer           |           |          |         | plain    |             |              | 
 path   | ltree             |           |          |         | extended |             |              | 
 label  | character varying |           |          |         | extended |             |              | 
 code   | character varying |           |          |         | extended |             |              | 
 name   | text              |           |          |         | extended |             |              | 
Indexes:
    "sector_used_key" UNIQUE, btree (path)
View definition:
 SELECT s.id,
    s.path,
    s.label,
    s.code,
    s.name
   FROM sector s
  WHERE s.path @> (( SELECT array_agg(DISTINCT statistical_unit.sector_path) AS array_agg
           FROM statistical_unit
          WHERE statistical_unit.sector_path IS NOT NULL)) AND s.active
  ORDER BY s.path;
Access method: heap

```
