```sql
                                                       Table "public.establishment"
         Column         |           Type           | Collation | Nullable |                            Default                            
------------------------+--------------------------+-----------+----------+---------------------------------------------------------------
 id                     | integer                  |           | not null | nextval('establishment_id_seq'::regclass)
 valid_after            | date                     |           | not null | generated always as ((valid_from - '1 day'::interval)) stored
 valid_from             | date                     |           | not null | CURRENT_DATE
 valid_to               | date                     |           | not null | 'infinity'::date
 active                 | boolean                  |           | not null | true
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
 edit_by_user_id        | character varying(100)   |           | not null | 
 edit_comment           | character varying(500)   |           |          | 
 unit_size_id           | integer                  |           |          | 
 data_source_id         | integer                  |           |          | 
 enterprise_id          | integer                  |           |          | 
 legal_unit_id          | integer                  |           |          | 
 primary_for_legal_unit | boolean                  |           |          | 
 invalid_codes          | jsonb                    |           |          | 
Indexes:
    "establishment_active_idx" btree (active)
    "establishment_id_daterange_excl" EXCLUDE USING gist (id WITH =, daterange(valid_after, valid_to, '[)'::text) WITH &&) DEFERRABLE
    "establishment_id_valid_after_valid_to_key" UNIQUE CONSTRAINT, btree (id, valid_after, valid_to) DEFERRABLE
    "ix_establishment_data_source_id" btree (data_source_id)
    "ix_establishment_enterprise_id" btree (enterprise_id)
    "ix_establishment_legal_unit_id" btree (legal_unit_id)
    "ix_establishment_name" btree (name)
    "ix_establishment_reorg_type_id" btree (reorg_type_id)
    "ix_establishment_sector_id" btree (sector_id)
    "ix_establishment_size_id" btree (unit_size_id)
Check constraints:
    "Must have either legal_unit_id or enterprise_id" CHECK (enterprise_id IS NOT NULL AND legal_unit_id IS NULL OR enterprise_id IS NULL AND legal_unit_id IS NOT NULL)
    "enterprise_id enables sector_id" CHECK (
CASE
    WHEN enterprise_id IS NULL THEN sector_id IS NULL
    ELSE NULL::boolean
END)
    "establishment_valid_check" CHECK (valid_after < valid_to)
    "primary_for_legal_unit and legal_unit_id must be defined togeth" CHECK (legal_unit_id IS NOT NULL AND primary_for_legal_unit IS NOT NULL OR legal_unit_id IS NULL AND primary_for_legal_unit IS NULL)
Foreign-key constraints:
    "establishment_data_source_id_fkey" FOREIGN KEY (data_source_id) REFERENCES data_source(id) ON DELETE RESTRICT
    "establishment_enterprise_id_fkey" FOREIGN KEY (enterprise_id) REFERENCES enterprise(id) ON DELETE RESTRICT
    "establishment_reorg_type_id_fkey" FOREIGN KEY (reorg_type_id) REFERENCES reorg_type(id)
    "establishment_sector_id_fkey" FOREIGN KEY (sector_id) REFERENCES sector(id)
    "establishment_unit_size_id_fkey" FOREIGN KEY (unit_size_id) REFERENCES unit_size(id)
Policies:
    POLICY "establishment_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "establishment_regular_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
    POLICY "establishment_super_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
Triggers:
    activity_establishment_id_valid_uk_delete AFTER DELETE ON establishment FROM activity DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.uk_delete_check('activity_establishment_id_valid')
    activity_establishment_id_valid_uk_update AFTER UPDATE OF id, valid_after, valid_to ON establishment FROM activity DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.uk_update_check('activity_establishment_id_valid')
    establishment_legal_unit_id_valid_fk_insert AFTER INSERT ON establishment FROM legal_unit DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_insert_check('establishment_legal_unit_id_valid')
    establishment_legal_unit_id_valid_fk_update AFTER UPDATE OF legal_unit_id, valid_after, valid_to ON establishment FROM legal_unit DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_update_check('establishment_legal_unit_id_valid')
    location_establishment_id_valid_uk_delete AFTER DELETE ON establishment FROM location DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.uk_delete_check('location_establishment_id_valid')
    location_establishment_id_valid_uk_update AFTER UPDATE OF id, valid_after, valid_to ON establishment FROM location DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.uk_update_check('location_establishment_id_valid')
    stat_for_unit_establishment_id_valid_uk_delete AFTER DELETE ON establishment FROM stat_for_unit DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.uk_delete_check('stat_for_unit_establishment_id_valid')
    stat_for_unit_establishment_id_valid_uk_update AFTER UPDATE OF id, valid_after, valid_to ON establishment FROM stat_for_unit DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.uk_update_check('stat_for_unit_establishment_id_valid')
    trigger_prevent_establishment_id_update BEFORE UPDATE OF id ON establishment FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```
