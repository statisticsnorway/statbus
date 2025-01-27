```sql
                                 Table "public.data_source"
   Column   |           Type           | Collation | Nullable |           Default            
------------+--------------------------+-----------+----------+------------------------------
 id         | integer                  |           | not null | generated always as identity
 code       | text                     |           | not null | 
 name       | text                     |           | not null | 
 active     | boolean                  |           | not null | 
 custom     | boolean                  |           | not null | 
 created_at | timestamp with time zone |           | not null | statement_timestamp()
 updated_at | timestamp with time zone |           | not null | statement_timestamp()
Indexes:
    "data_source_pkey" PRIMARY KEY, btree (id)
    "ix_data_source_active_code" UNIQUE, btree (active, code)
    "ix_data_source_code" UNIQUE, btree (code) WHERE active
Referenced by:
    TABLE "activity" CONSTRAINT "activity_data_source_id_fkey" FOREIGN KEY (data_source_id) REFERENCES data_source(id) ON DELETE SET NULL
    TABLE "contact" CONSTRAINT "contact_data_source_id_fkey" FOREIGN KEY (data_source_id) REFERENCES data_source(id)
    TABLE "enterprise_group" CONSTRAINT "enterprise_group_data_source_id_fkey" FOREIGN KEY (data_source_id) REFERENCES data_source(id)
    TABLE "establishment" CONSTRAINT "establishment_data_source_id_fkey" FOREIGN KEY (data_source_id) REFERENCES data_source(id) ON DELETE RESTRICT
    TABLE "legal_unit" CONSTRAINT "legal_unit_data_source_id_fkey" FOREIGN KEY (data_source_id) REFERENCES data_source(id) ON DELETE RESTRICT
    TABLE "location" CONSTRAINT "location_data_source_id_fkey" FOREIGN KEY (data_source_id) REFERENCES data_source(id) ON DELETE SET NULL
    TABLE "person_for_unit" CONSTRAINT "person_for_unit_data_source_id_fkey" FOREIGN KEY (data_source_id) REFERENCES data_source(id) ON DELETE RESTRICT
    TABLE "stat_for_unit" CONSTRAINT "stat_for_unit_data_source_id_fkey" FOREIGN KEY (data_source_id) REFERENCES data_source(id) ON DELETE SET NULL
Policies:
    POLICY "data_source_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "data_source_regular_user_read" FOR SELECT
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
    POLICY "data_source_super_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
      WITH CHECK (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
Triggers:
    trigger_prevent_data_source_id_update BEFORE UPDATE OF id ON data_source FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```
