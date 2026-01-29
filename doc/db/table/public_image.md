```sql
                                         Table "public.image"
       Column        |           Type           | Collation | Nullable |           Default            
---------------------+--------------------------+-----------+----------+------------------------------
 id                  | integer                  |           | not null | generated always as identity
 data                | bytea                    |           | not null | 
 type                | text                     |           | not null | 'image/png'::text
 uploaded_at         | timestamp with time zone |           | not null | statement_timestamp()
 uploaded_by_user_id | integer                  |           |          | 
Indexes:
    "image_pkey" PRIMARY KEY, btree (id)
    "image_id_idx" btree (id)
Check constraints:
    "image_size_limit" CHECK (length(data) <= 4194304)
Foreign-key constraints:
    "image_uploaded_by_user_id_fkey" FOREIGN KEY (uploaded_by_user_id) REFERENCES auth."user"(id)
Referenced by:
    TABLE "establishment" CONSTRAINT "establishment_image_id_fkey" FOREIGN KEY (image_id) REFERENCES image(id)
    TABLE "legal_unit" CONSTRAINT "legal_unit_image_id_fkey" FOREIGN KEY (image_id) REFERENCES image(id)
Policies:
    POLICY "image_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "image_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "image_regular_user_manage"
      TO regular_user
      USING (true)
      WITH CHECK (true)
Triggers:
    trigger_prevent_image_id_update BEFORE UPDATE OF id ON image FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()
    validate_image_before_insert BEFORE INSERT ON image FOR EACH ROW EXECUTE FUNCTION validate_image_on_insert()

```
