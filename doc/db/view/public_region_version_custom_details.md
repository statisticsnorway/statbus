```sql
                     View "public.region_version_custom"
   Column    | Type | Collation | Nullable | Default | Storage  | Description 
-------------+------+-----------+----------+---------+----------+-------------
 code        | text |           |          |         | extended | 
 name        | text |           |          |         | extended | 
 description | text |           |          |         | extended | 
View definition:
 SELECT code,
    name,
    description
   FROM region_version_enabled
  WHERE custom = true;
Triggers:
    prepare_region_version_custom BEFORE INSERT ON region_version_custom FOR EACH STATEMENT EXECUTE FUNCTION admin.prepare_region_version_custom()
    upsert_region_version_custom INSTEAD OF INSERT ON region_version_custom FOR EACH ROW EXECUTE FUNCTION admin.upsert_region_version_custom()
Options: security_invoker=on

```
