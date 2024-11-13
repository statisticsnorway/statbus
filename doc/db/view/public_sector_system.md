```sql
             View "public.sector_system"
   Column    | Type  | Collation | Nullable | Default 
-------------+-------+-----------+----------+---------
 path        | ltree |           |          | 
 name        | text  |           |          | 
 description | text  |           |          | 
Triggers:
    upsert_sector_system INSTEAD OF INSERT ON sector_system FOR EACH ROW EXECUTE FUNCTION admin.upsert_sector_system()

```
