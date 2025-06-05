```sql
                    View "public.data_source_system"
 Column | Type | Collation | Nullable | Default | Storage  | Description 
--------+------+-----------+----------+---------+----------+-------------
 code   | text |           |          |         | extended | 
 name   | text |           |          |         | extended | 
View definition:
 SELECT code,
    name
   FROM data_source_available
  WHERE custom = false;
Triggers:
    upsert_data_source_system INSTEAD OF INSERT ON data_source_system FOR EACH ROW EXECUTE FUNCTION admin.upsert_data_source_system()
Options: security_invoker=on

```
