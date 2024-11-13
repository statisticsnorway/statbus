```sql
                       View "public.reorg_type_custom"
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
  WHERE reorg_type_available.custom = true;
Triggers:
    prepare_reorg_type_custom BEFORE INSERT ON reorg_type_custom FOR EACH STATEMENT EXECUTE FUNCTION admin.prepare_reorg_type_custom()
    upsert_reorg_type_custom INSTEAD OF INSERT ON reorg_type_custom FOR EACH ROW EXECUTE FUNCTION admin.upsert_reorg_type_custom()
Options: security_invoker=on

```
