```sql
                          View "public.establishment_era"
         Column         |           Type           | Collation | Nullable | Default 
------------------------+--------------------------+-----------+----------+---------
 id                     | integer                  |           |          | 
 valid_after            | date                     |           |          | 
 valid_from             | date                     |           |          | 
 valid_to               | date                     |           |          | 
 active                 | boolean                  |           |          | 
 short_name             | character varying(16)    |           |          | 
 name                   | character varying(256)   |           |          | 
 birth_date             | date                     |           |          | 
 death_date             | date                     |           |          | 
 parent_org_link        | integer                  |           |          | 
 web_address            | character varying(200)   |           |          | 
 telephone_no           | character varying(50)    |           |          | 
 email_address          | character varying(50)    |           |          | 
 free_econ_zone         | boolean                  |           |          | 
 notes                  | text                     |           |          | 
 sector_id              | integer                  |           |          | 
 reorg_date             | timestamp with time zone |           |          | 
 reorg_references       | integer                  |           |          | 
 reorg_type_id          | integer                  |           |          | 
 edit_by_user_id        | character varying(100)   |           |          | 
 edit_comment           | character varying(500)   |           |          | 
 unit_size_id           | integer                  |           |          | 
 data_source_id         | integer                  |           |          | 
 enterprise_id          | integer                  |           |          | 
 legal_unit_id          | integer                  |           |          | 
 primary_for_legal_unit | boolean                  |           |          | 
 invalid_codes          | jsonb                    |           |          | 
Triggers:
    establishment_era_upsert INSTEAD OF INSERT ON establishment_era FOR EACH ROW EXECUTE FUNCTION admin.establishment_era_upsert()

```
