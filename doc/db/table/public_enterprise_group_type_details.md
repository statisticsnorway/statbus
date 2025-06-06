```sql
                                                       Table "public.enterprise_group_type"
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
    "enterprise_group_type_pkey" PRIMARY KEY, btree (id)
    "enterprise_group_type_code_key" UNIQUE CONSTRAINT, btree (code)
    "enterprise_group_type_name_key" UNIQUE CONSTRAINT, btree (name)
    "ix_enterprise_group_type_active_code" UNIQUE, btree (active, code)
    "ix_enterprise_group_type_code" UNIQUE, btree (code) WHERE active
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
Triggers:
    trigger_prevent_enterprise_group_type_id_update BEFORE UPDATE OF id ON enterprise_group_type FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()
Access method: heap

```
