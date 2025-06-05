```sql
                                             Table "public.activity_category_used"
    Column     |          Type          | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
---------------+------------------------+-----------+----------+---------+----------+-------------+--------------+-------------
 standard_code | character varying(16)  |           |          |         | extended |             |              | 
 id            | integer                |           |          |         | plain    |             |              | 
 path          | ltree                  |           |          |         | extended |             |              | 
 parent_path   | ltree                  |           |          |         | extended |             |              | 
 code          | character varying      |           |          |         | extended |             |              | 
 label         | character varying      |           |          |         | extended |             |              | 
 name          | character varying(256) |           |          |         | extended |             |              | 
 description   | text                   |           |          |         | extended |             |              | 
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
Access method: heap

```
