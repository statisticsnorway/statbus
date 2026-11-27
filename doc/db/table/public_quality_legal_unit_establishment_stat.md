```sql
                                                                                                                                                        Table "public.quality_legal_unit_establishment_stat"
       Column        |         Type          | Collation | Nullable |                          Default                           | Storage  | Compression | Stats target |                                                                                       Description                                                                                        
---------------------+-----------------------+-----------+----------+------------------------------------------------------------+----------+-------------+--------------+------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 check_id            | integer               |           | not null |                                                            | plain    |             |              | The check (public.quality_check_catalogue): which rule, for the variable in stat_definition_id.
 unit_type           | statistical_unit_type |           | not null |                                                            | plain    |             |              | The legal unit's statistical_unit row key: unit_type (always legal_unit), unit_id and valid_range.
 unit_id             | integer               |           | not null |                                                            | plain    |             |              | The legal unit; see unit_type.
 valid_range         | daterange             |           | not null |                                                            | extended |             |              | The statistical_unit row's period; see unit_type.
 existence_from      | date                  |           | not null |                                                            | plain    |             |              | public.existence_from of the statistical_unit row, copied so that a check is counted at an instant from this table alone (lib/unit-existence.ts: existence_from <= d < existence_until).
 existence_until     | date                  |           | not null |                                                            | plain    |             |              | public.existence_until of the statistical_unit row; see existence_from.
 hash_slot           | integer               |           |          | generated always as (hash_slot(unit_type, unit_id)) stored | plain    |             |              | The unit's public.hash_slot, the partition the relation step rederives the finding in (0pn35h).
 stat_definition_id  | integer               |           | not null |                                                            | plain    |             |              | The summed variable compared; the check's own variable (quality_legal_unit_establishment_stat_check_fkey).
 legal_unit_value    | numeric               |           |          |                                                            | main     |             |              | The legal unit's own value of the variable.
 establishments_sum  | numeric               |           |          |                                                            | main     |             |              | The sum of the variable over the legal unit's counted establishments.
 establishment_count | integer               |           | not null |                                                            | plain    |             |              | How many counted establishments the sum is over.
Indexes:
    "quality_legal_unit_establishment_stat_pkey" PRIMARY KEY, btree (check_id, unit_type, unit_id, valid_range)
    "quality_legal_unit_establishment_stat_count_idx" btree (check_id, existence_from, existence_until)
    "quality_legal_unit_establishment_stat_hash_slot_idx" btree (hash_slot)
    "quality_legal_unit_establishment_stat_stat_definition_idx" btree (stat_definition_id)
Foreign-key constraints:
    "quality_legal_unit_establishment_stat_check_fkey" FOREIGN KEY (check_id, stat_definition_id) REFERENCES quality_check(id, stat_definition_id) ON DELETE CASCADE
    "quality_legal_unit_establishment_stat_stat_definition_id_fkey" FOREIGN KEY (stat_definition_id) REFERENCES stat_definition(id) ON DELETE CASCADE
    "quality_legal_unit_establishment_stat_statistical_unit_fkey" FOREIGN KEY (unit_type, unit_id, PERIOD valid_range) REFERENCES statistical_unit(unit_type, unit_id, PERIOD valid_range) NOT ENFORCED
Policies:
    POLICY "quality_legal_unit_establishment_stat_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "quality_legal_unit_establishment_stat_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "quality_legal_unit_establishment_stat_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Not-null constraints:
    "quality_legal_unit_establishment_stat_check_id_not_null" NOT NULL "check_id"
    "quality_legal_unit_establishment_stat_unit_type_not_null" NOT NULL "unit_type"
    "quality_legal_unit_establishment_stat_unit_id_not_null" NOT NULL "unit_id"
    "quality_legal_unit_establishment_stat_valid_range_not_null" NOT NULL "valid_range"
    "quality_legal_unit_establishment_stat_existence_from_not_null" NOT NULL "existence_from"
    "quality_legal_unit_establishment_stat_existence_until_not_null" NOT NULL "existence_until"
    "quality_legal_unit_establishment_st_stat_definition_id_not_null" NOT NULL "stat_definition_id"
    "quality_legal_unit_establishment_s_establishment_count_not_null" NOT NULL "establishment_count"
Access method: heap

```

**Comment:** Findings of the per-variable checks establishments_above_legal_unit and legal_unit_above_establishments (h9mhxe): one row per check (a rule and summed variable) and legal unit's statistical_unit row it lists, with the comparison that decided it. One table serves both rules for every variable because they share one comparison. Filled from public.quality_legal_unit_establishment_stat_def by public.quality_relation_derive per hash partition in worker.derive_quality.
