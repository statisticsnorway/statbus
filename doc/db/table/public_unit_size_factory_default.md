```sql
                               Table "public.unit_size_factory_default"
 Column | Type | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
--------+------+-----------+----------+---------+----------+-------------+--------------+-------------
 code   | text |           | not null |         | extended |             |              | 
 name   | text |           | not null |         | extended |             |              | 
Indexes:
    "unit_size_factory_default_pkey" PRIMARY KEY, btree (code)
Policies:
    POLICY "unit_size_factory_default_admin_user_read" FOR SELECT
      TO admin_user
      USING (true)
    POLICY "unit_size_factory_default_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "unit_size_factory_default_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Not-null constraints:
    "unit_size_factory_default_code_not_null" NOT NULL "code"
    "unit_size_factory_default_name_not_null" NOT NULL "name"
Access method: heap

```

**Comment:** The public.unit_size rows as shipped with StatBus. public.reset (scope customisation) restores the system rows of public.unit_size to exactly these values, undoing edits; reset never changes this table.
