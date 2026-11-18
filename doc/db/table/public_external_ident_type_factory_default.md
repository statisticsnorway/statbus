```sql
                                     Table "public.external_ident_type_factory_default"
   Column    |          Type          | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
-------------+------------------------+-----------+----------+---------+----------+-------------+--------------+-------------
 code        | character varying(128) |           | not null |         | extended |             |              | 
 name        | character varying(50)  |           | not null |         | extended |             |              | 
 description | text                   |           |          |         | extended |             |              | 
 priority    | integer                |           | not null |         | plain    |             |              | 
 enabled     | boolean                |           | not null |         | plain    |             |              | 
Indexes:
    "external_ident_type_factory_default_pkey" PRIMARY KEY, btree (code)
Policies:
    POLICY "external_ident_type_factory_default_admin_user_read" FOR SELECT
      TO admin_user
      USING (true)
    POLICY "external_ident_type_factory_default_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "external_ident_type_factory_default_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Not-null constraints:
    "external_ident_type_factory_default_code_not_null" NOT NULL "code"
    "external_ident_type_factory_default_name_not_null" NOT NULL "name"
    "external_ident_type_factory_default_priority_not_null" NOT NULL "priority"
    "external_ident_type_factory_default_enabled_not_null" NOT NULL "enabled"
Access method: heap

```

**Comment:** The public.external_ident_type rows as shipped with StatBus. public.reset (scope customisation) restores the system rows of public.external_ident_type to exactly these values, undoing edits; reset never changes this table.
