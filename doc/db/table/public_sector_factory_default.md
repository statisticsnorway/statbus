```sql
                                 Table "public.sector_factory_default"
 Column | Type  | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
--------+-------+-----------+----------+---------+----------+-------------+--------------+-------------
 path   | ltree |           | not null |         | extended |             |              | 
 name   | text  |           | not null |         | extended |             |              | 
Indexes:
    "sector_factory_default_pkey" PRIMARY KEY, btree (path)
Policies:
    POLICY "sector_factory_default_admin_user_read" FOR SELECT
      TO admin_user
      USING (true)
    POLICY "sector_factory_default_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "sector_factory_default_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Not-null constraints:
    "sector_factory_default_path_not_null" NOT NULL "path"
    "sector_factory_default_name_not_null" NOT NULL "name"
Access method: heap

```

**Comment:** The public.sector rows as shipped with StatBus. public.reset (scope getting-started) restores the system rows of public.sector to exactly these values, undoing edits; reset never changes this table.
