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
 SELECT path::text AS path,
    name,
    center_latitude::text AS center_latitude,
    center_longitude::text AS center_longitude,
    center_altitude::text AS center_altitude
   FROM region
  ORDER BY (path::text);
Triggers:
    region_upload_upsert INSTEAD OF INSERT ON region_upload FOR EACH ROW EXECUTE FUNCTION admin.region_upload_upsert()
Options: security_invoker=on

```

**Comment:** Upload of regions by path, with name, and optionally center_latitude, center_longitude and center_altitude. Each row adds or changes one region; columns a row leaves out or empty keep what is stored, so a file of path and centre columns adds centres to the regions already listed (admin.region_upload_upsert).
