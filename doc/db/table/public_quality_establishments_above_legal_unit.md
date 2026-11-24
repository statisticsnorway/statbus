```sql
                                                                                                                                                        Table "public.quality_establishments_above_legal_unit"
   Column    |         Type          | Collation | Nullable |                             Default                             | Storage  | Compression | Stats target |                                                                                          Description                                                                                           
-------------+-----------------------+-----------+----------+-----------------------------------------------------------------+----------+-------------+--------------+------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 unit_type   | statistical_unit_type |           | not null |                                                                 | plain    |             |              | 
 unit_id     | integer               |           | not null |                                                                 | plain    |             |              | 
 valid_from  | date                  |           | not null |                                                                 | plain    |             |              | 
 valid_until | date                  |           | not null |                                                                 | plain    |             |              | 
 valid_range | daterange             |           | not null | generated always as (daterange(valid_from, valid_until)) stored | extended |             |              | The statistical_unit row's period. With unit_type and unit_id it is both the primary key and the foreign key to statistical_unit, so PostgREST embeds it as a one-to-one relationship.
 stats       | jsonb                 |           | not null |                                                                 | extended |             |              | Per stat code found: {"legal_unit": own value, "establishments_sum": sum, "establishments": count}, e.g. {"employees": {"legal_unit": 989, "establishments_sum": 1055, "establishments": 19}}.
Indexes:
    "quality_establishments_above_legal_unit_pkey" PRIMARY KEY, btree (unit_type, unit_id, valid_range)
Foreign-key constraints:
    "quality_establishments_above_legal_unit_statistical_unit_fkey" FOREIGN KEY (unit_type, unit_id, PERIOD valid_range) REFERENCES statistical_unit(unit_type, unit_id, PERIOD valid_range) NOT ENFORCED
Policies:
    POLICY "quality_establishments_above_legal_unit_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "quality_establishments_above_legal_unit_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "quality_establishments_above_legal_unit_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Not-null constraints:
    "quality_establishments_above_legal_unit_unit_type_not_null" NOT NULL "unit_type"
    "quality_establishments_above_legal_unit_unit_id_not_null" NOT NULL "unit_id"
    "quality_establishments_above_legal_unit_valid_from_not_null" NOT NULL "valid_from"
    "quality_establishments_above_legal_unit_valid_until_not_null" NOT NULL "valid_until"
    "quality_establishments_above_legal_unit_valid_range_not_null" NOT NULL "valid_range"
    "quality_establishments_above_legal_unit_stats_not_null" NOT NULL "stats"
Access method: heap

```

**Comment:** Quality check (ca6dk5): one row per legal_unit row of statistical_unit where, for at least one summed stat, the legal unit has its own value and its counted establishments' values add up to more. Establishments are parts of their legal unit (UN Guidelines on Statistical Business Registers; Eurostat Business Registers Recommendations Manual), so the parts exceeding the whole is a reporting error on one level; the legal unit's total takes the establishments' sum (public.jsonb_stats_covers). Filled from quality_establishments_above_legal_unit_def by quality_legal_unit_establishments_derive() in worker.derive_quality. Search lists it as select=*,quality_establishments_above_legal_unit!inner().
