```sql
                       View "public.reorg_type_system"
   Column    | Type | Collation | Nullable | Default | Storage  | Description 
-------------+------+-----------+----------+---------+----------+-------------
 code        | text |           |          |         | extended | 
 name        | text |           |          |         | extended | 
 description | text |           |          |         | extended | 
View definition:
 SELECT code,
    name,
    description
   FROM reorg_type_available
  WHERE custom = false;
Triggers:
    upsert_reorg_type_system INSTEAD OF INSERT ON reorg_type_system FOR EACH ROW EXECUTE FUNCTION admin.upsert_reorg_type_system()
Options: security_invoker=on

```
