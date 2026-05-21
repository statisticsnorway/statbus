```sql
                                                          Table "public.power_group_type"
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
    "power_group_type_pkey" PRIMARY KEY, btree (id)
    "ix_power_group_type_code" UNIQUE, btree (code) WHERE enabled
    "ix_power_group_type_enabled" btree (enabled)
    "ix_power_group_type_enabled_code" UNIQUE, btree (enabled, code)
    "power_group_type_code_key" UNIQUE CONSTRAINT, btree (code)
    "power_group_type_name_key" UNIQUE CONSTRAINT, btree (name)
Referenced by:
    TABLE "power_group" CONSTRAINT "power_group_type_id_fkey" FOREIGN KEY (type_id) REFERENCES power_group_type(id)
Policies:
    POLICY "power_group_type_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "power_group_type_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "power_group_type_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Not-null constraints:
    "power_group_type_id_not_null" NOT NULL "id"
    "power_group_type_code_not_null" NOT NULL "code"
    "power_group_type_name_not_null" NOT NULL "name"
    "power_group_type_enabled_not_null" NOT NULL "enabled"
    "power_group_type_custom_not_null" NOT NULL "custom"
    "power_group_type_created_at_not_null" NOT NULL "created_at"
    "power_group_type_updated_at_not_null" NOT NULL "updated_at"
Triggers:
    trigger_prevent_power_group_type_id_update BEFORE UPDATE OF id ON power_group_type FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()
Access method: heap

```
