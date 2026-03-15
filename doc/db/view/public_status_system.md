```sql
                  View "public.status_system"
  Column  |       Type        | Collation | Nullable | Default 
----------+-------------------+-----------+----------+---------
 code     | character varying |           |          | 
 name     | text              |           |          | 
 priority | integer           |           |          | 
Triggers:
    upsert_status_system INSTEAD OF INSERT ON status_system FOR EACH ROW EXECUTE FUNCTION admin.upsert_status_system()

```
