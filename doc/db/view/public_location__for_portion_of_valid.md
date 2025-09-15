```sql
                 View "public.location__for_portion_of_valid"
      Column      |           Type           | Collation | Nullable | Default 
------------------+--------------------------+-----------+----------+---------
 id               | integer                  |           |          | 
 valid_from       | date                     |           |          | 
 valid_to         | date                     |           |          | 
 valid_until      | date                     |           |          | 
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
    for_portion_of_valid INSTEAD OF INSERT OR DELETE OR UPDATE ON location__for_portion_of_valid FOR EACH ROW EXECUTE FUNCTION sql_saga.for_portion_of_trigger('id')

```
