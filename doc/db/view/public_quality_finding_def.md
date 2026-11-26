```sql
                                  View "public.quality_finding_def"
       Column       |         Type          | Collation | Nullable | Default | Storage  | Description 
--------------------+-----------------------+-----------+----------+---------+----------+-------------
 rule               | quality_rule          |           |          |         | plain    | 
 stat_definition_id | integer               |           |          |         | plain    | 
 unit_type          | statistical_unit_type |           |          |         | plain    | 
 unit_id            | integer               |           |          |         | plain    | 
 valid_from         | date                  |           |          |         | plain    | 
 valid_until        | date                  |           |          |         | plain    | 
 detail             | jsonb                 |           |          |         | extended | 
View definition:
 SELECT 'missing_region'::quality_rule AS rule,
    NULL::integer AS stat_definition_id,
    su.unit_type,
    su.unit_id,
    su.valid_from,
    su.valid_until,
    NULL::jsonb AS detail
   FROM statistical_unit su
  WHERE (su.unit_type = ANY (ARRAY['legal_unit'::statistical_unit_type, 'establishment'::statistical_unit_type])) AND su.domestic AND su.physical_country_id IS NOT NULL AND su.physical_region_path IS NULL
UNION ALL
 SELECT 'missing_activity_category'::quality_rule AS rule,
    NULL::integer AS stat_definition_id,
    su.unit_type,
    su.unit_id,
    su.valid_from,
    su.valid_until,
    NULL::jsonb AS detail
   FROM statistical_unit su
  WHERE (su.unit_type = ANY (ARRAY['legal_unit'::statistical_unit_type, 'establishment'::statistical_unit_type])) AND su.primary_activity_category_path IS NULL
UNION ALL
 SELECT 'missing_physical_location'::quality_rule AS rule,
    NULL::integer AS stat_definition_id,
    su.unit_type,
    su.unit_id,
    su.valid_from,
    su.valid_until,
    NULL::jsonb AS detail
   FROM statistical_unit su
  WHERE (su.unit_type = ANY (ARRAY['legal_unit'::statistical_unit_type, 'establishment'::statistical_unit_type])) AND su.physical_country_id IS NULL
UNION ALL
 SELECT 'establishment_activity_differs'::quality_rule AS rule,
    NULL::integer AS stat_definition_id,
    su.unit_type,
    su.unit_id,
    su.valid_from,
    su.valid_until,
    jsonb_build_object('legal_unit_activity_category_id', su.primary_activity_category_id, 'primary_establishment_id', te.unit_id, 'primary_establishment_activity_category_id', te.primary_activity_category_id) AS detail
   FROM statistical_unit su
     JOIN timeline_establishment te ON te.legal_unit_id = su.unit_id AND te.primary_for_legal_unit AND te.valid_from <= su.valid_from AND su.valid_from < te.valid_until
  WHERE su.unit_type = 'legal_unit'::statistical_unit_type AND su.primary_activity_category_id IS DISTINCT FROM te.primary_activity_category_id
UNION ALL
 SELECT 'establishments_above_legal_unit'::quality_rule AS rule,
    sd.id AS stat_definition_id,
    c.unit_type,
    c.unit_id,
    c.valid_from,
    c.valid_until,
    jsonb_build_object('legal_unit', c.legal_unit_value, 'establishments_sum', c.establishments_sum, 'establishments', c.establishment_count) AS detail
   FROM legal_unit_establishment_stat_comparison c
     JOIN stat_definition sd ON sd.code::text = c.stat_code::text
  WHERE c.legal_unit_value < c.establishments_sum
UNION ALL
 SELECT 'legal_unit_above_establishments'::quality_rule AS rule,
    sd.id AS stat_definition_id,
    c.unit_type,
    c.unit_id,
    c.valid_from,
    c.valid_until,
    jsonb_build_object('legal_unit', c.legal_unit_value, 'establishments_sum', c.establishments_sum, 'establishments', c.establishment_count) AS detail
   FROM legal_unit_establishment_stat_comparison c
     JOIN stat_definition sd ON sd.code::text = c.stat_code::text
  WHERE c.establishments_sum < c.legal_unit_value AND c.establishments_with_value = c.establishment_count
UNION ALL
 SELECT 'secondary_activity_equals_primary'::quality_rule AS rule,
    NULL::integer AS stat_definition_id,
    su.unit_type,
    su.unit_id,
    su.valid_from,
    su.valid_until,
    jsonb_build_object('activity_category_id', su.primary_activity_category_id) AS detail
   FROM statistical_unit su
  WHERE (su.unit_type = ANY (ARRAY['legal_unit'::statistical_unit_type, 'establishment'::statistical_unit_type])) AND su.secondary_activity_category_id = su.primary_activity_category_id;
Options: security_invoker=on

```

**Comment:** The rule of every data-quality check (public.quality_rule), read from the published statistical_unit and the legal unit / establishment comparison; public.quality_finding_derive() makes public.quality_finding equal to it. Missing region counts only units located in the installation's own country (domestic): a unit abroad has no region of this country to lack, and a unit without a physical location is missing_physical_location (pkne34). Secondary activity equals primary reads each statistical_unit row, which statistical_unit splits wherever an activity changes, so the row is the period where the two overlap (qjy2eg).
