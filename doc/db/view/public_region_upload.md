```sql
                   View "public.region_upload"
      Column      |     Type     | Collation | Nullable | Default 
------------------+--------------+-----------+----------+---------
 path             | ltree        |           |          | 
 name             | text         |           |          | 
 center_latitude  | numeric(9,6) |           |          | 
 center_longitude | numeric(9,6) |           |          | 
 center_altitude  | numeric(6,1) |           |          | 
Triggers:
    region_upload_upsert INSTEAD OF INSERT ON region_upload FOR EACH ROW EXECUTE FUNCTION admin.region_upload_upsert()

```
