```sql
                        View "public.region_upload"
  Column   | Type | Collation | Nullable | Default | Storage  | Description 
-----------+------+-----------+----------+---------+----------+-------------
 path      | text |           |          |         | extended | 
 name      | text |           |          |         | extended | 
 latitude  | text |           |          |         | extended | 
 longitude | text |           |          |         | extended | 
 altitude  | text |           |          |         | extended | 
View definition:
 SELECT path::text AS path,
    name,
    latitude::text AS latitude,
    longitude::text AS longitude,
    altitude::text AS altitude
   FROM region
  ORDER BY (path::text);
Triggers:
    region_upload_upsert INSTEAD OF INSERT ON region_upload FOR EACH ROW EXECUTE FUNCTION admin.region_upload_upsert()
Options: security_invoker=on

```

**Comment:** Upload of regions by path, with name, and optionally latitude, longitude and altitude. Each row adds or changes one region; columns a row leaves out or empty keep what is stored, so a file of path and coordinate columns adds points to the regions already listed (admin.region_upload_upsert).
