```sql
           View "public.sector_custom_only"
   Column    | Type  | Collation | Nullable | Default 
-------------+-------+-----------+----------+---------
 path        | ltree |           |          | 
 name        | text  |           |          | 
 description | text  |           |          | 
Triggers:
    sector_custom_only_prepare_trigger BEFORE INSERT ON sector_custom_only FOR EACH STATEMENT EXECUTE FUNCTION admin.sector_custom_only_prepare()
    sector_custom_only_upsert INSTEAD OF INSERT ON sector_custom_only FOR EACH ROW EXECUTE FUNCTION admin.sector_custom_only_upsert()

```
