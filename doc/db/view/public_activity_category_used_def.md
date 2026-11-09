```sql
                             View "public.activity_category_used_def"
    Column     |          Type          | Collation | Nullable | Default | Storage  | Description 
---------------+------------------------+-----------+----------+---------+----------+-------------
 standard_code | character varying(16)  |           |          |         | extended | 
 id            | integer                |           |          |         | plain    | 
 path          | ltree                  |           |          |         | extended | 
 parent_path   | ltree                  |           |          |         | extended | 
 code          | character varying      |           |          |         | extended | 
 label         | character varying      |           |          |         | extended | 
 name          | character varying(512) |           |          |         | extended | 
 description   | text                   |           |          |         | extended | 
View definition:
 WITH RECURSIVE primary_path(path) AS (
        ( SELECT statistical_unit.primary_activity_category_path
           FROM statistical_unit
          WHERE statistical_unit.primary_activity_category_path IS NOT NULL
          ORDER BY statistical_unit.primary_activity_category_path
         LIMIT 1)
        UNION ALL
         SELECT ( SELECT statistical_unit.primary_activity_category_path
                   FROM statistical_unit
                  WHERE statistical_unit.primary_activity_category_path > primary_path.path
                  ORDER BY statistical_unit.primary_activity_category_path
                 LIMIT 1) AS path
           FROM primary_path
          WHERE primary_path.path IS NOT NULL
        ), secondary_path(path) AS (
        ( SELECT statistical_unit.secondary_activity_category_path
           FROM statistical_unit
          WHERE statistical_unit.secondary_activity_category_path IS NOT NULL
          ORDER BY statistical_unit.secondary_activity_category_path
         LIMIT 1)
        UNION ALL
         SELECT ( SELECT statistical_unit.secondary_activity_category_path
                   FROM statistical_unit
                  WHERE statistical_unit.secondary_activity_category_path > secondary_path.path
                  ORDER BY statistical_unit.secondary_activity_category_path
                 LIMIT 1) AS path
           FROM secondary_path
          WHERE secondary_path.path IS NOT NULL
        )
 SELECT acs.code AS standard_code,
    ac.id,
    ac.path,
    acp.path AS parent_path,
    ac.code,
    ac.label,
    ac.name,
    ac.description
   FROM activity_category ac
     JOIN activity_category_standard acs ON ac.standard_id = acs.id
     LEFT JOIN activity_category acp ON ac.parent_id = acp.id
  WHERE acs.id = (( SELECT settings.activity_category_standard_id
           FROM settings)) AND ac.enabled AND (ac.path @> (( SELECT array_agg(primary_path.path) AS array_agg
           FROM primary_path
          WHERE primary_path.path IS NOT NULL)) OR ac.path @> (( SELECT array_agg(secondary_path.path) AS array_agg
           FROM secondary_path
          WHERE secondary_path.path IS NOT NULL)))
  ORDER BY ac.path;
Options: security_invoker=on

```
