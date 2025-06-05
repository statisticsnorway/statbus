```sql
                                                                               Table "public.import_source_column"
    Column     |           Type           | Collation | Nullable |           Default            | Storage  | Compression | Stats target |                       Description                       
---------------+--------------------------+-----------+----------+------------------------------+----------+-------------+--------------+---------------------------------------------------------
 id            | integer                  |           | not null | generated always as identity | plain    |             |              | 
 definition_id | integer                  |           | not null |                              | plain    |             |              | 
 column_name   | text                     |           | not null |                              | extended |             |              | 
 priority      | integer                  |           | not null |                              | plain    |             |              | The 1-based ordering of the columns in the source file.
 created_at    | timestamp with time zone |           | not null | now()                        | plain    |             |              | 
 updated_at    | timestamp with time zone |           | not null | now()                        | plain    |             |              | 
Indexes:
    "import_source_column_pkey" PRIMARY KEY, btree (id)
    "import_source_column_definition_id_column_name_key" UNIQUE CONSTRAINT, btree (definition_id, column_name)
    "import_source_column_definition_id_priority_key" UNIQUE CONSTRAINT, btree (definition_id, priority)
Foreign-key constraints:
    "import_source_column_definition_id_fkey" FOREIGN KEY (definition_id) REFERENCES import_definition(id) ON DELETE CASCADE
Referenced by:
    TABLE "import_mapping" CONSTRAINT "import_mapping_source_column_id_fkey" FOREIGN KEY (source_column_id) REFERENCES import_source_column(id) ON DELETE CASCADE
Policies:
    POLICY "import_source_column_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "import_source_column_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "import_source_column_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Access method: heap

```
