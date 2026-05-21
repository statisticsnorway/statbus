```sql
                     View "public.region_version_system"
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
  WHERE custom = false;
Triggers:
    upsert_region_version_system INSTEAD OF INSERT ON region_version_system FOR EACH ROW EXECUTE FUNCTION admin.upsert_region_version_system()
Options: security_invoker=on

```
