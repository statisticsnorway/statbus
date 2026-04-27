```sql
                                        Table "public.power_group"
          Column          |           Type           | Collation | Nullable |           Default            
--------------------------+--------------------------+-----------+----------+------------------------------
 id                       | integer                  |           | not null | generated always as identity
 ident                    | text                     |           | not null | generate_power_ident()
 short_name               | character varying(16)    |           |          | 
 name                     | character varying(256)   |           |          | 
 type_id                  | integer                  |           |          | 
 contact_person           | text                     |           |          | 
 unit_size_id             | integer                  |           |          | 
 data_source_id           | integer                  |           |          | 
 foreign_participation_id | integer                  |           |          | 
 edit_comment             | character varying(512)   |           |          | 
 edit_by_user_id          | integer                  |           | not null | auth.uid()
 edit_at                  | timestamp with time zone |           | not null | statement_timestamp()
Indexes:
    "power_group_pkey" PRIMARY KEY, btree (id)
    "ix_power_group_data_source_id" btree (data_source_id)
    "ix_power_group_edit_by_user_id" btree (edit_by_user_id)
    "ix_power_group_foreign_participation_id" btree (foreign_participation_id)
    "ix_power_group_name" btree (name)
    "ix_power_group_type_id" btree (type_id)
    "ix_power_group_unit_size_id" btree (unit_size_id)
    "power_group_ident_key" UNIQUE CONSTRAINT, btree (ident)
Foreign-key constraints:
    "power_group_data_source_id_fkey" FOREIGN KEY (data_source_id) REFERENCES data_source(id)
    "power_group_edit_by_user_id_fkey" FOREIGN KEY (edit_by_user_id) REFERENCES auth."user"(id) ON DELETE RESTRICT
    "power_group_foreign_participation_id_fkey" FOREIGN KEY (foreign_participation_id) REFERENCES foreign_participation(id)
    "power_group_type_id_fkey" FOREIGN KEY (type_id) REFERENCES power_group_type(id)
    "power_group_unit_size_id_fkey" FOREIGN KEY (unit_size_id) REFERENCES unit_size(id)
Referenced by:
    TABLE "legal_relationship" CONSTRAINT "legal_relationship_derived_power_group_id_fkey" FOREIGN KEY (derived_power_group_id) REFERENCES power_group(id) ON DELETE SET NULL
    TABLE "power_root" CONSTRAINT "power_root_power_group_id_fkey" FOREIGN KEY (power_group_id) REFERENCES power_group(id) ON DELETE CASCADE
Policies:
    POLICY "power_group_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "power_group_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "power_group_regular_user_manage"
      TO regular_user
      USING (true)
      WITH CHECK ((edit_by_user_id = auth.uid()))
Triggers:
    a_power_group_log_delete AFTER DELETE ON power_group REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION worker.log_base_change()
    a_power_group_log_insert AFTER INSERT ON power_group REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION worker.log_base_change()
    a_power_group_log_update AFTER UPDATE ON power_group REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION worker.log_base_change()
    trigger_prevent_power_group_id_update BEFORE UPDATE OF id ON power_group FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```
