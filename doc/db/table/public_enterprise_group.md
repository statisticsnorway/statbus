```sql
                                              Table "public.enterprise_group"
          Column          |           Type           | Collation | Nullable |                   Default                    
--------------------------+--------------------------+-----------+----------+----------------------------------------------
 id                       | integer                  |           | not null | nextval('enterprise_group_id_seq'::regclass)
 valid_from               | date                     |           | not null | 
 valid_after              | date                     |           | not null | 
 valid_to                 | date                     |           | not null | 'infinity'::date
 active                   | boolean                  |           | not null | true
 short_name               | character varying(16)    |           |          | 
 name                     | character varying(256)   |           |          | 
 enterprise_group_type_id | integer                  |           |          | 
 contact_person           | text                     |           |          | 
 edit_comment             | character varying(512)   |           |          | 
 edit_by_user_id          | integer                  |           | not null | 
 edit_at                  | timestamp with time zone |           | not null | statement_timestamp()
 unit_size_id             | integer                  |           |          | 
 data_source_id           | integer                  |           |          | 
 reorg_references         | text                     |           |          | 
 reorg_date               | timestamp with time zone |           |          | 
 reorg_type_id            | integer                  |           |          | 
 foreign_participation_id | integer                  |           |          | 
Indexes:
    "enterprise_group_id_daterange_excl" EXCLUDE USING gist (id WITH =, daterange(valid_after, valid_to, '(]'::text) WITH &&) DEFERRABLE
    "enterprise_group_id_valid_after_valid_to_key" UNIQUE CONSTRAINT, btree (id, valid_after, valid_to) DEFERRABLE
    "ix_enterprise_group_data_source_id" btree (data_source_id)
    "ix_enterprise_group_edit_by_user_id" btree (edit_by_user_id)
    "ix_enterprise_group_enterprise_group_type_id" btree (enterprise_group_type_id)
    "ix_enterprise_group_foreign_participation_id" btree (foreign_participation_id)
    "ix_enterprise_group_name" btree (name)
    "ix_enterprise_group_reorg_type_id" btree (reorg_type_id)
    "ix_enterprise_group_size_id" btree (unit_size_id)
Check constraints:
    "enterprise_group_valid_check" CHECK (valid_after < valid_to)
Foreign-key constraints:
    "enterprise_group_data_source_id_fkey" FOREIGN KEY (data_source_id) REFERENCES data_source(id)
    "enterprise_group_edit_by_user_id_fkey" FOREIGN KEY (edit_by_user_id) REFERENCES auth."user"(id) ON DELETE RESTRICT
    "enterprise_group_enterprise_group_type_id_fkey" FOREIGN KEY (enterprise_group_type_id) REFERENCES enterprise_group_type(id)
    "enterprise_group_foreign_participation_id_fkey" FOREIGN KEY (foreign_participation_id) REFERENCES foreign_participation(id)
    "enterprise_group_reorg_type_id_fkey" FOREIGN KEY (reorg_type_id) REFERENCES reorg_type(id)
    "enterprise_group_unit_size_id_fkey" FOREIGN KEY (unit_size_id) REFERENCES unit_size(id)
Policies:
    POLICY "enterprise_group_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "enterprise_group_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "enterprise_group_regular_user_manage"
      TO regular_user
      USING (true)
      WITH CHECK (true)
Triggers:
    trg_enterprise_group_synchronize_valid_from_after BEFORE INSERT OR UPDATE ON enterprise_group FOR EACH ROW EXECUTE FUNCTION synchronize_valid_from_after()
    trigger_prevent_enterprise_group_id_update BEFORE UPDATE OF id ON enterprise_group FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```
