```sql
                                         View "public.legal_unit_era"
          Column          |           Type           | Collation | Nullable | Default | Storage  | Description 
--------------------------+--------------------------+-----------+----------+---------+----------+-------------
 id                       | integer                  |           |          |         | plain    | 
 valid_after              | date                     |           |          |         | plain    | 
 valid_from               | date                     |           |          |         | plain    | 
 valid_to                 | date                     |           |          |         | plain    | 
 active                   | boolean                  |           |          |         | plain    | 
 short_name               | character varying(16)    |           |          |         | extended | 
 name                     | character varying(256)   |           |          |         | extended | 
 birth_date               | date                     |           |          |         | plain    | 
 death_date               | date                     |           |          |         | plain    | 
 parent_org_link          | integer                  |           |          |         | plain    | 
 web_address              | character varying(200)   |           |          |         | extended | 
 telephone_no             | character varying(50)    |           |          |         | extended | 
 email_address            | character varying(50)    |           |          |         | extended | 
 free_econ_zone           | boolean                  |           |          |         | plain    | 
 notes                    | text                     |           |          |         | extended | 
 sector_id                | integer                  |           |          |         | plain    | 
 legal_form_id            | integer                  |           |          |         | plain    | 
 reorg_date               | timestamp with time zone |           |          |         | plain    | 
 reorg_references         | integer                  |           |          |         | plain    | 
 reorg_type_id            | integer                  |           |          |         | plain    | 
 edit_by_user_id          | character varying(100)   |           |          |         | extended | 
 edit_comment             | character varying(500)   |           |          |         | extended | 
 unit_size_id             | integer                  |           |          |         | plain    | 
 foreign_participation_id | integer                  |           |          |         | plain    | 
 data_source_id           | integer                  |           |          |         | plain    | 
 enterprise_id            | integer                  |           |          |         | plain    | 
 primary_for_enterprise   | boolean                  |           |          |         | plain    | 
 invalid_codes            | jsonb                    |           |          |         | extended | 
View definition:
 SELECT legal_unit.id,
    legal_unit.valid_after,
    legal_unit.valid_from,
    legal_unit.valid_to,
    legal_unit.active,
    legal_unit.short_name,
    legal_unit.name,
    legal_unit.birth_date,
    legal_unit.death_date,
    legal_unit.parent_org_link,
    legal_unit.web_address,
    legal_unit.telephone_no,
    legal_unit.email_address,
    legal_unit.free_econ_zone,
    legal_unit.notes,
    legal_unit.sector_id,
    legal_unit.legal_form_id,
    legal_unit.reorg_date,
    legal_unit.reorg_references,
    legal_unit.reorg_type_id,
    legal_unit.edit_by_user_id,
    legal_unit.edit_comment,
    legal_unit.unit_size_id,
    legal_unit.foreign_participation_id,
    legal_unit.data_source_id,
    legal_unit.enterprise_id,
    legal_unit.primary_for_enterprise,
    legal_unit.invalid_codes
   FROM legal_unit;
Triggers:
    legal_unit_era_upsert INSTEAD OF INSERT ON legal_unit_era FOR EACH ROW EXECUTE FUNCTION admin.legal_unit_era_upsert()
Options: security_invoker=on

```
