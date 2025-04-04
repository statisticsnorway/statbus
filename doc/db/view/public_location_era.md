```sql
                          View "public.location_era"
      Column      |           Type           | Collation | Nullable | Default 
------------------+--------------------------+-----------+----------+---------
 id               | integer                  |           |          | 
 valid_after      | date                     |           |          | 
 valid_from       | date                     |           |          | 
 valid_to         | date                     |           |          | 
 type             | location_type            |           |          | 
 address_part1    | character varying(200)   |           |          | 
 address_part2    | character varying(200)   |           |          | 
 address_part3    | character varying(200)   |           |          | 
 postcode         | character varying(200)   |           |          | 
 postplace        | character varying(200)   |           |          | 
 region_id        | integer                  |           |          | 
 country_id       | integer                  |           |          | 
 latitude         | numeric(9,6)             |           |          | 
 longitude        | numeric(9,6)             |           |          | 
 altitude         | numeric(6,1)             |           |          | 
 establishment_id | integer                  |           |          | 
 legal_unit_id    | integer                  |           |          | 
 data_source_id   | integer                  |           |          | 
 edit_comment     | character varying(512)   |           |          | 
 edit_by_user_id  | integer                  |           |          | 
 edit_at          | timestamp with time zone |           |          | 
Triggers:
    location_era_upsert INSTEAD OF INSERT ON location_era FOR EACH ROW EXECUTE FUNCTION admin.location_era_upsert()

```
