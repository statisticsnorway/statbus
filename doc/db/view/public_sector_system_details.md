```sql
                          View "public.sector_system"
   Column    | Type  | Collation | Nullable | Default | Storage  | Description 
-------------+-------+-----------+----------+---------+----------+-------------
 path        | ltree |           |          |         | extended | 
 name        | text  |           |          |         | extended | 
 description | text  |           |          |         | extended | 
View definition:
 SELECT sector_available.path,
    sector_available.name,
    sector_available.description
   FROM sector_available
  WHERE sector_available.custom = false;
Triggers:
    upsert_sector_system INSTEAD OF INSERT ON sector_system FOR EACH ROW EXECUTE FUNCTION admin.upsert_sector_system()
Options: security_invoker=on

```
