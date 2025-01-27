```sql
                             View "public.legal_unit_era"
          Column          |           Type           | Collation | Nullable | Default 
--------------------------+--------------------------+-----------+----------+---------
 id                       | integer                  |           |          | 
 valid_after              | date                     |           |          | 
 valid_from               | date                     |           |          | 
 valid_to                 | date                     |           |          | 
 active                   | boolean                  |           |          | 
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
    legal_unit_era_upsert INSTEAD OF INSERT ON legal_unit_era FOR EACH ROW EXECUTE FUNCTION admin.legal_unit_era_upsert()

```
