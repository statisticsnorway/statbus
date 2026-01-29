```sql
                                                                 Table "public.unit_notes"
       Column        |           Type           | Collation | Nullable |           Default            | Storage  | Compression | Stats target | Description 
---------------------+--------------------------+-----------+----------+------------------------------+----------+-------------+--------------+-------------
 id                  | integer                  |           | not null | generated always as identity | plain    |             |              | 
 notes               | text                     |           | not null |                              | extended |             |              | 
 establishment_id    | integer                  |           |          |                              | plain    |             |              | 
 legal_unit_id       | integer                  |           |          |                              | plain    |             |              | 
 enterprise_id       | integer                  |           |          |                              | plain    |             |              | 
 enterprise_group_id | integer                  |           |          |                              | plain    |             |              | 
 created_at          | timestamp with time zone |           | not null | statement_timestamp()        | plain    |             |              | 
 edit_comment        | character varying(512)   |           |          |                              | extended |             |              | 
 edit_by_user_id     | integer                  |           | not null |                              | plain    |             |              | 
 edit_at             | timestamp with time zone |           | not null | statement_timestamp()        | plain    |             |              | 
Indexes:
    "unit_notes_pkey" PRIMARY KEY, btree (id)
    "ix_unit_notes_edit_by_user_id" btree (edit_by_user_id)
    "unit_notes_unit_consolidated_key" UNIQUE, btree (establishment_id, legal_unit_id, enterprise_id, enterprise_group_id) NULLS NOT DISTINCT
Check constraints:
    "One and only one statistical unit id must be set" CHECK (num_nonnulls(establishment_id, legal_unit_id, enterprise_id, enterprise_group_id) = 1)
    "unit_notes_enterprise_group_id_check" CHECK (admin.enterprise_group_id_exists(enterprise_group_id))
    "unit_notes_establishment_id_check" CHECK (admin.establishment_id_exists(establishment_id))
    "unit_notes_legal_unit_id_check" CHECK (admin.legal_unit_id_exists(legal_unit_id))
Foreign-key constraints:
    "unit_notes_edit_by_user_id_fkey" FOREIGN KEY (edit_by_user_id) REFERENCES auth."user"(id) ON DELETE RESTRICT
    "unit_notes_enterprise_id_fkey" FOREIGN KEY (enterprise_id) REFERENCES enterprise(id) ON DELETE CASCADE
Policies:
    POLICY "unit_notes_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "unit_notes_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "unit_notes_regular_user_manage"
      TO regular_user
      USING (true)
      WITH CHECK (true)
Not-null constraints:
    "unit_notes_id_not_null" NOT NULL "id"
    "unit_notes_notes_not_null" NOT NULL "notes"
    "unit_notes_created_at_not_null" NOT NULL "created_at"
    "unit_notes_edit_by_user_id_not_null" NOT NULL "edit_by_user_id"
    "unit_notes_edit_at_not_null" NOT NULL "edit_at"
Triggers:
    trigger_prevent_unit_notes_id_update BEFORE UPDATE OF id ON unit_notes FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()
Access method: heap

```
