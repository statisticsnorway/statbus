```sql
                          View "public.sector_custom"
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
  WHERE sector_available.custom = true;
Triggers:
    prepare_sector_custom BEFORE INSERT ON sector_custom FOR EACH STATEMENT EXECUTE FUNCTION admin.prepare_sector_custom()
    upsert_sector_custom INSTEAD OF INSERT ON sector_custom FOR EACH ROW EXECUTE FUNCTION admin.upsert_sector_custom()
Options: security_invoker=on

```
