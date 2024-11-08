```sql
             View "public.sector_custom"
   Column    | Type  | Collation | Nullable | Default 
-------------+-------+-----------+----------+---------
 path        | ltree |           |          | 
 name        | text  |           |          | 
 description | text  |           |          | 
Triggers:
    prepare_sector_custom BEFORE INSERT ON sector_custom FOR EACH STATEMENT EXECUTE FUNCTION admin.prepare_sector_custom()
    upsert_sector_custom INSTEAD OF INSERT ON sector_custom FOR EACH ROW EXECUTE FUNCTION admin.upsert_sector_custom()

```
