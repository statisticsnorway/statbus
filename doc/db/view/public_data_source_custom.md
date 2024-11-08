```sql
        View "public.data_source_custom"
 Column | Type | Collation | Nullable | Default 
--------+------+-----------+----------+---------
 code   | text |           |          | 
 name   | text |           |          | 
Triggers:
    prepare_data_source_custom BEFORE INSERT ON data_source_custom FOR EACH STATEMENT EXECUTE FUNCTION admin.prepare_data_source_custom()
    upsert_data_source_custom INSTEAD OF INSERT ON data_source_custom FOR EACH ROW EXECUTE FUNCTION admin.upsert_data_source_custom()

```
