```sql
                          Table "public.postal_index"
     Column     |  Type   | Collation | Nullable |           Default            
----------------+---------+-----------+----------+------------------------------
 id             | integer |           | not null | generated always as identity
 name           | text    |           |          | 
 archived       | boolean |           | not null | false
 name_language1 | text    |           |          | 
 name_language2 | text    |           |          | 
Indexes:
    "postal_index_pkey" PRIMARY KEY, btree (id)
Policies:
    POLICY "postal_index_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "postal_index_regular_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
    POLICY "postal_index_super_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
Triggers:
    trigger_prevent_postal_index_id_update BEFORE UPDATE OF id ON postal_index FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```
