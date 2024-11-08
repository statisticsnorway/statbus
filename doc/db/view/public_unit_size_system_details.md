```sql
                     View "public.unit_size_system"
 Column | Type | Collation | Nullable | Default | Storage  | Description 
--------+------+-----------+----------+---------+----------+-------------
 code   | text |           |          |         | extended | 
 name   | text |           |          |         | extended | 
View definition:
 SELECT unit_size_available.code,
    unit_size_available.name
   FROM unit_size_available
  WHERE unit_size_available.custom = false;
Triggers:
    upsert_unit_size_system INSTEAD OF INSERT ON unit_size_system FOR EACH ROW EXECUTE FUNCTION admin.upsert_unit_size_system()
Options: security_invoker=on

```
