```sql
                                 Table "public.data_source"
   Column   |           Type           | Collation | Nullable |           Default            
------------+--------------------------+-----------+----------+------------------------------
 id         | integer                  |           | not null | generated always as identity
 code       | text                     |           | not null | 
 name       | text                     |           | not null | 
 enabled    | boolean                  |           | not null | 
 custom     | boolean                  |           | not null | 
 created_at | timestamp with time zone |           | not null | statement_timestamp()
 updated_at | timestamp with time zone |           | not null | statement_timestamp()
Indexes:
    "data_source_pkey" PRIMARY KEY, btree (id)
    "ix_data_source_code" UNIQUE, btree (code) WHERE enabled
    "ix_data_source_enabled" btree (enabled)
    "ix_data_source_enabled_code" UNIQUE, btree (enabled, code)
Referenced by:
    TABLE "activity" CONSTRAINT "activity_data_source_id_fkey" FOREIGN KEY (data_source_id) REFERENCES data_source(id) ON DELETE SET NULL
    TABLE "contact" CONSTRAINT "contact_data_source_id_fkey" FOREIGN KEY (data_source_id) REFERENCES data_source(id)
    TABLE "enterprise_group" CONSTRAINT "enterprise_group_data_source_id_fkey" FOREIGN KEY (data_source_id) REFERENCES data_source(id)
    TABLE "establishment" CONSTRAINT "establishment_data_source_id_fkey" FOREIGN KEY (data_source_id) REFERENCES data_source(id) ON DELETE RESTRICT
    TABLE "import_definition" CONSTRAINT "import_definition_data_source_id_fkey" FOREIGN KEY (data_source_id) REFERENCES data_source(id) ON DELETE RESTRICT
    TABLE "legal_unit" CONSTRAINT "legal_unit_data_source_id_fkey" FOREIGN KEY (data_source_id) REFERENCES data_source(id) ON DELETE RESTRICT
    TABLE "location" CONSTRAINT "location_data_source_id_fkey" FOREIGN KEY (data_source_id) REFERENCES data_source(id) ON DELETE SET NULL
    TABLE "person_for_unit" CONSTRAINT "person_for_unit_data_source_id_fkey" FOREIGN KEY (data_source_id) REFERENCES data_source(id) ON DELETE RESTRICT
    TABLE "stat_for_unit" CONSTRAINT "stat_for_unit_data_source_id_fkey" FOREIGN KEY (data_source_id) REFERENCES data_source(id) ON DELETE SET NULL
Policies:
    POLICY "data_source_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "data_source_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "data_source_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Triggers:
    trigger_prevent_data_source_id_update BEFORE UPDATE OF id ON data_source FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```
