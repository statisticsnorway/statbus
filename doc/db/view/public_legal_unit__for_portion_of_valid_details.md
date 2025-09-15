```sql
                                View "public.legal_unit__for_portion_of_valid"
          Column          |           Type           | Collation | Nullable | Default | Storage  | Description 
--------------------------+--------------------------+-----------+----------+---------+----------+-------------
 id                       | integer                  |           |          |         | plain    | 
 valid_from               | date                     |           |          |         | plain    | 
 valid_to                 | date                     |           |          |         | plain    | 
 valid_until              | date                     |           |          |         | plain    | 
 short_name               | character varying(16)    |           |          |         | extended | 
 name                     | character varying(256)   |           |          |         | extended | 
 birth_date               | date                     |           |          |         | plain    | 
 death_date               | date                     |           |          |         | plain    | 
 free_econ_zone           | boolean                  |           |          |         | plain    | 
 sector_id                | integer                  |           |          |         | plain    | 
 status_id                | integer                  |           |          |         | plain    | 
 legal_form_id            | integer                  |           |          |         | plain    | 
 edit_comment             | character varying(512)   |           |          |         | extended | 
 edit_by_user_id          | integer                  |           |          |         | plain    | 
 edit_at                  | timestamp with time zone |           |          |         | plain    | 
 unit_size_id             | integer                  |           |          |         | plain    | 
 foreign_participation_id | integer                  |           |          |         | plain    | 
 data_source_id           | integer                  |           |          |         | plain    | 
 enterprise_id            | integer                  |           |          |         | plain    | 
 primary_for_enterprise   | boolean                  |           |          |         | plain    | 
 invalid_codes            | jsonb                    |           |          |         | extended | 
View definition:
 SELECT id,
    valid_from,
    valid_to,
    valid_until,
    short_name,
    name,
    birth_date,
    death_date,
    free_econ_zone,
    sector_id,
    status_id,
    legal_form_id,
    edit_comment,
    edit_by_user_id,
    edit_at,
    unit_size_id,
    foreign_participation_id,
    data_source_id,
    enterprise_id,
    primary_for_enterprise,
    invalid_codes
   FROM legal_unit;
Triggers:
    for_portion_of_valid INSTEAD OF INSERT OR DELETE OR UPDATE ON legal_unit__for_portion_of_valid FOR EACH ROW EXECUTE FUNCTION sql_saga.for_portion_of_trigger('id')

```
