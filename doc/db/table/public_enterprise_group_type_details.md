```sql
                                                       Table "public.enterprise_group_type"
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
    "enterprise_group_type_pkey" PRIMARY KEY, btree (id)
    "enterprise_group_type_code_key" UNIQUE CONSTRAINT, btree (code)
    "enterprise_group_type_name_key" UNIQUE CONSTRAINT, btree (name)
    "ix_enterprise_group_type_code" UNIQUE, btree (code) WHERE enabled
    "ix_enterprise_group_type_enabled" btree (enabled)
    "ix_enterprise_group_type_enabled_code" UNIQUE, btree (enabled, code)
Referenced by:
    TABLE "enterprise_group" CONSTRAINT "enterprise_group_enterprise_group_type_id_fkey" FOREIGN KEY (enterprise_group_type_id) REFERENCES enterprise_group_type(id)
Policies:
    POLICY "enterprise_group_type_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "enterprise_group_type_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "enterprise_group_type_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Not-null constraints:
    "enterprise_group_type_id_not_null" NOT NULL "id"
    "enterprise_group_type_code_not_null" NOT NULL "code"
    "enterprise_group_type_name_not_null" NOT NULL "name"
    "enterprise_group_type_enabled_not_null" NOT NULL "enabled"
    "enterprise_group_type_custom_not_null" NOT NULL "custom"
    "enterprise_group_type_created_at_not_null" NOT NULL "created_at"
    "enterprise_group_type_updated_at_not_null" NOT NULL "updated_at"
Triggers:
    trigger_prevent_enterprise_group_type_id_update BEFORE UPDATE OF id ON enterprise_group_type FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()
Access method: heap

```
