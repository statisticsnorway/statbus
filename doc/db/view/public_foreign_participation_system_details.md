```sql
               View "public.foreign_participation_system"
 Column | Type | Collation | Nullable | Default | Storage  | Description 
--------+------+-----------+----------+---------+----------+-------------
 code   | text |           |          |         | extended | 
 name   | text |           |          |         | extended | 
View definition:
 SELECT foreign_participation_available.code,
    foreign_participation_available.name
   FROM foreign_participation_available
  WHERE foreign_participation_available.custom = false;
Triggers:
    upsert_foreign_participation_system INSTEAD OF INSERT ON foreign_participation_system FOR EACH ROW EXECUTE FUNCTION admin.upsert_foreign_participation_system()
Options: security_invoker=on

```
