```sql
        View "public.data_source_system"
 Column | Type | Collation | Nullable | Default 
--------+------+-----------+----------+---------
 code   | text |           |          | 
 name   | text |           |          | 
Triggers:
    upsert_data_source_system INSTEAD OF INSERT ON data_source_system FOR EACH ROW EXECUTE FUNCTION admin.upsert_data_source_system()

```
