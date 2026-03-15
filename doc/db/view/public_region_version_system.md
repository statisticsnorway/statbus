```sql
         View "public.region_version_system"
   Column    | Type | Collation | Nullable | Default 
-------------+------+-----------+----------+---------
 code        | text |           |          | 
 name        | text |           |          | 
 description | text |           |          | 
Triggers:
    upsert_region_version_system INSTEAD OF INSERT ON region_version_system FOR EACH ROW EXECUTE FUNCTION admin.upsert_region_version_system()

```
