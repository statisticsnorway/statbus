```sql
                              Table "public.legal_form_factory_default"
 Column | Type | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
--------+------+-----------+----------+---------+----------+-------------+--------------+-------------
 code   | text |           | not null |         | extended |             |              | 
 name   | text |           | not null |         | extended |             |              | 
Indexes:
    "legal_form_factory_default_pkey" PRIMARY KEY, btree (code)
Policies:
    POLICY "legal_form_factory_default_admin_user_read" FOR SELECT
      TO admin_user
      USING (true)
    POLICY "legal_form_factory_default_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "legal_form_factory_default_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Not-null constraints:
    "legal_form_factory_default_code_not_null" NOT NULL "code"
    "legal_form_factory_default_name_not_null" NOT NULL "name"
Access method: heap

```

**Comment:** The public.legal_form rows as shipped with StatBus. public.reset (scope getting-started) restores the system rows of public.legal_form to exactly these values, undoing edits; reset never changes this table.
