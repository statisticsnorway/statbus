```sql
                                    Table "public.analysis_queue"
       Column        |           Type           | Collation | Nullable |           Default            
---------------------+--------------------------+-----------+----------+------------------------------
 id                  | integer                  |           | not null | generated always as identity
 user_start_period   | timestamp with time zone |           | not null | 
 user_end_period     | timestamp with time zone |           | not null | 
 user_id             | integer                  |           | not null | 
 comment             | text                     |           |          | 
 server_start_period | timestamp with time zone |           |          | 
 server_end_period   | timestamp with time zone |           |          | 
Indexes:
    "analysis_queue_pkey" PRIMARY KEY, btree (id)
    "ix_analysis_queue_user_id" btree (user_id)
Foreign-key constraints:
    "analysis_queue_user_id_fkey" FOREIGN KEY (user_id) REFERENCES statbus_user(id) ON DELETE CASCADE
Referenced by:
    TABLE "analysis_log" CONSTRAINT "analysis_log_analysis_queue_id_fkey" FOREIGN KEY (analysis_queue_id) REFERENCES analysis_queue(id) ON DELETE CASCADE
Policies:
    POLICY "analysis_queue_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "analysis_queue_regular_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
    POLICY "analysis_queue_super_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
Triggers:
    trigger_prevent_analysis_queue_id_update BEFORE UPDATE OF id ON analysis_queue FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```
