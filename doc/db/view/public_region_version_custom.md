```sql
         View "public.region_version_custom"
   Column    | Type | Collation | Nullable | Default 
-------------+------+-----------+----------+---------
 code        | text |           |          | 
 name        | text |           |          | 
 description | text |           |          | 
Triggers:
    prepare_region_version_custom BEFORE INSERT ON region_version_custom FOR EACH STATEMENT EXECUTE FUNCTION admin.prepare_region_version_custom()
    upsert_region_version_custom INSTEAD OF INSERT ON region_version_custom FOR EACH ROW EXECUTE FUNCTION admin.upsert_region_version_custom()

```
