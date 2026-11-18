```sql
                                       Table "public.activity_category_standard_factory_default"
    Column    |               Type               | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
--------------+----------------------------------+-----------+----------+---------+----------+-------------+--------------+-------------
 code         | character varying(16)            |           | not null |         | extended |             |              | 
 name         | character varying                |           | not null |         | extended |             |              | 
 description  | character varying                |           | not null |         | extended |             |              | 
 code_pattern | activity_category_code_behaviour |           | not null |         | plain    |             |              | 
 enabled      | boolean                          |           | not null |         | plain    |             |              | 
 lasts_to     | date                             |           |          |         | plain    |             |              | 
Indexes:
    "activity_category_standard_factory_default_pkey" PRIMARY KEY, btree (code)
Policies:
    POLICY "activity_category_standard_factory_default_admin_user_read" FOR SELECT
      TO admin_user
      USING (true)
    POLICY "activity_category_standard_factory_default_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "activity_category_standard_factory_default_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Not-null constraints:
    "activity_category_standard_factory_default_code_not_null" NOT NULL "code"
    "activity_category_standard_factory_default_name_not_null" NOT NULL "name"
    "activity_category_standard_factory_default_description_not_null" NOT NULL "description"
    "activity_category_standard_factory_defaul_code_pattern_not_null" NOT NULL "code_pattern"
    "activity_category_standard_factory_default_enabled_not_null" NOT NULL "enabled"
Access method: heap

```

**Comment:** The public.activity_category_standard rows as shipped with StatBus. public.reset (scope getting-started) restores the system rows of public.activity_category_standard to exactly these values, undoing edits; reset never changes this table.
