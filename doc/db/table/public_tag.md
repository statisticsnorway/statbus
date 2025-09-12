```sql
                                                                                   Table "public.tag"
       Column        |           Type           | Collation | Nullable |                                                    Default                                                     
---------------------+--------------------------+-----------+----------+----------------------------------------------------------------------------------------------------------------
 id                  | integer                  |           | not null | generated always as identity
 path                | ltree                    |           | not null | 
 parent_id           | integer                  |           |          | 
 level               | integer                  |           |          | generated always as (nlevel(path)) stored
 label               | character varying        |           | not null | generated always as (replace(path::text, '.'::text, ''::text)) stored
 code                | character varying        |           |          | generated always as (NULLIF(regexp_replace(path::text, '[^0-9]'::text, ''::text, 'g'::text), ''::text)) stored
 name                | character varying(256)   |           | not null | 
 description         | text                     |           |          | 
 active              | boolean                  |           | not null | true
 type                | tag_type                 |           | not null | 
 context_valid_from  | date                     |           |          | 
 context_valid_to    | date                     |           |          | 
 context_valid_until | date                     |           |          | generated always as ((context_valid_to + '1 day'::interval)) stored
 context_valid_on    | date                     |           |          | 
 is_scoped_tag       | boolean                  |           | not null | false
 created_at          | timestamp with time zone |           | not null | statement_timestamp()
 updated_at          | timestamp with time zone |           | not null | statement_timestamp()
Indexes:
    "tag_pkey" PRIMARY KEY, btree (id)
    "ix_tag_active" btree (active)
    "ix_tag_type" btree (type)
    "tag_path_key" UNIQUE CONSTRAINT, btree (path)
Check constraints:
    "context_valid_dates_same_nullability" CHECK (context_valid_from IS NULL AND context_valid_to IS NULL AND context_valid_until IS NULL OR context_valid_from IS NOT NULL AND context_valid_to IS NOT NULL AND context_valid_until IS NOT NULL)
    "context_valid_from_lt_context_valid_until" CHECK (context_valid_from < context_valid_until)
Foreign-key constraints:
    "tag_parent_id_fkey" FOREIGN KEY (parent_id) REFERENCES tag(id) ON DELETE RESTRICT
Referenced by:
    TABLE "external_ident_type" CONSTRAINT "external_ident_type_by_tag_id_fkey" FOREIGN KEY (by_tag_id) REFERENCES tag(id) ON DELETE RESTRICT
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
Triggers:
    trigger_prevent_tag_id_update BEFORE UPDATE OF id ON tag FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```
