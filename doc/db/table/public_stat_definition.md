```sql
                                                                                                                                                                                                                                             Table "public.stat_definition"
    Column    |       Type        | Collation | Nullable |                   Default                   | Storage  | Compression | Stats target |                                                                                                                                                                               Description                                                                                                                                                                               
--------------+-------------------+-----------+----------+---------------------------------------------+----------+-------------+--------------+-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 id           | integer           |           | not null | nextval('stat_definition_id_seq'::regclass) | plain    |             |              | 
 code         | character varying |           | not null |                                             | extended |             |              | 
 type         | stat_type         |           | not null |                                             | plain    |             |              | 
 frequency    | stat_frequency    |           | not null |                                             | plain    |             |              | 
 name         | character varying |           | not null |                                             | extended |             |              | 
 description  | text              |           |          |                                             | extended |             |              | 
 priority     | integer           |           |          |                                             | plain    |             |              | UI ordering of the entry fields
 enabled      | boolean           |           | not null | true                                        | plain    |             |              | At the time of data entry, only enabled codes can be used.
 lu_es_rollup | lu_es_rollup      |           | not null | 'sum'::lu_es_rollup                         | plain    |             |              | How a legal unit's total of this variable combines its own value with its establishments' (public.lu_es_rollup); sum by default, the rule of every released version. Read by public.jsonb_stats_lu_es_rollup; changing it recalculates the totals (trigger stat_definition_lu_es_rollup_recalculate). The quality checks comparing the two levels apply only under max.
Indexes:
    "stat_definition_pkey" PRIMARY KEY, btree (id)
    "ix_stat_definition_type" btree (type)
    "stat_definition_code_key" UNIQUE CONSTRAINT, btree (code)
    "stat_definition_enabled_priority_key" UNIQUE, btree (priority) WHERE enabled
Check constraints:
    "stat_definition_code_is_csv_column_name" CHECK (code::text ~ '^[a-z0-9_]+$'::text)
Referenced by:
    TABLE "quality_check_catalogue" CONSTRAINT "quality_check_catalogue_stat_definition_id_fkey" FOREIGN KEY (stat_definition_id) REFERENCES stat_definition(id) ON DELETE CASCADE
    TABLE "quality_check_switched_on" CONSTRAINT "quality_check_switched_on_stat_definition_id_fkey" FOREIGN KEY (stat_definition_id) REFERENCES stat_definition(id) ON DELETE CASCADE
    TABLE "quality_finding" CONSTRAINT "quality_finding_stat_definition_id_fkey" FOREIGN KEY (stat_definition_id) REFERENCES stat_definition(id) ON DELETE CASCADE
    TABLE "quality_legal_unit_establishment_stat" CONSTRAINT "quality_legal_unit_establishment_stat_stat_definition_id_fkey" FOREIGN KEY (stat_definition_id) REFERENCES stat_definition(id) ON DELETE CASCADE
    TABLE "stat_for_unit" CONSTRAINT "stat_for_unit_stat_definition_id_fkey" FOREIGN KEY (stat_definition_id) REFERENCES stat_definition(id) ON DELETE RESTRICT
Policies:
    POLICY "stat_definition_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "stat_definition_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "stat_definition_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Not-null constraints:
    "stat_definition_id_not_null" NOT NULL "id"
    "stat_definition_code_not_null" NOT NULL "code"
    "stat_definition_type_not_null" NOT NULL "type"
    "stat_definition_frequency_not_null" NOT NULL "frequency"
    "stat_definition_name_not_null" NOT NULL "name"
    "stat_definition_enabled_not_null" NOT NULL "enabled"
    "stat_definition_lu_es_rollup_not_null" NOT NULL "lu_es_rollup"
Triggers:
    stat_definition_lifecycle_callbacks_after_delete AFTER DELETE ON stat_definition FOR EACH STATEMENT EXECUTE FUNCTION lifecycle_callbacks.cleanup_and_generate()
    stat_definition_lifecycle_callbacks_after_insert AFTER INSERT ON stat_definition FOR EACH STATEMENT EXECUTE FUNCTION lifecycle_callbacks.cleanup_and_generate()
    stat_definition_lifecycle_callbacks_after_update AFTER UPDATE ON stat_definition FOR EACH STATEMENT EXECUTE FUNCTION lifecycle_callbacks.cleanup_and_generate()
    stat_definition_lu_es_rollup_recalculate AFTER UPDATE ON stat_definition REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION admin.stat_definition_lu_es_rollup_recalculate()
    trigger_prevent_stat_definition_id_update BEFORE UPDATE OF id ON stat_definition FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()
Access method: heap

```
