```sql
                  View "public.status_custom"
  Column  |       Type        | Collation | Nullable | Default 
----------+-------------------+-----------+----------+---------
 code     | character varying |           |          | 
 name     | text              |           |          | 
 priority | integer           |           |          | 
Triggers:
    prepare_status_custom BEFORE INSERT ON status_custom FOR EACH STATEMENT EXECUTE FUNCTION admin.prepare_status_custom()
    upsert_status_custom INSTEAD OF INSERT ON status_custom FOR EACH ROW EXECUTE FUNCTION admin.upsert_status_custom()

```
