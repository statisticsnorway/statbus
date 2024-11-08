```sql
                                View "public.region_upload"
      Column      |     Type     | Collation | Nullable | Default | Storage  | Description 
------------------+--------------+-----------+----------+---------+----------+-------------
 path             | ltree        |           |          |         | extended | 
 name             | text         |           |          |         | extended | 
 center_latitude  | numeric(9,6) |           |          |         | main     | 
 center_longitude | numeric(9,6) |           |          |         | main     | 
 center_altitude  | numeric(6,1) |           |          |         | main     | 
View definition:
 SELECT region.path,
    region.name,
    region.center_latitude,
    region.center_longitude,
    region.center_altitude
   FROM region
  ORDER BY region.path;
Triggers:
    region_upload_upsert INSTEAD OF INSERT ON region_upload FOR EACH ROW EXECUTE FUNCTION admin.region_upload_upsert()
Options: security_invoker=on

```
