```sql
         View "public.unit_size_system"
 Column | Type | Collation | Nullable | Default 
--------+------+-----------+----------+---------
 code   | text |           |          | 
 name   | text |           |          | 
Triggers:
    upsert_unit_size_system INSTEAD OF INSERT ON unit_size_system FOR EACH ROW EXECUTE FUNCTION admin.upsert_unit_size_system()

```
