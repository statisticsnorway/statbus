```sql
                           View "public.activity_category_nace_v2_1"
   Column    |          Type          | Collation | Nullable | Default | Storage  | Description 
-------------+------------------------+-----------+----------+---------+----------+-------------
 standard    | character varying(16)  |           |          |         | extended | 
 path        | ltree                  |           |          |         | extended | 
 label       | character varying      |           |          |         | extended | 
 code        | character varying      |           |          |         | extended | 
 name        | character varying(256) |           |          |         | extended | 
 description | text                   |           |          |         | extended | 
View definition:
 SELECT acs.code AS standard,
    ac.path,
    ac.label,
    ac.code,
    ac.name,
    ac.description
   FROM activity_category ac
     JOIN activity_category_standard acs ON ac.standard_id = acs.id
  WHERE acs.code::text = 'nace_v2.1'::text
  ORDER BY ac.path;
Triggers:
    delete_stale_activity_category_nace_v2_1 AFTER INSERT ON activity_category_nace_v2_1 FOR EACH STATEMENT EXECUTE FUNCTION admin.delete_stale_activity_category()
    upsert_activity_category_nace_v2_1 INSTEAD OF INSERT ON activity_category_nace_v2_1 FOR EACH ROW EXECUTE FUNCTION admin.upsert_activity_category('nace_v2.1')
Options: security_invoker=on

```
