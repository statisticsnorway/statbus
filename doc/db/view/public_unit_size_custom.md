```sql
         View "public.unit_size_custom"
 Column | Type | Collation | Nullable | Default 
--------+------+-----------+----------+---------
 code   | text |           |          | 
 name   | text |           |          | 
Triggers:
    prepare_unit_size_custom BEFORE INSERT ON unit_size_custom FOR EACH STATEMENT EXECUTE FUNCTION admin.prepare_unit_size_custom()
    upsert_unit_size_custom INSTEAD OF INSERT ON unit_size_custom FOR EACH ROW EXECUTE FUNCTION admin.upsert_unit_size_custom()

```
