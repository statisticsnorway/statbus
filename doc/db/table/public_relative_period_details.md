```sql
                                                            Table "public.relative_period"
     Column      |          Type          | Collation | Nullable |           Default            | Storage  | Compression | Stats target | Description 
-----------------+------------------------+-----------+----------+------------------------------+----------+-------------+--------------+-------------
 id              | integer                |           | not null | generated always as identity | plain    |             |              | 
 code            | relative_period_code   |           | not null |                              | plain    |             |              | 
 name_when_query | character varying(256) |           |          |                              | extended |             |              | 
 name_when_input | character varying(256) |           |          |                              | extended |             |              | 
 scope           | relative_period_scope  |           | not null |                              | plain    |             |              | 
 active          | boolean                |           | not null | true                         | plain    |             |              | 
Indexes:
    "relative_period_pkey" PRIMARY KEY, btree (id)
    "relative_period_code_key" UNIQUE CONSTRAINT, btree (code)
Check constraints:
    "scope input_and_query requires name_when_input" CHECK (
CASE scope
    WHEN 'input_and_query'::relative_period_scope THEN name_when_input IS NOT NULL AND name_when_query IS NOT NULL
    WHEN 'query'::relative_period_scope THEN name_when_input IS NULL AND name_when_query IS NOT NULL
    WHEN 'input'::relative_period_scope THEN name_when_input IS NOT NULL AND name_when_query IS NULL
    ELSE NULL::boolean
END)
Policies:
    POLICY "relative_period_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "relative_period_regular_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
      WITH CHECK (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
    POLICY "relative_period_super_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
      WITH CHECK (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
Triggers:
    trigger_prevent_relative_period_id_update BEFORE UPDATE OF id ON relative_period FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()
Access method: heap

```
