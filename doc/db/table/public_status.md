```sql
                                          Table "public.status"
         Column          |           Type           | Collation | Nullable |           Default            
-------------------------+--------------------------+-----------+----------+------------------------------
 id                      | integer                  |           | not null | generated always as identity
 code                    | character varying        |           | not null | 
 name                    | text                     |           | not null | 
 assigned_by_default     | boolean                  |           | not null | 
 include_unit_in_reports | boolean                  |           | not null | 
 priority                | integer                  |           | not null | 
 active                  | boolean                  |           | not null | 
 custom                  | boolean                  |           | not null | false
 created_at              | timestamp with time zone |           | not null | statement_timestamp()
 updated_at              | timestamp with time zone |           | not null | statement_timestamp()
Indexes:
    "status_pkey" PRIMARY KEY, btree (id)
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
Triggers:
    trigger_prevent_status_id_update BEFORE UPDATE OF id ON status FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```
