```sql
                     View "public.unit_size_custom"
 Column | Type | Collation | Nullable | Default | Storage  | Description 
--------+------+-----------+----------+---------+----------+-------------
 code   | text |           |          |         | extended | 
 name   | text |           |          |         | extended | 
View definition:
 SELECT code,
    name
   FROM unit_size_available
  WHERE custom = true;
Triggers:
    prepare_unit_size_custom BEFORE INSERT ON unit_size_custom FOR EACH STATEMENT EXECUTE FUNCTION admin.prepare_unit_size_custom()
    upsert_unit_size_custom INSTEAD OF INSERT ON unit_size_custom FOR EACH ROW EXECUTE FUNCTION admin.upsert_unit_size_custom()
Options: security_invoker=on

```
