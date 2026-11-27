```sql
                                                                                                                                                                                                                                                                            Table "public.quality_finding"
       Column       |         Type          | Collation | Nullable |                             Default                             | Storage  | Compression | Stats target |                                                                                                                                                                                              Description                                                                                                                                                                                               
--------------------+-----------------------+-----------+----------+-----------------------------------------------------------------+----------+-------------+--------------+--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 rule               | quality_rule          |           | not null |                                                                 | plain    |             |              | 
 stat_definition_id | integer               |           |          |                                                                 | plain    |             |              | The summed variable a per-variable rule compares (public.quality_rule_per_stat); NULL for every other rule.
 unit_type          | statistical_unit_type |           | not null |                                                                 | plain    |             |              | 
 unit_id            | integer               |           | not null |                                                                 | plain    |             |              | 
 valid_from         | date                  |           | not null |                                                                 | plain    |             |              | 
 valid_until        | date                  |           | not null |                                                                 | plain    |             |              | 
 valid_range        | daterange             |           | not null | generated always as (daterange(valid_from, valid_until)) stored | extended |             |              | The statistical_unit row's period; with unit_type and unit_id the key of that row.
 existence_from     | date                  |           | not null |                                                                 | plain    |             |              | public.existence_from of the statistical_unit row, copied so that a check is counted at an instant from this table alone (lib/unit-existence.ts: existence_from <= d < existence_until).
 existence_until    | date                  |           | not null |                                                                 | plain    |             |              | public.existence_until of the statistical_unit row; see existence_from.
 detail             | jsonb                 |           |          |                                                                 | extended |             |              | What the rule compared, for a reader of the finding. establishments_above_legal_unit and legal_unit_above_establishments: {"legal_unit": own value, "establishments_sum": sum, "establishments": count}. establishment_activity_differs: {"legal_unit_activity_category_id", "primary_establishment_id", "primary_establishment_activity_category_id"}. NULL for the rules that say all in their name.
 hash_slot          | integer               |           |          | generated always as (hash_slot(unit_type, unit_id)) stored      | plain    |             |              | The unit's public.hash_slot, the partition public.quality_finding_derive() rederives the finding in (0pn35h).
Indexes:
    "quality_finding_count_idx" btree (rule, COALESCE(stat_definition_id, 0), existence_from, existence_until)
    "quality_finding_hash_slot_idx" btree (hash_slot)
    "quality_finding_key" UNIQUE CONSTRAINT, btree (rule, stat_definition_id, unit_type, unit_id, valid_range) NULLS NOT DISTINCT
Check constraints:
    "quality_finding_variable_matches_rule" CHECK (quality_rule_per_stat(rule) = (stat_definition_id IS NOT NULL))
Foreign-key constraints:
    "quality_finding_stat_definition_id_fkey" FOREIGN KEY (stat_definition_id) REFERENCES stat_definition(id) ON DELETE CASCADE
    "quality_finding_statistical_unit_fkey" FOREIGN KEY (unit_type, unit_id, PERIOD valid_range) REFERENCES statistical_unit(unit_type, unit_id, PERIOD valid_range) NOT ENFORCED
Policies:
    POLICY "quality_finding_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "quality_finding_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "quality_finding_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Not-null constraints:
    "quality_finding_rule_not_null" NOT NULL "rule"
    "quality_finding_unit_type_not_null" NOT NULL "unit_type"
    "quality_finding_unit_id_not_null" NOT NULL "unit_id"
    "quality_finding_valid_from_not_null" NOT NULL "valid_from"
    "quality_finding_valid_until_not_null" NOT NULL "valid_until"
    "quality_finding_valid_range_not_null" NOT NULL "valid_range"
    "quality_finding_existence_from_not_null" NOT NULL "existence_from"
    "quality_finding_existence_until_not_null" NOT NULL "existence_until"
Access method: heap

```

**Comment:** The units each data-quality check lists (05pe0x): one row per check (rule, and variable for a per-variable rule) and statistical_unit row it lists. Filled from public.quality_finding_def by public.quality_finding_derive() in worker.derive_quality after statistical_unit is published; it holds every check, switched off or not, so switching one on shows its number at once. The dashboard counts every check at an instant in one query on (rule, stat_definition_id, existence_from, existence_until); the search lists a check's units through public.statistical_unit_quality().
