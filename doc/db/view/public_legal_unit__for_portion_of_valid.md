```sql
                    View "public.legal_unit__for_portion_of_valid"
          Column          |           Type           | Collation | Nullable | Default 
--------------------------+--------------------------+-----------+----------+---------
 id                       | integer                  |           |          | 
 valid_from               | date                     |           |          | 
 valid_to                 | date                     |           |          | 
 valid_until              | date                     |           |          | 
 short_name               | character varying(16)    |           |          | 
 name                     | character varying(256)   |           |          | 
 birth_date               | date                     |           |          | 
 death_date               | date                     |           |          | 
 free_econ_zone           | boolean                  |           |          | 
 sector_id                | integer                  |           |          | 
 status_id                | integer                  |           |          | 
 legal_form_id            | integer                  |           |          | 
 edit_comment             | character varying(512)   |           |          | 
 edit_by_user_id          | integer                  |           |          | 
 edit_at                  | timestamp with time zone |           |          | 
 unit_size_id             | integer                  |           |          | 
 foreign_participation_id | integer                  |           |          | 
 data_source_id           | integer                  |           |          | 
 enterprise_id            | integer                  |           |          | 
 primary_for_enterprise   | boolean                  |           |          | 
 invalid_codes            | jsonb                    |           |          | 
Triggers:
    for_portion_of_valid INSTEAD OF INSERT OR DELETE OR UPDATE ON legal_unit__for_portion_of_valid FOR EACH ROW EXECUTE FUNCTION sql_saga.for_portion_of_trigger('id')

```
