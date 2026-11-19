```sql
                                                                                                                                                                                                 Table "public.image"
       Column        |           Type           | Collation | Nullable |           Default            | Storage  | Compression | Stats target |                                                                                                                              Description                                                                                                                               
---------------------+--------------------------+-----------+----------+------------------------------+----------+-------------+--------------+------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 id                  | integer                  |           | not null | generated always as identity | plain    |             |              | 
 data                | bytea                    |           | not null |                              | external |             |              | Binary image data with EXTERNAL storage (no compression). At most 256 KB (image_size_limit): photos are few and small; the app keeps the whole picture, scaled so its longest side is at most 800 px, as JPEG. Validated on insert: only PNG, JPEG, GIF, WebP allowed.
 type                | text                     |           | not null | 'image/png'::text            | extended |             |              | MIME type for proper Content-Type header. Auto-detected from magic bytes on insert to prevent Content-Type spoofing attacks.
 uploaded_at         | timestamp with time zone |           | not null | statement_timestamp()        | plain    |             |              | 
 uploaded_by_user_id | integer                  |           |          |                              | plain    |             |              | User who uploaded the image
Indexes:
    "image_pkey" PRIMARY KEY, btree (id)
    "image_id_idx" btree (id)
    "ix_image_uploaded_by_user_id" btree (uploaded_by_user_id)
Check constraints:
    "image_size_limit" CHECK (length(data) <= 262144)
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
Not-null constraints:
    "image_id_not_null" NOT NULL "id"
    "image_data_not_null" NOT NULL "data"
    "image_type_not_null" NOT NULL "type"
    "image_uploaded_at_not_null" NOT NULL "uploaded_at"
Triggers:
    trigger_prevent_image_id_update BEFORE UPDATE OF id ON image FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()
    validate_image_before_insert BEFORE INSERT ON image FOR EACH ROW EXECUTE FUNCTION validate_image_on_insert()
Access method: heap

```

**Comment:** A unit's photo (legal_unit.image_id, establishment.image_id), for example a shop front a field worker took to recognise the unit on the next visit. Each period of a unit may refer to a photo. A photo that no row of either table refers to any more is deleted at commit (admin.image_released). Validates magic bytes on insert to prevent XSS attacks via malicious file uploads.
