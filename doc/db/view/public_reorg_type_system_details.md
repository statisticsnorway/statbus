```sql
                       View "public.reorg_type_system"
   Column    | Type | Collation | Nullable | Default | Storage  | Description 
-------------+------+-----------+----------+---------+----------+-------------
 code        | text |           |          |         | extended | 
 name        | text |           |          |         | extended | 
 description | text |           |          |         | extended | 
View definition:
 SELECT reorg_type_available.code,
    reorg_type_available.name,
    reorg_type_available.description
   FROM reorg_type_available
  WHERE reorg_type_available.custom = false;
Triggers:
    upsert_reorg_type_system INSTEAD OF INSERT ON reorg_type_system FOR EACH ROW EXECUTE FUNCTION admin.upsert_reorg_type_system()
Options: security_invoker=on

```
