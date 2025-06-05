```sql
               View "public.foreign_participation_system"
 Column | Type | Collation | Nullable | Default | Storage  | Description 
--------+------+-----------+----------+---------+----------+-------------
 code   | text |           |          |         | extended | 
 name   | text |           |          |         | extended | 
View definition:
 SELECT code,
    name
   FROM foreign_participation_available
  WHERE custom = false;
Triggers:
    upsert_foreign_participation_system INSTEAD OF INSERT ON foreign_participation_system FOR EACH ROW EXECUTE FUNCTION admin.upsert_foreign_participation_system()
Options: security_invoker=on

```
