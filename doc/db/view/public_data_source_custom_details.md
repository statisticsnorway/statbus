```sql
                    View "public.data_source_custom"
 Column | Type | Collation | Nullable | Default | Storage  | Description 
--------+------+-----------+----------+---------+----------+-------------
 code   | text |           |          |         | extended | 
 name   | text |           |          |         | extended | 
View definition:
 SELECT data_source_available.code,
    data_source_available.name
   FROM data_source_available
  WHERE data_source_available.custom = true;
Triggers:
    prepare_data_source_custom BEFORE INSERT ON data_source_custom FOR EACH STATEMENT EXECUTE FUNCTION admin.prepare_data_source_custom()
    upsert_data_source_custom INSTEAD OF INSERT ON data_source_custom FOR EACH ROW EXECUTE FUNCTION admin.upsert_data_source_custom()
Options: security_invoker=on

```
