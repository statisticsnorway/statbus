```sql
                                                                                                                                                               Table "public.quality_establishment_activity_differs"
               Column               |         Type          | Collation | Nullable |                          Default                           | Storage  | Compression | Stats target |                                                                                       Description                                                                                        
------------------------------------+-----------------------+-----------+----------+------------------------------------------------------------+----------+-------------+--------------+------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 check_id                           | integer               |           | not null |                                                            | plain    |             |              | The check (public.quality_check_catalogue), always 4.
 unit_type                          | statistical_unit_type |           | not null |                                                            | plain    |             |              | The legal unit's statistical_unit row key: unit_type (always legal_unit), unit_id and valid_range.
 unit_id                            | integer               |           | not null |                                                            | plain    |             |              | The legal unit; see unit_type.
 valid_range                        | daterange             |           | not null |                                                            | extended |             |              | The statistical_unit row's period; see unit_type.
 existence_from                     | date                  |           | not null |                                                            | plain    |             |              | public.existence_from of the statistical_unit row, copied so that a check is counted at an instant from this table alone (lib/unit-existence.ts: existence_from <= d < existence_until).
 existence_until                    | date                  |           | not null |                                                            | plain    |             |              | public.existence_until of the statistical_unit row; see existence_from.
 hash_slot                          | integer               |           |          | generated always as (hash_slot(unit_type, unit_id)) stored | plain    |             |              | The unit's public.hash_slot, the partition the relation step rederives the finding in (0pn35h).
 primary_establishment_id           | integer               |           | not null |                                                            | plain    |             |              | The legal unit's primary establishment over the row's period.
 legal_unit_activity_category_id    | integer               |           |          |                                                            | plain    |             |              | The legal unit's primary activity category; NULL when it has none and its primary establishment has one.
 establishment_activity_category_id | integer               |           |          |                                                            | plain    |             |              | The primary establishment's primary activity category, which differs from the legal unit's; NULL when it has none and the legal unit has one.
Indexes:
    "quality_establishment_activity_differs_pkey" PRIMARY KEY, btree (check_id, unit_type, unit_id, valid_range)
    "quality_activity_differs_primary_establishment_idx" btree (primary_establishment_id)
    "quality_establishment_activity_differs_count_idx" btree (check_id, existence_from, existence_until)
    "quality_establishment_activity_differs_es_activity_idx" btree (establishment_activity_category_id)
    "quality_establishment_activity_differs_hash_slot_idx" btree (hash_slot)
    "quality_establishment_activity_differs_lu_activity_idx" btree (legal_unit_activity_category_id)
Check constraints:
    "quality_establishment_activity_differs_is_its_check" CHECK (check_id = 4)
Foreign-key constraints:
    "quality_activity_differs_primary_establishment_fkey" FOREIGN KEY (primary_establishment_id, PERIOD valid_range) REFERENCES establishment(id, PERIOD valid_range) NOT ENFORCED
    "quality_establishment_activit_establishment_activity_categ_fkey" FOREIGN KEY (establishment_activity_category_id) REFERENCES activity_category(id) ON DELETE CASCADE
    "quality_establishment_activit_legal_unit_activity_category_fkey" FOREIGN KEY (legal_unit_activity_category_id) REFERENCES activity_category(id) ON DELETE CASCADE
    "quality_establishment_activity_differs_check_id_fkey" FOREIGN KEY (check_id) REFERENCES quality_check(id) ON DELETE CASCADE
    "quality_establishment_activity_differs_statistical_unit_fkey" FOREIGN KEY (unit_type, unit_id, PERIOD valid_range) REFERENCES statistical_unit(unit_type, unit_id, PERIOD valid_range) NOT ENFORCED
Policies:
    POLICY "quality_establishment_activity_differs_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "quality_establishment_activity_differs_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "quality_establishment_activity_differs_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Not-null constraints:
    "quality_establishment_activity_differs_check_id_not_null" NOT NULL "check_id"
    "quality_establishment_activity_differs_unit_type_not_null" NOT NULL "unit_type"
    "quality_establishment_activity_differs_unit_id_not_null" NOT NULL "unit_id"
    "quality_establishment_activity_differs_valid_range_not_null" NOT NULL "valid_range"
    "quality_establishment_activity_differs_existence_from_not_null" NOT NULL "existence_from"
    "quality_establishment_activity_differs_existence_until_not_null" NOT NULL "existence_until"
    "quality_establishment_activit_primary_establishment_id_not_null" NOT NULL "primary_establishment_id"
Access method: heap

```

**Comment:** Findings of check 4, establishment_activity_differs (h9mhxe): one row per legal unit's statistical_unit row whose primary establishment has another primary activity category than the legal unit. Filled from public.quality_establishment_activity_differs_def by public.quality_relation_derive per hash partition in worker.derive_quality.
