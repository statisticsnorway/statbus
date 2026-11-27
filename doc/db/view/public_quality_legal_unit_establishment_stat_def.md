```sql
                        View "public.quality_legal_unit_establishment_stat_def"
       Column        |         Type          | Collation | Nullable | Default | Storage  | Description 
---------------------+-----------------------+-----------+----------+---------+----------+-------------
 check_id            | integer               |           |          |         | plain    | 
 unit_type           | statistical_unit_type |           |          |         | plain    | 
 unit_id             | integer               |           |          |         | plain    | 
 valid_range         | daterange             |           |          |         | extended | 
 existence_from      | date                  |           |          |         | plain    | 
 existence_until     | date                  |           |          |         | plain    | 
 hash_slot           | integer               |           |          |         | plain    | 
 stat_definition_id  | integer               |           |          |         | plain    | 
 legal_unit_value    | numeric               |           |          |         | main     | 
 establishments_sum  | numeric               |           |          |         | main     | 
 establishment_count | integer               |           |          |         | plain    | 
View definition:
 SELECT qc.id AS check_id,
    c.unit_type,
    c.unit_id,
    daterange(c.valid_from, c.valid_until) AS valid_range,
    unit_existence_from(su.valid_from, su.birth_date) AS existence_from,
    unit_existence_until(su.valid_until, su.death_date) AS existence_until,
    c.hash_slot,
    sd.id AS stat_definition_id,
    c.legal_unit_value,
    c.establishments_sum,
    c.establishment_count::integer AS establishment_count
   FROM legal_unit_establishment_stat_comparison c
     JOIN stat_definition sd ON sd.code::text = c.stat_code::text
     JOIN statistical_unit su ON su.unit_type = c.unit_type AND su.unit_id = c.unit_id AND su.valid_from = c.valid_from AND su.hash_slot = c.hash_slot
     JOIN quality_check qc ON qc.stat_definition_id = sd.id AND (qc.rule = 'establishments_above_legal_unit'::quality_rule AND c.legal_unit_value < c.establishments_sum OR qc.rule = 'legal_unit_above_establishments'::quality_rule AND c.establishments_sum < c.legal_unit_value AND c.establishments_with_value = c.establishment_count);
Options: security_invoker=on

```

**Comment:** The rules of the per-variable checks (ca6dk5) on public.legal_unit_establishment_stat_comparison: establishments_above_legal_unit when the counted establishments' sum is above the legal unit's own value, legal_unit_above_establishments when the own value is above the sum while every counted establishment has a value. One row per check and legal unit row; its columns are those of public.quality_legal_unit_establishment_stat, which public.quality_relation_derive fills from it per hash partition.
