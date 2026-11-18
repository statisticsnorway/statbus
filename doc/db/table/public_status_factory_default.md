```sql
                                             Table "public.status_factory_default"
       Column        |       Type        | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
---------------------+-------------------+-----------+----------+---------+----------+-------------+--------------+-------------
 code                | character varying |           | not null |         | extended |             |              | 
 name                | text              |           | not null |         | extended |             |              | 
 assigned_by_default | boolean           |           | not null |         | plain    |             |              | 
 used_for_counting   | boolean           |           | not null |         | plain    |             |              | 
 priority            | integer           |           | not null |         | plain    |             |              | 
Indexes:
    "status_factory_default_pkey" PRIMARY KEY, btree (code)
Policies:
    POLICY "status_factory_default_admin_user_read" FOR SELECT
      TO admin_user
      USING (true)
    POLICY "status_factory_default_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "status_factory_default_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Not-null constraints:
    "status_factory_default_code_not_null" NOT NULL "code"
    "status_factory_default_name_not_null" NOT NULL "name"
    "status_factory_default_assigned_by_default_not_null" NOT NULL "assigned_by_default"
    "status_factory_default_used_for_counting_not_null" NOT NULL "used_for_counting"
    "status_factory_default_priority_not_null" NOT NULL "priority"
Access method: heap

```

**Comment:** The public.status rows as shipped with StatBus. public.reset (scope customisation) restores the system rows of public.status to exactly these values, undoing edits; reset never changes this table.
