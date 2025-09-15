```sql
                             View "public.location__for_portion_of_valid"
      Column      |           Type           | Collation | Nullable | Default | Storage  | Description 
------------------+--------------------------+-----------+----------+---------+----------+-------------
 id               | integer                  |           |          |         | plain    | 
 valid_from       | date                     |           |          |         | plain    | 
 valid_to         | date                     |           |          |         | plain    | 
 valid_until      | date                     |           |          |         | plain    | 
 type             | location_type            |           |          |         | plain    | 
 address_part1    | character varying(200)   |           |          |         | extended | 
 address_part2    | character varying(200)   |           |          |         | extended | 
 address_part3    | character varying(200)   |           |          |         | extended | 
 postcode         | character varying(200)   |           |          |         | extended | 
 postplace        | character varying(200)   |           |          |         | extended | 
 region_id        | integer                  |           |          |         | plain    | 
 country_id       | integer                  |           |          |         | plain    | 
 latitude         | numeric(9,6)             |           |          |         | main     | 
 longitude        | numeric(9,6)             |           |          |         | main     | 
 altitude         | numeric(6,1)             |           |          |         | main     | 
 establishment_id | integer                  |           |          |         | plain    | 
 legal_unit_id    | integer                  |           |          |         | plain    | 
 data_source_id   | integer                  |           |          |         | plain    | 
 edit_comment     | character varying(512)   |           |          |         | extended | 
 edit_by_user_id  | integer                  |           |          |         | plain    | 
 edit_at          | timestamp with time zone |           |          |         | plain    | 
View definition:
 SELECT id,
    valid_from,
    valid_to,
    valid_until,
    type,
    address_part1,
    address_part2,
    address_part3,
    postcode,
    postplace,
    region_id,
    country_id,
    latitude,
    longitude,
    altitude,
    establishment_id,
    legal_unit_id,
    data_source_id,
    edit_comment,
    edit_by_user_id,
    edit_at
   FROM location;
Triggers:
    for_portion_of_valid INSTEAD OF INSERT OR DELETE OR UPDATE ON location__for_portion_of_valid FOR EACH ROW EXECUTE FUNCTION sql_saga.for_portion_of_trigger('id')

```
