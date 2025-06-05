```sql
                                     Table "public.import_definition_step"
    Column     |  Type   | Collation | Nullable | Default | Storage | Compression | Stats target | Description 
---------------+---------+-----------+----------+---------+---------+-------------+--------------+-------------
 definition_id | integer |           | not null |         | plain   |             |              | 
 step_id       | integer |           | not null |         | plain   |             |              | 
Indexes:
    "import_definition_step_pkey" PRIMARY KEY, btree (definition_id, step_id)
Foreign-key constraints:
    "import_definition_step_definition_id_fkey" FOREIGN KEY (definition_id) REFERENCES import_definition(id) ON DELETE CASCADE
    "import_definition_step_step_id_fkey" FOREIGN KEY (step_id) REFERENCES import_step(id) ON DELETE CASCADE
Policies:
    POLICY "import_definition_step_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "import_definition_step_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "import_definition_step_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Access method: heap

```
