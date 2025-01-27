```sql
                                       View "public.establishment_era"
         Column         |           Type           | Collation | Nullable | Default | Storage  | Description 
------------------------+--------------------------+-----------+----------+---------+----------+-------------
 id                     | integer                  |           |          |         | plain    | 
 valid_after            | date                     |           |          |         | plain    | 
 valid_from             | date                     |           |          |         | plain    | 
 valid_to               | date                     |           |          |         | plain    | 
 active                 | boolean                  |           |          |         | plain    | 
 short_name             | character varying(16)    |           |          |         | extended | 
 name                   | character varying(256)   |           |          |         | extended | 
 birth_date             | date                     |           |          |         | plain    | 
 death_date             | date                     |           |          |         | plain    | 
 free_econ_zone         | boolean                  |           |          |         | plain    | 
 sector_id              | integer                  |           |          |         | plain    | 
 status_id              | integer                  |           |          |         | plain    | 
 edit_comment           | character varying(512)   |           |          |         | extended | 
 edit_by_user_id        | integer                  |           |          |         | plain    | 
 edit_at                | timestamp with time zone |           |          |         | plain    | 
 unit_size_id           | integer                  |           |          |         | plain    | 
 data_source_id         | integer                  |           |          |         | plain    | 
 enterprise_id          | integer                  |           |          |         | plain    | 
 legal_unit_id          | integer                  |           |          |         | plain    | 
 primary_for_legal_unit | boolean                  |           |          |         | plain    | 
 primary_for_enterprise | boolean                  |           |          |         | plain    | 
 invalid_codes          | jsonb                    |           |          |         | extended | 
View definition:
 SELECT establishment.id,
    establishment.valid_after,
    establishment.valid_from,
    establishment.valid_to,
    establishment.active,
    establishment.short_name,
    establishment.name,
    establishment.birth_date,
    establishment.death_date,
    establishment.free_econ_zone,
    establishment.sector_id,
    establishment.status_id,
    establishment.edit_comment,
    establishment.edit_by_user_id,
    establishment.edit_at,
    establishment.unit_size_id,
    establishment.data_source_id,
    establishment.enterprise_id,
    establishment.legal_unit_id,
    establishment.primary_for_legal_unit,
    establishment.primary_for_enterprise,
    establishment.invalid_codes
   FROM establishment;
Triggers:
    establishment_era_upsert INSTEAD OF INSERT ON establishment_era FOR EACH ROW EXECUTE FUNCTION admin.establishment_era_upsert()
Options: security_invoker=on

```
