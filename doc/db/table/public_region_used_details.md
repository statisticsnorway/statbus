```sql
                                      Materialized view "public.region_used"
 Column |       Type        | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
--------+-------------------+-----------+----------+---------+----------+-------------+--------------+-------------
 id     | integer           |           |          |         | plain    |             |              | 
 path   | ltree             |           |          |         | extended |             |              | 
 level  | integer           |           |          |         | plain    |             |              | 
 label  | character varying |           |          |         | extended |             |              | 
 code   | character varying |           |          |         | extended |             |              | 
 name   | text              |           |          |         | extended |             |              | 
Indexes:
    "region_used_key" UNIQUE, btree (path)
View definition:
 SELECT r.id,
    r.path,
    r.level,
    r.label,
    r.code,
    r.name
   FROM region r
  WHERE r.path @> (( SELECT array_agg(DISTINCT statistical_unit.physical_region_path) AS array_agg
           FROM statistical_unit
          WHERE statistical_unit.physical_region_path IS NOT NULL))
  ORDER BY (nlevel(r.path)), r.path;
Access method: heap

```
