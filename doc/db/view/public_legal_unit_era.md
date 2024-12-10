```sql
                            View "public.legal_unit_era"
          Column          |          Type          | Collation | Nullable | Default 
--------------------------+------------------------+-----------+----------+---------
 id                       | integer                |           |          | 
 valid_after              | date                   |           |          | 
 valid_from               | date                   |           |          | 
 valid_to                 | date                   |           |          | 
 active                   | boolean                |           |          | 
 short_name               | character varying(16)  |           |          | 
 name                     | character varying(256) |           |          | 
 birth_date               | date                   |           |          | 
 death_date               | date                   |           |          | 
 web_address              | character varying(200) |           |          | 
 telephone_no             | character varying(50)  |           |          | 
 email_address            | character varying(50)  |           |          | 
 free_econ_zone           | boolean                |           |          | 
 notes                    | text                   |           |          | 
 sector_id                | integer                |           |          | 
 legal_form_id            | integer                |           |          | 
 edit_by_user_id          | character varying(100) |           |          | 
 edit_comment             | character varying(500) |           |          | 
 unit_size_id             | integer                |           |          | 
 foreign_participation_id | integer                |           |          | 
 data_source_id           | integer                |           |          | 
 enterprise_id            | integer                |           |          | 
 primary_for_enterprise   | boolean                |           |          | 
 invalid_codes            | jsonb                  |           |          | 
Triggers:
    legal_unit_era_upsert INSTEAD OF INSERT ON legal_unit_era FOR EACH ROW EXECUTE FUNCTION admin.legal_unit_era_upsert()

```
