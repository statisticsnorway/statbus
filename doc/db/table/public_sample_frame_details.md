```sql
                                                                Table "public.sample_frame"
       Column        |           Type           | Collation | Nullable |           Default            | Storage  | Compression | Stats target | Description 
---------------------+--------------------------+-----------+----------+------------------------------+----------+-------------+--------------+-------------
 id                  | integer                  |           | not null | generated always as identity | plain    |             |              | 
 name                | text                     |           | not null |                              | extended |             |              | 
 description         | text                     |           |          |                              | extended |             |              | 
 predicate           | text                     |           | not null |                              | extended |             |              | 
 fields              | text                     |           | not null |                              | extended |             |              | 
 user_id             | integer                  |           |          |                              | plain    |             |              | 
 status              | integer                  |           | not null |                              | plain    |             |              | 
 file_path           | text                     |           |          |                              | extended |             |              | 
 generated_date_time | timestamp with time zone |           |          |                              | plain    |             |              | 
 creation_date       | timestamp with time zone |           | not null |                              | plain    |             |              | 
 editing_date        | timestamp with time zone |           |          |                              | plain    |             |              | 
Indexes:
    "sample_frame_pkey" PRIMARY KEY, btree (id)
    "ix_sample_frame_user_id" btree (user_id)
Foreign-key constraints:
    "sample_frame_user_id_fkey" FOREIGN KEY (user_id) REFERENCES statbus_user(id) ON DELETE SET NULL
Policies:
    POLICY "sample_frame_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "sample_frame_regular_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
    POLICY "sample_frame_super_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
Triggers:
    trigger_prevent_sample_frame_id_update BEFORE UPDATE OF id ON sample_frame FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()
Access method: heap

```
