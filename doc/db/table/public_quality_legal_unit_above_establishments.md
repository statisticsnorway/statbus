```sql
                                                                                                                                                      Table "public.quality_legal_unit_above_establishments"
   Column    |         Type          | Collation | Nullable |                             Default                             | Storage  | Compression | Stats target |                                                                                        Description                                                                                         
-------------+-----------------------+-----------+----------+-----------------------------------------------------------------+----------+-------------+--------------+--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 unit_type   | statistical_unit_type |           | not null |                                                                 | plain    |             |              | 
 unit_id     | integer               |           | not null |                                                                 | plain    |             |              | 
 valid_from  | date                  |           | not null |                                                                 | plain    |             |              | 
 valid_until | date                  |           | not null |                                                                 | plain    |             |              | 
 valid_range | daterange             |           | not null | generated always as (daterange(valid_from, valid_until)) stored | extended |             |              | The statistical_unit row's period. With unit_type and unit_id it is both the primary key and the foreign key to statistical_unit, so PostgREST embeds it as a one-to-one relationship.
 stats       | jsonb                 |           | not null |                                                                 | extended |             |              | Per stat code found: {"legal_unit": own value, "establishments_sum": sum, "establishments": count}, e.g. {"employees": {"legal_unit": 364, "establishments_sum": 5, "establishments": 1}}.
Indexes:
    "quality_legal_unit_above_establishments_pkey" PRIMARY KEY, btree (unit_type, unit_id, valid_range)
Foreign-key constraints:
    "quality_legal_unit_above_establishments_statistical_unit_fkey" FOREIGN KEY (unit_type, unit_id, PERIOD valid_range) REFERENCES statistical_unit(unit_type, unit_id, PERIOD valid_range) NOT ENFORCED
Policies:
    POLICY "quality_legal_unit_above_establishments_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "quality_legal_unit_above_establishments_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "quality_legal_unit_above_establishments_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Not-null constraints:
    "quality_legal_unit_above_establishments_unit_type_not_null" NOT NULL "unit_type"
    "quality_legal_unit_above_establishments_unit_id_not_null" NOT NULL "unit_id"
    "quality_legal_unit_above_establishments_valid_from_not_null" NOT NULL "valid_from"
    "quality_legal_unit_above_establishments_valid_until_not_null" NOT NULL "valid_until"
    "quality_legal_unit_above_establishments_valid_range_not_null" NOT NULL "valid_range"
    "quality_legal_unit_above_establishments_stats_not_null" NOT NULL "stats"
Access method: heap

```

**Comment:** Quality check (ca6dk5): one row per legal_unit row of statistical_unit where, for at least one summed stat, the legal unit's own value is larger than its counted establishments' sum while every one of those establishments has a value. The legal unit's value covers its establishments (UN Guidelines on Statistical Business Registers; Eurostat Business Registers Recommendations Manual), so the rest belongs to an establishment, yet none lacks a value: often an establishment, such as the head office, is missing. A legal unit that is larger while some establishments have no value is not listed, as its own value covers them. Filled from quality_legal_unit_above_establishments_def by quality_legal_unit_establishments_derive() in worker.derive_quality. Search lists it as select=*,quality_legal_unit_above_establishments!inner().
