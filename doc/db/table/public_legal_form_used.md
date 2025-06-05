```sql
          Table "public.legal_form_used"
 Column |  Type   | Collation | Nullable | Default 
--------+---------+-----------+----------+---------
 id     | integer |           |          | 
 code   | text    |           |          | 
 name   | text    |           |          | 
Indexes:
    "legal_form_used_key" UNIQUE, btree (code)
Policies:
    POLICY "legal_form_used_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "legal_form_used_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "legal_form_used_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)

```
