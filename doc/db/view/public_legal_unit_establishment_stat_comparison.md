```sql
                           View "public.legal_unit_establishment_stat_comparison"
          Column           |         Type          | Collation | Nullable | Default | Storage  | Description 
---------------------------+-----------------------+-----------+----------+---------+----------+-------------
 unit_type                 | statistical_unit_type |           |          |         | plain    | 
 unit_id                   | integer               |           |          |         | plain    | 
 valid_from                | date                  |           |          |         | plain    | 
 valid_until               | date                  |           |          |         | plain    | 
 stat_code                 | character varying     |           |          |         | extended | 
 legal_unit_value          | numeric               |           |          |         | main     | 
 establishment_count       | bigint                |           |          |         | plain    | 
 establishments_with_value | bigint                |           |          |         | plain    | 
 establishments_sum        | numeric               |           |          |         | main     | 
View definition:
 WITH establishment_values AS (
         SELECT su_1.unit_id,
            su_1.valid_from,
            sd.code AS stat_code,
            count(*) AS establishment_count,
            count(te.stats -> sd.code::text) AS establishments_with_value,
            sum(((te.stats -> sd.code::text) ->> 'value'::text)::numeric) AS establishments_sum
           FROM statistical_unit su_1
             JOIN timeline_establishment te ON te.legal_unit_id = su_1.unit_id AND te.used_for_counting AND te.valid_from <= su_1.valid_from AND su_1.valid_from < te.valid_until
             JOIN stat_definition sd ON sd.type = ANY (ARRAY['int'::stat_type, 'float'::stat_type])
          WHERE su_1.unit_type = 'legal_unit'::statistical_unit_type
          GROUP BY su_1.unit_id, su_1.valid_from, sd.code
        )
 SELECT su.unit_type,
    su.unit_id,
    su.valid_from,
    su.valid_until,
    ev.stat_code,
    ((su.stats -> ev.stat_code::text) ->> 'value'::text)::numeric AS legal_unit_value,
    ev.establishment_count,
    ev.establishments_with_value,
    ev.establishments_sum
   FROM statistical_unit su
     JOIN establishment_values ev ON ev.unit_id = su.unit_id AND ev.valid_from = su.valid_from
  WHERE su.unit_type = 'legal_unit'::statistical_unit_type;
Options: security_invoker=on

```

**Comment:** Per legal_unit row of statistical_unit and summed stat (int, float): the legal unit's own value (statistical_unit.stats) and its counted establishments' count, count with a value, and sum at the row's valid_from. The rules of quality_establishments_above_legal_unit and quality_legal_unit_above_establishments read it; a legal unit's total takes the larger level (public.jsonb_stats_covers).
