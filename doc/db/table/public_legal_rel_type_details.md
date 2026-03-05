```sql
                                                                                                                  Table "public.legal_rel_type"
         Column          |           Type           | Collation | Nullable |           Default            | Storage  | Compression | Stats target |                                                 Description                                                  
-------------------------+--------------------------+-----------+----------+------------------------------+----------+-------------+--------------+--------------------------------------------------------------------------------------------------------------
 id                      | integer                  |           | not null | generated always as identity | plain    |             |              | 
 code                    | text                     |           | not null |                              | extended |             |              | Unique code for the relationship type
 name                    | text                     |           | not null |                              | extended |             |              | Human-readable name
 description             | text                     |           |          |                              | extended |             |              | Detailed description of this relationship type
 primary_influencer_only | boolean                  |           | not null | false                        | plain    |             |              | When TRUE, this relationship type forms power group hierarchies (guaranteed single root per influenced unit)
 enabled                 | boolean                  |           | not null | true                         | plain    |             |              | 
 custom                  | boolean                  |           | not null | false                        | plain    |             |              | 
 created_at              | timestamp with time zone |           | not null | statement_timestamp()        | plain    |             |              | 
 updated_at              | timestamp with time zone |           | not null | statement_timestamp()        | plain    |             |              | 
Indexes:
    "legal_rel_type_pkey" PRIMARY KEY, btree (id)
    "ix_legal_rel_type_code" UNIQUE, btree (code) WHERE enabled
    "ix_legal_rel_type_enabled" btree (enabled)
    "ix_legal_rel_type_enabled_code" UNIQUE, btree (enabled, code)
    "legal_rel_type_code_key" UNIQUE CONSTRAINT, btree (code)
    "legal_rel_type_id_primary_influencer_only_key" UNIQUE CONSTRAINT, btree (id, primary_influencer_only)
Referenced by:
    TABLE "legal_relationship" CONSTRAINT "legal_relationship_type_id_fkey" FOREIGN KEY (type_id) REFERENCES legal_rel_type(id) ON DELETE RESTRICT
    TABLE "legal_relationship" CONSTRAINT "legal_relationship_type_id_primary_influencer_only_fkey" FOREIGN KEY (type_id, primary_influencer_only) REFERENCES legal_rel_type(id, primary_influencer_only) ON UPDATE CASCADE
Policies:
    POLICY "legal_rel_type_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "legal_rel_type_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "legal_rel_type_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Not-null constraints:
    "legal_rel_type_id_not_null" NOT NULL "id"
    "legal_rel_type_code_not_null" NOT NULL "code"
    "legal_rel_type_name_not_null" NOT NULL "name"
    "legal_rel_type_primary_influencer_only_not_null" NOT NULL "primary_influencer_only"
    "legal_rel_type_enabled_not_null" NOT NULL "enabled"
    "legal_rel_type_custom_not_null" NOT NULL "custom"
    "legal_rel_type_created_at_not_null" NOT NULL "created_at"
    "legal_rel_type_updated_at_not_null" NOT NULL "updated_at"
Triggers:
    trigger_prevent_legal_rel_type_id_update BEFORE UPDATE OF id ON legal_rel_type FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()
Access method: heap

```
