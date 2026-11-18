```sql
                              Table "public.legal_reorg_type_factory_default"
   Column    | Type | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
-------------+------+-----------+----------+---------+----------+-------------+--------------+-------------
 code        | text |           | not null |         | extended |             |              | 
 name        | text |           | not null |         | extended |             |              | 
 description | text |           | not null |         | extended |             |              | 
Indexes:
    "legal_reorg_type_factory_default_pkey" PRIMARY KEY, btree (code)
Policies:
    POLICY "legal_reorg_type_factory_default_admin_user_read" FOR SELECT
      TO admin_user
      USING (true)
    POLICY "legal_reorg_type_factory_default_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "legal_reorg_type_factory_default_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Not-null constraints:
    "legal_reorg_type_factory_default_code_not_null" NOT NULL "code"
    "legal_reorg_type_factory_default_name_not_null" NOT NULL "name"
    "legal_reorg_type_factory_default_description_not_null" NOT NULL "description"
Access method: heap

```

**Comment:** The public.legal_reorg_type rows as shipped with StatBus. public.reset (scope customisation) restores the system rows of public.legal_reorg_type to exactly these values, undoing edits; reset never changes this table.
