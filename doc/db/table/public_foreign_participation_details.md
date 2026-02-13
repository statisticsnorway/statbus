```sql
                                                       Table "public.foreign_participation"
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
    "foreign_participation_pkey" PRIMARY KEY, btree (id)
    "ix_foreign_participation_code" UNIQUE, btree (code) WHERE enabled
    "ix_foreign_participation_enabled" btree (enabled)
    "ix_foreign_participation_enabled_code" UNIQUE, btree (enabled, code)
    "ix_status_code" UNIQUE, btree (code) WHERE enabled
Referenced by:
    TABLE "enterprise_group" CONSTRAINT "enterprise_group_foreign_participation_id_fkey" FOREIGN KEY (foreign_participation_id) REFERENCES foreign_participation(id)
    TABLE "legal_unit" CONSTRAINT "legal_unit_foreign_participation_id_fkey" FOREIGN KEY (foreign_participation_id) REFERENCES foreign_participation(id)
Policies:
    POLICY "foreign_participation_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "foreign_participation_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "foreign_participation_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Not-null constraints:
    "foreign_participation_id_not_null" NOT NULL "id"
    "foreign_participation_code_not_null" NOT NULL "code"
    "foreign_participation_name_not_null" NOT NULL "name"
    "foreign_participation_enabled_not_null" NOT NULL "enabled"
    "foreign_participation_custom_not_null" NOT NULL "custom"
    "foreign_participation_created_at_not_null" NOT NULL "created_at"
    "foreign_participation_updated_at_not_null" NOT NULL "updated_at"
Triggers:
    trigger_prevent_foreign_participation_id_update BEFORE UPDATE OF id ON foreign_participation FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()
Access method: heap

```
