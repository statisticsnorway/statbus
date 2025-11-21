```sql
                                                                   Table "public.status"
       Column        |           Type           | Collation | Nullable |           Default            | Storage  | Compression | Stats target | Description 
---------------------+--------------------------+-----------+----------+------------------------------+----------+-------------+--------------+-------------
 id                  | integer                  |           | not null | generated always as identity | plain    |             |              | 
 code                | character varying        |           | not null |                              | extended |             |              | 
 name                | text                     |           | not null |                              | extended |             |              | 
 assigned_by_default | boolean                  |           | not null |                              | plain    |             |              | 
 used_for_counting   | boolean                  |           | not null |                              | plain    |             |              | 
 priority            | integer                  |           | not null |                              | plain    |             |              | 
 active              | boolean                  |           | not null |                              | plain    |             |              | 
 custom              | boolean                  |           | not null | false                        | plain    |             |              | 
 created_at          | timestamp with time zone |           | not null | statement_timestamp()        | plain    |             |              | 
 updated_at          | timestamp with time zone |           | not null | statement_timestamp()        | plain    |             |              | 
Indexes:
    "status_pkey" PRIMARY KEY, btree (id)
    "ix_status_active" btree (active)
    "ix_status_only_one_assigned_by_default" UNIQUE, btree (assigned_by_default) WHERE active AND assigned_by_default
    "status_code_active_custom_key" UNIQUE CONSTRAINT, btree (code, active, custom)
Referenced by:
    TABLE "establishment" CONSTRAINT "establishment_status_id_fkey" FOREIGN KEY (status_id) REFERENCES status(id) ON DELETE RESTRICT
    TABLE "legal_unit" CONSTRAINT "legal_unit_status_id_fkey" FOREIGN KEY (status_id) REFERENCES status(id) ON DELETE RESTRICT
Policies:
    POLICY "status_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "status_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "status_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Not-null constraints:
    "status_id_not_null" NOT NULL "id"
    "status_code_not_null" NOT NULL "code"
    "status_name_not_null" NOT NULL "name"
    "status_assigned_by_default_not_null" NOT NULL "assigned_by_default"
    "status_used_for_counting_not_null" NOT NULL "used_for_counting"
    "status_priority_not_null" NOT NULL "priority"
    "status_active_not_null" NOT NULL "active"
    "status_custom_not_null" NOT NULL "custom"
    "status_created_at_not_null" NOT NULL "created_at"
    "status_updated_at_not_null" NOT NULL "updated_at"
Triggers:
    trigger_prevent_status_id_update BEFORE UPDATE OF id ON status FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()
Access method: heap

```
