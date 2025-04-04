```sql
                                  Table "public.import_target_column"
        Column        |           Type           | Collation | Nullable |           Default            
----------------------+--------------------------+-----------+----------+------------------------------
 id                   | integer                  |           | not null | generated always as identity
 target_id            | integer                  |           |          | 
 column_name          | text                     |           | not null | 
 column_type          | text                     |           | not null | 
 uniquely_identifying | boolean                  |           | not null | 
 created_at           | timestamp with time zone |           | not null | now()
 updated_at           | timestamp with time zone |           | not null | now()
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

```
