```sql
                                     Table "public.stat_definition_factory_default"
   Column    |       Type        | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
-------------+-------------------+-----------+----------+---------+----------+-------------+--------------+-------------
 code        | character varying |           | not null |         | extended |             |              | 
 type        | stat_type         |           | not null |         | plain    |             |              | 
 frequency   | stat_frequency    |           | not null |         | plain    |             |              | 
 name        | character varying |           | not null |         | extended |             |              | 
 description | text              |           |          |         | extended |             |              | 
 priority    | integer           |           | not null |         | plain    |             |              | 
 enabled     | boolean           |           | not null |         | plain    |             |              | 
Indexes:
    "stat_definition_factory_default_pkey" PRIMARY KEY, btree (code)
Policies:
    POLICY "stat_definition_factory_default_admin_user_read" FOR SELECT
      TO admin_user
      USING (true)
    POLICY "stat_definition_factory_default_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "stat_definition_factory_default_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Not-null constraints:
    "stat_definition_factory_default_code_not_null" NOT NULL "code"
    "stat_definition_factory_default_type_not_null" NOT NULL "type"
    "stat_definition_factory_default_frequency_not_null" NOT NULL "frequency"
    "stat_definition_factory_default_name_not_null" NOT NULL "name"
    "stat_definition_factory_default_priority_not_null" NOT NULL "priority"
    "stat_definition_factory_default_enabled_not_null" NOT NULL "enabled"
Access method: heap

```

**Comment:** The public.stat_definition rows as shipped with StatBus. public.reset (scope customisation) restores the system rows of public.stat_definition to exactly these values, undoing edits; reset never changes this table.
