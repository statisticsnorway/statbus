```sql
                                     Table "public.analysis_log"
       Column        |           Type           | Collation | Nullable |           Default            
---------------------+--------------------------+-----------+----------+------------------------------
 id                  | integer                  |           | not null | generated always as identity
 analysis_queue_id   | integer                  |           | not null | 
 establishment_id    | integer                  |           |          | 
 legal_unit_id       | integer                  |           |          | 
 enterprise_id       | integer                  |           |          | 
 enterprise_group_id | integer                  |           |          | 
 issued_at           | timestamp with time zone |           | not null | 
 resolved_at         | timestamp with time zone |           |          | 
 summary_messages    | text                     |           |          | 
 error_values        | text                     |           |          | 
Indexes:
    "analysis_log_pkey" PRIMARY KEY, btree (id)
    "ix_analysis_log_analysis_queue_id_analyzed_queue_id" btree (analysis_queue_id)
    "ix_analysis_log_analysis_queue_id_enterprise_group_id" btree (enterprise_group_id)
    "ix_analysis_log_analysis_queue_id_enterprise_id" btree (enterprise_id)
    "ix_analysis_log_analysis_queue_id_establishment_id" btree (establishment_id)
    "ix_analysis_log_analysis_queue_id_legal_unit_id" btree (legal_unit_id)
Check constraints:
    "One and only one statistical unit id must be set" CHECK (establishment_id IS NOT NULL AND legal_unit_id IS NULL AND enterprise_id IS NULL AND enterprise_group_id IS NULL OR establishment_id IS NULL AND legal_unit_id IS NOT NULL AND enterprise_id IS NULL AND enterprise_group_id IS NULL OR establishment_id IS NULL AND legal_unit_id IS NULL AND enterprise_id IS NOT NULL AND enterprise_group_id IS NULL OR establishment_id IS NULL AND legal_unit_id IS NULL AND enterprise_id IS NULL AND enterprise_group_id IS NOT NULL)
    "analysis_log_enterprise_group_id_check" CHECK (admin.enterprise_group_id_exists(enterprise_group_id))
    "analysis_log_establishment_id_check" CHECK (admin.establishment_id_exists(establishment_id))
    "analysis_log_legal_unit_id_check" CHECK (admin.legal_unit_id_exists(legal_unit_id))
Foreign-key constraints:
    "analysis_log_analysis_queue_id_fkey" FOREIGN KEY (analysis_queue_id) REFERENCES analysis_queue(id) ON DELETE CASCADE
    "analysis_log_enterprise_id_fkey" FOREIGN KEY (enterprise_id) REFERENCES enterprise(id) ON DELETE CASCADE
Policies:
    POLICY "analysis_log_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "analysis_log_regular_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
    POLICY "analysis_log_super_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
Triggers:
    trigger_prevent_analysis_log_id_update BEFORE UPDATE OF id ON analysis_log FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```
