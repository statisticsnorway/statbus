```sql
                            View "public.region_upload"
      Column      | Type | Collation | Nullable | Default | Storage  | Description 
------------------+------+-----------+----------+---------+----------+-------------
 path             | text |           |          |         | extended | 
 name             | text |           |          |         | extended | 
 center_latitude  | text |           |          |         | extended | 
 center_longitude | text |           |          |         | extended | 
 center_altitude  | text |           |          |         | extended | 
View definition:
 SELECT region.path::text AS path,
    region.name,
    region.center_latitude::text AS center_latitude,
    region.center_longitude::text AS center_longitude,
    region.center_altitude::text AS center_altitude
   FROM region
  ORDER BY (region.path::text);
Triggers:
    region_upload_upsert INSTEAD OF INSERT ON region_upload FOR EACH ROW EXECUTE FUNCTION admin.region_upload_upsert()
Options: security_invoker=on

```
