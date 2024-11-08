```sql
                                      View "public.location_era"
       Column       |          Type          | Collation | Nullable | Default | Storage  | Description 
--------------------+------------------------+-----------+----------+---------+----------+-------------
 id                 | integer                |           |          |         | plain    | 
 valid_after        | date                   |           |          |         | plain    | 
 valid_from         | date                   |           |          |         | plain    | 
 valid_to           | date                   |           |          |         | plain    | 
 type               | location_type          |           |          |         | plain    | 
 address_part1      | character varying(200) |           |          |         | extended | 
 address_part2      | character varying(200) |           |          |         | extended | 
 address_part3      | character varying(200) |           |          |         | extended | 
 postal_code        | character varying(200) |           |          |         | extended | 
 postal_place       | character varying(200) |           |          |         | extended | 
 region_id          | integer                |           |          |         | plain    | 
 country_id         | integer                |           |          |         | plain    | 
 latitude           | numeric(9,6)           |           |          |         | main     | 
 longitude          | numeric(9,6)           |           |          |         | main     | 
 altitude           | numeric(6,1)           |           |          |         | main     | 
 establishment_id   | integer                |           |          |         | plain    | 
 legal_unit_id      | integer                |           |          |         | plain    | 
 data_source_id     | integer                |           |          |         | plain    | 
 updated_by_user_id | integer                |           |          |         | plain    | 
View definition:
 SELECT location.id,
    location.valid_after,
    location.valid_from,
    location.valid_to,
    location.type,
    location.address_part1,
    location.address_part2,
    location.address_part3,
    location.postal_code,
    location.postal_place,
    location.region_id,
    location.country_id,
    location.latitude,
    location.longitude,
    location.altitude,
    location.establishment_id,
    location.legal_unit_id,
    location.data_source_id,
    location.updated_by_user_id
   FROM location;
Triggers:
    location_era_upsert INSTEAD OF INSERT ON location_era FOR EACH ROW EXECUTE FUNCTION admin.location_era_upsert()
Options: security_invoker=on

```
