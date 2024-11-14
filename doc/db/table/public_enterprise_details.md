```sql
                                                              Table "public.enterprise"
     Column      |          Type          | Collation | Nullable |           Default            | Storage  | Compression | Stats target | Description 
-----------------+------------------------+-----------+----------+------------------------------+----------+-------------+--------------+-------------
 id              | integer                |           | not null | generated always as identity | plain    |             |              | 
 active          | boolean                |           | not null | true                         | plain    |             |              | 
 short_name      | character varying(16)  |           |          |                              | extended |             |              | 
 notes           | text                   |           |          |                              | extended |             |              | 
 edit_by_user_id | character varying(100) |           | not null |                              | extended |             |              | 
 edit_comment    | character varying(500) |           |          |                              | extended |             |              | 
Indexes:
    "enterprise_pkey" PRIMARY KEY, btree (id)
Referenced by:
    TABLE "establishment" CONSTRAINT "establishment_enterprise_id_fkey" FOREIGN KEY (enterprise_id) REFERENCES enterprise(id) ON DELETE RESTRICT
    TABLE "external_ident" CONSTRAINT "external_ident_enterprise_id_fkey" FOREIGN KEY (enterprise_id) REFERENCES enterprise(id) ON DELETE CASCADE
    TABLE "legal_unit" CONSTRAINT "legal_unit_enterprise_id_fkey" FOREIGN KEY (enterprise_id) REFERENCES enterprise(id) ON DELETE RESTRICT
    TABLE "tag_for_unit" CONSTRAINT "tag_for_unit_enterprise_id_fkey" FOREIGN KEY (enterprise_id) REFERENCES enterprise(id) ON DELETE CASCADE
Policies:
    POLICY "enterprise_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "enterprise_regular_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
    POLICY "enterprise_super_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
Triggers:
    trigger_prevent_enterprise_id_update BEFORE UPDATE OF id ON enterprise FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()
Access method: heap

```
