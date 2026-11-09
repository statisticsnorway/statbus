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
 WITH RECURSIVE used_path(path) AS (
        ( SELECT statistical_unit.physical_region_path
           FROM statistical_unit
          WHERE statistical_unit.physical_region_path IS NOT NULL
          ORDER BY statistical_unit.physical_region_path
         LIMIT 1)
        UNION ALL
         SELECT ( SELECT statistical_unit.physical_region_path
                   FROM statistical_unit
                  WHERE statistical_unit.physical_region_path > used_path.path
                  ORDER BY statistical_unit.physical_region_path
                 LIMIT 1) AS path
           FROM used_path
          WHERE used_path.path IS NOT NULL
        )
 SELECT id,
    path,
    level,
    label,
    code,
    name
   FROM region r
  WHERE path @> (( SELECT array_agg(used_path.path) AS array_agg
           FROM used_path
          WHERE used_path.path IS NOT NULL))
  ORDER BY (nlevel(path)), path;
Options: security_invoker=on

```
