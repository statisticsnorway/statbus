```sql
                                    Table "public.stat_definition"
   Column    |       Type        | Collation | Nullable |                   Default                   
-------------+-------------------+-----------+----------+---------------------------------------------
 id          | integer           |           | not null | nextval('stat_definition_id_seq'::regclass)
 code        | character varying |           | not null | 
 type        | stat_type         |           | not null | 
 frequency   | stat_frequency    |           | not null | 
 name        | character varying |           | not null | 
 description | text              |           |          | 
 priority    | integer           |           |          | 
 archived    | boolean           |           | not null | false
Indexes:
    "stat_definition_pkey" PRIMARY KEY, btree (id)
    "stat_definition_code_key" UNIQUE CONSTRAINT, btree (code)
    "stat_definition_priority_key" UNIQUE CONSTRAINT, btree (priority)
Referenced by:
    TABLE "stat_for_unit" CONSTRAINT "stat_for_unit_stat_definition_id_fkey" FOREIGN KEY (stat_definition_id) REFERENCES stat_definition(id) ON DELETE RESTRICT
Policies:
    POLICY "stat_definition_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "stat_definition_regular_user_read" FOR SELECT
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
    POLICY "stat_definition_super_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
      WITH CHECK (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
Triggers:
    stat_definition_lifecycle_callbacks_after_delete AFTER DELETE ON stat_definition FOR EACH STATEMENT EXECUTE FUNCTION lifecycle_callbacks.cleanup_and_generate()
    stat_definition_lifecycle_callbacks_after_insert AFTER INSERT ON stat_definition FOR EACH STATEMENT EXECUTE FUNCTION lifecycle_callbacks.cleanup_and_generate()
    stat_definition_lifecycle_callbacks_after_update AFTER UPDATE ON stat_definition FOR EACH STATEMENT EXECUTE FUNCTION lifecycle_callbacks.cleanup_and_generate()
    trigger_prevent_stat_definition_id_update BEFORE UPDATE OF id ON stat_definition FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```
