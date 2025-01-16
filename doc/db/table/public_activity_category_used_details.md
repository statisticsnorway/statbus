```sql
                                       Materialized view "public.activity_category_used"
    Column     |          Type          | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
---------------+------------------------+-----------+----------+---------+----------+-------------+--------------+-------------
 standard_code | character varying(16)  |           |          |         | extended |             |              | 
 id            | integer                |           |          |         | plain    |             |              | 
 path          | ltree                  |           |          |         | extended |             |              | 
 parent_path   | ltree                  |           |          |         | extended |             |              | 
 code          | character varying      |           |          |         | extended |             |              | 
 label         | character varying      |           |          |         | extended |             |              | 
 name          | character varying(256) |           |          |         | extended |             |              | 
 description   | text                   |           |          |         | extended |             |              | 
Indexes:
    "activity_category_used_key" UNIQUE, btree (path)
View definition:
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
           FROM settings)) AND ac.active AND ac.path @> (( SELECT array_agg(DISTINCT statistical_unit.primary_activity_category_path) AS array_agg
           FROM statistical_unit
          WHERE statistical_unit.primary_activity_category_path IS NOT NULL))
  ORDER BY ac.path;
Access method: heap

```
