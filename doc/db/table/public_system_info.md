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

**Comment:** Key/value system state surfaced to the admin UI.

RLS ON THIS TABLE GOVERNS USERS, NOT WRITERS. The policies here (authenticated
SELECT, admin_user manage) describe what a USER may do. They are NOT the complete
list of who writes: the upgrade service and the install verb write their own keys
over a SUPERUSER connection, which bypasses RLS entirely.

So a policy-layer audit of this table must not conclude that admin_user is the whole
writer set. It is not, and the catalog cannot show you the rest.

The bypass is the accepted contract, not an oversight: these writers are system
components reporting state, not users acting on data — and a policy written for a
superuser role would be inert, sitting in pg_policy looking like a constraint while
constraining nothing. Governing them by policy would require giving the service a
least-privilege role instead of superuser (STATBUS-308).
