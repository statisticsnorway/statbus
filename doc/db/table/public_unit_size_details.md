```sql
                                                             Table "public.unit_size"
   Column   |           Type           | Collation | Nullable |           Default            | Storage  | Compression | Stats target | Description 
------------+--------------------------+-----------+----------+------------------------------+----------+-------------+--------------+-------------
 id         | integer                  |           | not null | generated always as identity | plain    |             |              | 
 code       | text                     |           | not null |                              | extended |             |              | 
 name       | text                     |           | not null |                              | extended |             |              | 
 enabled    | boolean                  |           | not null |                              | plain    |             |              | 
 custom     | boolean                  |           | not null |                              | plain    |             |              | 
 created_at | timestamp with time zone |           | not null | statement_timestamp()        | plain    |             |              | 
 updated_at | timestamp with time zone |           | not null | statement_timestamp()        | plain    |             |              | 
Indexes:
    "unit_size_pkey" PRIMARY KEY, btree (id)
    "ix_unit_size_code" UNIQUE, btree (code) WHERE enabled
    "ix_unit_size_enabled" btree (enabled)
    "ix_unit_size_enabled_code" UNIQUE, btree (enabled, code)
Referenced by:
    TABLE "enterprise_group" CONSTRAINT "enterprise_group_unit_size_id_fkey" FOREIGN KEY (unit_size_id) REFERENCES unit_size(id)
    TABLE "establishment" CONSTRAINT "establishment_unit_size_id_fkey" FOREIGN KEY (unit_size_id) REFERENCES unit_size(id)
    TABLE "legal_unit" CONSTRAINT "legal_unit_unit_size_id_fkey" FOREIGN KEY (unit_size_id) REFERENCES unit_size(id)
Policies:
    POLICY "unit_size_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "unit_size_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "unit_size_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Not-null constraints:
    "unit_size_id_not_null" NOT NULL "id"
    "unit_size_code_not_null" NOT NULL "code"
    "unit_size_name_not_null" NOT NULL "name"
    "unit_size_enabled_not_null" NOT NULL "enabled"
    "unit_size_custom_not_null" NOT NULL "custom"
    "unit_size_created_at_not_null" NOT NULL "created_at"
    "unit_size_updated_at_not_null" NOT NULL "updated_at"
Triggers:
    trigger_prevent_unit_size_id_update BEFORE UPDATE OF id ON unit_size FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()
Access method: heap

```
