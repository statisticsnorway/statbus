```sql
                        View "public.activity_category_available_custom"
   Column    |          Type          | Collation | Nullable | Default | Storage  | Description 
-------------+------------------------+-----------+----------+---------+----------+-------------
 path        | ltree                  |           |          |         | extended | 
 name        | character varying(256) |           |          |         | extended | 
 description | text                   |           |          |         | extended | 
View definition:
 SELECT ac.path,
    ac.name,
    ac.description
   FROM activity_category ac
  WHERE ac.standard_id = (( SELECT settings.activity_category_standard_id
           FROM settings)) AND ac.active AND ac.custom
  ORDER BY ac.path;
Triggers:
    activity_category_available_custom_upsert_custom INSTEAD OF INSERT ON activity_category_available_custom FOR EACH ROW EXECUTE FUNCTION admin.activity_category_available_custom_upsert_custom()
Options: security_invoker=on

```
