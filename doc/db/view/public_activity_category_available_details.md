```sql
                            View "public.activity_category_available"
    Column     |          Type          | Collation | Nullable | Default | Storage  | Description 
---------------+------------------------+-----------+----------+---------+----------+-------------
 standard_code | character varying(16)  |           |          |         | extended | 
 id            | integer                |           |          |         | plain    | 
 path          | ltree                  |           |          |         | extended | 
 parent_path   | ltree                  |           |          |         | extended | 
 code          | character varying      |           |          |         | extended | 
 label         | character varying      |           |          |         | extended | 
 name          | character varying(256) |           |          |         | extended | 
 description   | text                   |           |          |         | extended | 
 custom        | boolean                |           |          |         | plain    | 
View definition:
 SELECT acs.code AS standard_code,
    ac.id,
    ac.path,
    acp.path AS parent_path,
    ac.code,
    ac.label,
    ac.name,
    ac.description,
    ac.custom
   FROM activity_category ac
     JOIN activity_category_standard acs ON ac.standard_id = acs.id
     LEFT JOIN activity_category acp ON ac.parent_id = acp.id
  WHERE acs.id = (( SELECT settings.activity_category_standard_id
           FROM settings)) AND ac.enabled
  ORDER BY ac.path;
Triggers:
    activity_category_available_upsert_custom INSTEAD OF INSERT ON activity_category_available FOR EACH ROW EXECUTE FUNCTION admin.activity_category_available_upsert_custom()
Options: security_invoker=on

```
