```sql
                            View "public.region_used_def"
 Column |       Type        | Collation | Nullable | Default | Storage  | Description 
--------+-------------------+-----------+----------+---------+----------+-------------
 id     | integer           |           |          |         | plain    | 
 path   | ltree             |           |          |         | extended | 
 level  | integer           |           |          |         | plain    | 
 label  | character varying |           |          |         | extended | 
 code   | character varying |           |          |         | extended | 
 name   | text              |           |          |         | extended | 
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

```
