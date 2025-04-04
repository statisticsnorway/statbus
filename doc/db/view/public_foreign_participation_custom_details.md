```sql
               View "public.foreign_participation_custom"
 Column | Type | Collation | Nullable | Default | Storage  | Description 
--------+------+-----------+----------+---------+----------+-------------
 code   | text |           |          |         | extended | 
 name   | text |           |          |         | extended | 
View definition:
 SELECT code,
    name
   FROM foreign_participation_available
  WHERE custom = true;
Triggers:
    prepare_foreign_participation_custom BEFORE INSERT ON foreign_participation_custom FOR EACH STATEMENT EXECUTE FUNCTION admin.prepare_foreign_participation_custom()
    upsert_foreign_participation_custom INSTEAD OF INSERT ON foreign_participation_custom FOR EACH ROW EXECUTE FUNCTION admin.upsert_foreign_participation_custom()
Options: security_invoker=on

```
