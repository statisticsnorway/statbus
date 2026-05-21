```sql
                                                       Table "public.system_info"
   Column   |           Type           | Collation | Nullable |      Default      | Storage  | Compression | Stats target | Description 
------------+--------------------------+-----------+----------+-------------------+----------+-------------+--------------+-------------
 key        | text                     |           | not null |                   | extended |             |              | 
 value      | text                     |           | not null |                   | extended |             |              | 
 updated_at | timestamp with time zone |           | not null | clock_timestamp() | plain    |             |              | 
Indexes:
    "system_info_pkey" PRIMARY KEY, btree (key)
Policies:
    POLICY "system_info_admin_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "system_info_authenticated_view" FOR SELECT
      TO authenticated
      USING (true)
Not-null constraints:
    "system_info_key_not_null" NOT NULL "key"
    "system_info_value_not_null" NOT NULL "value"
    "system_info_updated_at_not_null" NOT NULL "updated_at"
Access method: heap

```
