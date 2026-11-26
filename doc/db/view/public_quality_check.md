```sql
                                View "public.quality_check"
       Column       |     Type     | Collation | Nullable | Default | Storage | Description 
--------------------+--------------+-----------+----------+---------+---------+-------------
 rule               | quality_rule |           |          |         | plain   | 
 stat_definition_id | integer      |           |          |         | plain   | 
 on_dashboard       | boolean      |           |          |         | plain   | 
 priority           | bigint       |           |          |         | plain   | 
View definition:
 WITH check_of AS (
         SELECT r.rule,
            NULL::integer AS stat_definition_id,
            0 AS stat_priority
           FROM unnest(enum_range(NULL::quality_rule)) r(rule)
          WHERE NOT quality_rule_per_stat(r.rule)
        UNION ALL
         SELECT r.rule,
            sd.id,
            sd.priority
           FROM unnest(enum_range(NULL::quality_rule)) r(rule)
             JOIN stat_definition sd ON sd.enabled AND (sd.type = ANY (ARRAY['int'::stat_type, 'float'::stat_type]))
          WHERE quality_rule_per_stat(r.rule)
        )
 SELECT rule,
    stat_definition_id,
    (EXISTS ( SELECT 1
           FROM quality_check_switched_on qs
          WHERE qs.rule = c.rule AND COALESCE(qs.stat_definition_id, 0) = COALESCE(c.stat_definition_id, 0))) AS on_dashboard,
    row_number() OVER (ORDER BY rule, stat_priority, stat_definition_id) AS priority
   FROM check_of c;
Options: security_invoker=on

```

**Comment:** Every data-quality check of this installation (05pe0x): each rule that is not per variable once, and each per-variable rule once per enabled summed statistical variable (stat_definition of type int or float), so adding, disabling or enabling a variable adds or removes its checks with no other step. on_dashboard is true when the check is in public.quality_check_switched_on (1tx1ed): a check starts off. priority orders the checks: by rule (the enum's order), then by the variable's priority. The dashboard and the search's Quality filter show the checks with on_dashboard; Admin > Data quality checks lists them all.
