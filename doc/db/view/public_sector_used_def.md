```sql
                            View "public.sector_used_def"
 Column |       Type        | Collation | Nullable | Default | Storage  | Description 
--------+-------------------+-----------+----------+---------+----------+-------------
 id     | integer           |           |          |         | plain    | 
 path   | ltree             |           |          |         | extended | 
 label  | character varying |           |          |         | extended | 
 code   | character varying |           |          |         | extended | 
 name   | text              |           |          |         | extended | 
View definition:
 WITH RECURSIVE used_path(path) AS (
        ( SELECT statistical_unit.sector_path
           FROM statistical_unit
          WHERE statistical_unit.sector_path IS NOT NULL
          ORDER BY statistical_unit.sector_path
         LIMIT 1)
        UNION ALL
         SELECT ( SELECT statistical_unit.sector_path
                   FROM statistical_unit
                  WHERE statistical_unit.sector_path > used_path.path
                  ORDER BY statistical_unit.sector_path
                 LIMIT 1) AS path
           FROM used_path
          WHERE used_path.path IS NOT NULL
        )
 SELECT id,
    path,
    label,
    code,
    name
   FROM sector s
  WHERE path @> (( SELECT array_agg(used_path.path) AS array_agg
           FROM used_path
          WHERE used_path.path IS NOT NULL)) AND enabled
  ORDER BY path;
Options: security_invoker=on

```
