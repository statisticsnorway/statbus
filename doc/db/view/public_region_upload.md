```sql
               View "public.region_upload"
      Column      | Type | Collation | Nullable | Default 
------------------+------+-----------+----------+---------
 path             | text |           |          | 
 name             | text |           |          | 
 center_latitude  | text |           |          | 
 center_longitude | text |           |          | 
 center_altitude  | text |           |          | 
Triggers:
    region_upload_upsert INSTEAD OF INSERT ON region_upload FOR EACH ROW EXECUTE FUNCTION admin.region_upload_upsert()

```
