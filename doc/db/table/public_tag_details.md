```sql
                                                                                                              Table "public.tag"
       Column        |           Type           | Collation | Nullable |                                                    Default                                                     | Storage  | Compression | Stats target | Description 
---------------------+--------------------------+-----------+----------+----------------------------------------------------------------------------------------------------------------+----------+-------------+--------------+-------------
 id                  | integer                  |           | not null | generated always as identity                                                                                   | plain    |             |              | 
 path                | ltree                    |           | not null |                                                                                                                | extended |             |              | 
 parent_id           | integer                  |           |          |                                                                                                                | plain    |             |              | 
 level               | integer                  |           |          | generated always as (nlevel(path)) stored                                                                      | plain    |             |              | 
 label               | character varying        |           | not null | generated always as (replace(path::text, '.'::text, ''::text)) stored                                          | extended |             |              | 
 code                | character varying        |           |          | generated always as (NULLIF(regexp_replace(path::text, '[^0-9]'::text, ''::text, 'g'::text), ''::text)) stored | extended |             |              | 
 name                | character varying(256)   |           | not null |                                                                                                                | extended |             |              | 
 description         | text                     |           |          |                                                                                                                | extended |             |              | 
 enabled             | boolean                  |           | not null | true                                                                                                           | plain    |             |              | 
 type                | tag_type                 |           | not null |                                                                                                                | plain    |             |              | 
 context_valid_from  | date                     |           |          |                                                                                                                | plain    |             |              | 
 context_valid_to    | date                     |           |          |                                                                                                                | plain    |             |              | 
 context_valid_until | date                     |           |          | generated always as ((context_valid_to + '1 day'::interval)) stored                                            | plain    |             |              | 
 context_valid_on    | date                     |           |          |                                                                                                                | plain    |             |              | 
 created_at          | timestamp with time zone |           | not null | statement_timestamp()                                                                                          | plain    |             |              | 
 updated_at          | timestamp with time zone |           | not null | statement_timestamp()                                                                                          | plain    |             |              | 
Indexes:
    "tag_pkey" PRIMARY KEY, btree (id)
    "ix_tag_enabled" btree (enabled)
    "ix_tag_type" btree (type)
    "tag_path_key" UNIQUE CONSTRAINT, btree (path)
Check constraints:
    "context_valid_dates_same_nullability" CHECK (context_valid_from IS NULL AND context_valid_to IS NULL AND context_valid_until IS NULL OR context_valid_from IS NOT NULL AND context_valid_to IS NOT NULL AND context_valid_until IS NOT NULL)
    "context_valid_from_lt_context_valid_until" CHECK (context_valid_from < context_valid_until)
Foreign-key constraints:
    "tag_parent_id_fkey" FOREIGN KEY (parent_id) REFERENCES tag(id) ON DELETE RESTRICT
Referenced by:
    TABLE "tag_for_unit" CONSTRAINT "tag_for_unit_tag_id_fkey" FOREIGN KEY (tag_id) REFERENCES tag(id) ON DELETE CASCADE
    TABLE "tag" CONSTRAINT "tag_parent_id_fkey" FOREIGN KEY (parent_id) REFERENCES tag(id) ON DELETE RESTRICT
Policies:
    POLICY "tag_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "tag_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "tag_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Not-null constraints:
    "tag_id_not_null" NOT NULL "id"
    "tag_path_not_null" NOT NULL "path"
    "tag_label_not_null" NOT NULL "label"
    "tag_name_not_null" NOT NULL "name"
    "tag_enabled_not_null" NOT NULL "enabled"
    "tag_type_not_null" NOT NULL "type"
    "tag_created_at_not_null" NOT NULL "created_at"
    "tag_updated_at_not_null" NOT NULL "updated_at"
Triggers:
    trigger_prevent_tag_id_update BEFORE UPDATE OF id ON tag FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()
Access method: heap

```
