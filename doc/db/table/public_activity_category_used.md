```sql
                  Table "public.activity_category_used"
    Column     |          Type          | Collation | Nullable | Default 
---------------+------------------------+-----------+----------+---------
 standard_code | character varying(16)  |           |          | 
 id            | integer                |           |          | 
 path          | ltree                  |           |          | 
 parent_path   | ltree                  |           |          | 
 code          | character varying      |           |          | 
 label         | character varying      |           |          | 
 name          | character varying(256) |           |          | 
 description   | text                   |           |          | 
Indexes:
    "activity_category_used_key" UNIQUE, btree (path)
Policies:
    POLICY "activity_category_used_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "activity_category_used_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "activity_category_used_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)

```
