```sql
                                                                     Table "public.status"
         Column          |           Type           | Collation | Nullable |           Default            | Storage  | Compression | Stats target | Description 
-------------------------+--------------------------+-----------+----------+------------------------------+----------+-------------+--------------+-------------
 id                      | integer                  |           | not null | generated always as identity | plain    |             |              | 
 code                    | character varying        |           | not null |                              | extended |             |              | 
 name                    | text                     |           | not null |                              | extended |             |              | 
 assigned_by_default     | boolean                  |           | not null |                              | plain    |             |              | 
 include_unit_in_reports | boolean                  |           | not null |                              | plain    |             |              | 
 priority                | integer                  |           | not null |                              | plain    |             |              | 
 active                  | boolean                  |           | not null |                              | plain    |             |              | 
 custom                  | boolean                  |           | not null | false                        | plain    |             |              | 
 created_at              | timestamp with time zone |           | not null | statement_timestamp()        | plain    |             |              | 
 updated_at              | timestamp with time zone |           | not null | statement_timestamp()        | plain    |             |              | 
Indexes:
    "status_pkey" PRIMARY KEY, btree (id)
    "ix_status_only_one_assigned_by_default" UNIQUE, btree (assigned_by_default) WHERE active AND assigned_by_default
    "status_code_active_custom_key" UNIQUE CONSTRAINT, btree (code, active, custom)
Referenced by:
    TABLE "establishment" CONSTRAINT "establishment_status_id_fkey" FOREIGN KEY (status_id) REFERENCES status(id) ON DELETE RESTRICT
    TABLE "legal_unit" CONSTRAINT "legal_unit_status_id_fkey" FOREIGN KEY (status_id) REFERENCES status(id) ON DELETE RESTRICT
Policies:
    POLICY "status_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "status_regular_user_read" FOR SELECT
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
    POLICY "status_super_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
      WITH CHECK (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
Triggers:
    trigger_prevent_status_id_update BEFORE UPDATE OF id ON status FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()
Access method: heap

```
