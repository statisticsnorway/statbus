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
 SELECT id,
    path,
    level,
    label,
    code,
    name
   FROM region r
  WHERE path @> (( SELECT array_agg(DISTINCT statistical_unit.physical_region_path) AS array_agg
           FROM statistical_unit
          WHERE statistical_unit.physical_region_path IS NOT NULL))
  ORDER BY (nlevel(path)), path;

```
