```sql
                                                            Table "public.data_source"
   Column   |           Type           | Collation | Nullable |           Default            | Storage  | Compression | Stats target | Description 
------------+--------------------------+-----------+----------+------------------------------+----------+-------------+--------------+-------------
 id         | integer                  |           | not null | generated always as identity | plain    |             |              | 
 code       | text                     |           | not null |                              | extended |             |              | 
 name       | text                     |           | not null |                              | extended |             |              | 
 active     | boolean                  |           | not null |                              | plain    |             |              | 
 custom     | boolean                  |           | not null |                              | plain    |             |              | 
 created_at | timestamp with time zone |           | not null | statement_timestamp()        | plain    |             |              | 
 updated_at | timestamp with time zone |           | not null | statement_timestamp()        | plain    |             |              | 
Indexes:
    "data_source_pkey" PRIMARY KEY, btree (id)
    "ix_data_source_active" btree (active)
    "ix_data_source_active_code" UNIQUE, btree (active, code)
    "ix_data_source_code" UNIQUE, btree (code) WHERE active
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
Not-null constraints:
    "data_source_id_not_null" NOT NULL "id"
    "data_source_code_not_null" NOT NULL "code"
    "data_source_name_not_null" NOT NULL "name"
    "data_source_active_not_null" NOT NULL "active"
    "data_source_custom_not_null" NOT NULL "custom"
    "data_source_created_at_not_null" NOT NULL "created_at"
    "data_source_updated_at_not_null" NOT NULL "updated_at"
Triggers:
    trigger_prevent_data_source_id_update BEFORE UPDATE OF id ON data_source FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()
Access method: heap

```
