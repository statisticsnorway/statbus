```sql
                                                            Table "public.import_target"
   Column    |           Type           | Collation | Nullable |           Default            | Storage  | Compression | Stats target | Description 
-------------+--------------------------+-----------+----------+------------------------------+----------+-------------+--------------+-------------
 id          | integer                  |           | not null | generated always as identity | plain    |             |              | 
 schema_name | text                     |           | not null |                              | extended |             |              | 
 table_name  | text                     |           |          |                              | extended |             |              | 
 name        | text                     |           | not null |                              | extended |             |              | 
 created_at  | timestamp with time zone |           | not null | now()                        | plain    |             |              | 
 updated_at  | timestamp with time zone |           | not null | now()                        | plain    |             |              | 
Indexes:
    "import_target_pkey" PRIMARY KEY, btree (id)
    "import_target_name_key" UNIQUE CONSTRAINT, btree (name)
    "import_target_schema_name_table_name_key" UNIQUE CONSTRAINT, btree (schema_name, table_name)
Referenced by:
    TABLE "import_definition" CONSTRAINT "import_definition_target_id_fkey" FOREIGN KEY (target_id) REFERENCES import_target(id) ON DELETE CASCADE
    TABLE "import_target_column" CONSTRAINT "import_target_column_target_id_fkey" FOREIGN KEY (target_id) REFERENCES import_target(id) ON DELETE CASCADE
Policies:
    POLICY "import_target_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "import_target_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "import_target_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Access method: heap

```
