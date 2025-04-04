```sql
                                                             Table "public.import_target_column"
        Column        |           Type           | Collation | Nullable |           Default            | Storage  | Compression | Stats target | Description 
----------------------+--------------------------+-----------+----------+------------------------------+----------+-------------+--------------+-------------
 id                   | integer                  |           | not null | generated always as identity | plain    |             |              | 
 target_id            | integer                  |           |          |                              | plain    |             |              | 
 column_name          | text                     |           | not null |                              | extended |             |              | 
 column_type          | text                     |           | not null |                              | extended |             |              | 
 uniquely_identifying | boolean                  |           | not null |                              | plain    |             |              | 
 created_at           | timestamp with time zone |           | not null | now()                        | plain    |             |              | 
 updated_at           | timestamp with time zone |           | not null | now()                        | plain    |             |              | 
Indexes:
    "import_target_column_pkey" PRIMARY KEY, btree (id)
Foreign-key constraints:
    "import_target_column_target_id_fkey" FOREIGN KEY (target_id) REFERENCES import_target(id) ON DELETE CASCADE
Referenced by:
    TABLE "import_mapping" CONSTRAINT "import_mapping_target_column_id_fkey" FOREIGN KEY (target_column_id) REFERENCES import_target_column(id) ON DELETE CASCADE
Policies:
    POLICY "import_target_column_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "import_target_column_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "import_target_column_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Access method: heap

```
