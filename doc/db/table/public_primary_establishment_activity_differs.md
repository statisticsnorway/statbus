```sql
                                                                                                                                                                                                                  Table "public.primary_establishment_activity_differs"
                   Column                   |         Type          | Collation | Nullable |                             Default                             | Storage  | Compression | Stats target |                                                                                                                                    Description                                                                                                                                     
--------------------------------------------+-----------------------+-----------+----------+-----------------------------------------------------------------+----------+-------------+--------------+------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 unit_type                                  | statistical_unit_type |           | not null |                                                                 | plain    |             |              | 
 unit_id                                    | integer               |           | not null |                                                                 | plain    |             |              | 
 valid_from                                 | date                  |           | not null |                                                                 | plain    |             |              | 
 valid_until                                | date                  |           | not null |                                                                 | plain    |             |              | 
 valid_range                                | daterange             |           | not null | generated always as (daterange(valid_from, valid_until)) stored | extended |             |              | The statistical_unit row's period. With unit_type and unit_id it is both the primary key and the foreign key to statistical_unit, so PostgREST sees a one-to-one relationship and embeds it as a plain join; another primary key makes it one-to-many, aggregated as JSON per row.
 legal_unit_activity_category_id            | integer               |           |          |                                                                 | plain    |             |              | The legal unit's primary activity category (statistical_unit.primary_activity_category_id), NULL when it has none.
 primary_establishment_id                   | integer               |           | not null |                                                                 | plain    |             |              | The establishment recorded as the legal unit's primary at valid_from.
 primary_establishment_activity_category_id | integer               |           |          |                                                                 | plain    |             |              | The primary establishment's primary activity category at valid_from, NULL when it has none.
Indexes:
    "primary_establishment_activity_differs_pkey" PRIMARY KEY, btree (unit_type, unit_id, valid_range)
Foreign-key constraints:
    "primary_establishment_activity_differs_statistical_unit_fkey" FOREIGN KEY (unit_type, unit_id, PERIOD valid_range) REFERENCES statistical_unit(unit_type, unit_id, PERIOD valid_range) NOT ENFORCED
Policies:
    POLICY "primary_establishment_activity_differs_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "primary_establishment_activity_differs_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "primary_establishment_activity_differs_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Not-null constraints:
    "primary_establishment_activity_differs_unit_type_not_null" NOT NULL "unit_type"
    "primary_establishment_activity_differs_unit_id_not_null" NOT NULL "unit_id"
    "primary_establishment_activity_differs_valid_from_not_null" NOT NULL "valid_from"
    "primary_establishment_activity_differs_valid_until_not_null" NOT NULL "valid_until"
    "primary_establishment_activity_differs_valid_range_not_null" NOT NULL "valid_range"
    "primary_establishment_activit_primary_establishment_id_not_null" NOT NULL "primary_establishment_id"
Access method: heap

```

**Comment:** Data quality (xz3jej): one row per legal_unit row of statistical_unit whose primary activity category differs from that of its primary establishment (timeline_establishment.primary_for_legal_unit) valid at the row's valid_from, compared by id, a missing activity on one side counting as a difference. Uses the primary as recorded and never picks one. Filled from primary_establishment_activity_differs_def by primary_establishment_activity_differs_derive() in worker.derive_used_tables, after statistical_unit is published. The dashboard's Data quality card counts it and the search lists it as select=*,primary_establishment_activity_differs!inner().
