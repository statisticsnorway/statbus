```sql
                                  View "public.timepoints"
  Column   |         Type          | Collation | Nullable | Default | Storage | Description 
-----------+-----------------------+-----------+----------+---------+---------+-------------
 unit_type | statistical_unit_type |           |          |         | plain   | 
 unit_id   | integer               |           |          |         | plain   | 
 timepoint | date                  |           |          |         | plain   | 
View definition:
 WITH es AS (
         SELECT 'establishment'::statistical_unit_type AS unit_type,
            establishment.id AS unit_id,
            establishment.valid_after,
            establishment.valid_to
           FROM establishment
        UNION
         SELECT 'establishment'::statistical_unit_type AS unit_type,
            a.establishment_id AS unit_id,
            a.valid_after,
            a.valid_to
           FROM activity a
             JOIN establishment es ON a.establishment_id = es.id AND daterange(a.valid_after, a.valid_to, '(]'::text) <@ daterange(es.valid_after, es.valid_to, '(]'::text)
          WHERE a.establishment_id IS NOT NULL
        UNION
         SELECT 'establishment'::statistical_unit_type AS unit_type,
            l.establishment_id AS unit_id,
            l.valid_after,
            l.valid_to
           FROM location l
             JOIN establishment es ON l.establishment_id = es.id AND daterange(l.valid_after, l.valid_to, '(]'::text) <@ daterange(es.valid_after, es.valid_to, '(]'::text)
          WHERE l.establishment_id IS NOT NULL
        UNION
         SELECT 'establishment'::statistical_unit_type AS unit_type,
            sfu.establishment_id AS unit_id,
            sfu.valid_after,
            sfu.valid_to
           FROM stat_for_unit sfu
             JOIN establishment es ON sfu.establishment_id = es.id AND daterange(sfu.valid_after, sfu.valid_to, '(]'::text) <@ daterange(es.valid_after, es.valid_to, '(]'::text)
          WHERE sfu.establishment_id IS NOT NULL
        ), lu AS (
         SELECT 'legal_unit'::statistical_unit_type AS unit_type,
            legal_unit.id AS unit_id,
            legal_unit.valid_after,
            legal_unit.valid_to
           FROM legal_unit
        UNION
         SELECT 'legal_unit'::statistical_unit_type AS unit_type,
            a.legal_unit_id AS unit_id,
            a.valid_after,
            a.valid_to
           FROM activity a
             JOIN legal_unit lu ON a.legal_unit_id = lu.id AND daterange(a.valid_after, a.valid_to, '(]'::text) <@ daterange(lu.valid_after, lu.valid_to, '(]'::text)
          WHERE a.legal_unit_id IS NOT NULL
        UNION
         SELECT 'legal_unit'::statistical_unit_type AS unit_type,
            l.legal_unit_id AS unit_id,
            l.valid_after,
            l.valid_to
           FROM location l
             JOIN legal_unit lu ON l.legal_unit_id = lu.id AND daterange(l.valid_after, l.valid_to, '(]'::text) <@ daterange(lu.valid_after, lu.valid_to, '(]'::text)
          WHERE l.legal_unit_id IS NOT NULL
        UNION
         SELECT 'legal_unit'::statistical_unit_type AS unit_type,
            sfu.legal_unit_id AS unit_id,
            sfu.valid_after,
            sfu.valid_to
           FROM stat_for_unit sfu
             JOIN legal_unit lu ON sfu.legal_unit_id = lu.id AND daterange(sfu.valid_after, sfu.valid_to, '(]'::text) <@ daterange(lu.valid_after, lu.valid_to, '(]'::text)
          WHERE sfu.legal_unit_id IS NOT NULL
        UNION
         SELECT 'legal_unit'::statistical_unit_type AS unit_type,
            lu.id AS unit_id,
            es.valid_after,
            es.valid_to
           FROM establishment es
             JOIN legal_unit lu ON es.legal_unit_id = lu.id AND daterange(es.valid_after, es.valid_to, '(]'::text) <@ daterange(lu.valid_after, lu.valid_to, '(]'::text)
          WHERE es.legal_unit_id IS NOT NULL
        UNION
         SELECT 'legal_unit'::statistical_unit_type AS unit_type,
            es.legal_unit_id AS unit_id,
            a.valid_after,
            a.valid_to
           FROM activity a
             JOIN establishment es ON a.establishment_id = es.id AND daterange(a.valid_after, a.valid_to, '(]'::text) <@ daterange(es.valid_after, es.valid_to, '(]'::text)
             JOIN legal_unit lu ON es.legal_unit_id = lu.id AND daterange(a.valid_after, a.valid_to, '(]'::text) <@ daterange(lu.valid_after, lu.valid_to, '(]'::text)
          WHERE es.legal_unit_id IS NOT NULL
        UNION
         SELECT 'legal_unit'::statistical_unit_type AS unit_type,
            lu.id AS unit_id,
            sfu.valid_after,
            sfu.valid_to
           FROM stat_for_unit sfu
             JOIN establishment es ON sfu.establishment_id = es.id AND daterange(sfu.valid_after, sfu.valid_to, '(]'::text) <@ daterange(es.valid_after, es.valid_to, '(]'::text)
             JOIN legal_unit lu ON es.legal_unit_id = lu.id AND daterange(sfu.valid_after, sfu.valid_to, '(]'::text) <@ daterange(lu.valid_after, lu.valid_to, '(]'::text)
          WHERE es.legal_unit_id IS NOT NULL
        ), en AS (
         SELECT 'enterprise'::statistical_unit_type AS unit_type,
            legal_unit.enterprise_id AS unit_id,
            legal_unit.valid_after,
            legal_unit.valid_to
           FROM legal_unit
        UNION
         SELECT 'enterprise'::statistical_unit_type AS unit_type,
            es.enterprise_id AS unit_id,
            es.valid_after,
            es.valid_to
           FROM establishment es
          WHERE es.enterprise_id IS NOT NULL
        UNION
         SELECT 'enterprise'::statistical_unit_type AS unit_type,
            lu.enterprise_id AS unit_id,
            es.valid_after,
            es.valid_to
           FROM establishment es
             JOIN legal_unit lu ON es.legal_unit_id = lu.id AND daterange(es.valid_after, es.valid_to, '(]'::text) <@ daterange(lu.valid_after, lu.valid_to, '(]'::text)
          WHERE lu.enterprise_id IS NOT NULL
        UNION
         SELECT 'enterprise'::statistical_unit_type AS unit_type,
            es.enterprise_id AS unit_id,
            a.valid_after,
            a.valid_to
           FROM activity a
             JOIN establishment es ON a.establishment_id = es.id AND daterange(a.valid_after, a.valid_to, '(]'::text) <@ daterange(es.valid_after, es.valid_to, '(]'::text)
          WHERE es.enterprise_id IS NOT NULL
        UNION
         SELECT 'enterprise'::statistical_unit_type AS unit_type,
            lu.enterprise_id AS unit_id,
            a.valid_after,
            a.valid_to
           FROM activity a
             JOIN legal_unit lu ON a.legal_unit_id = lu.id AND daterange(a.valid_after, a.valid_to, '(]'::text) <@ daterange(lu.valid_after, lu.valid_to, '(]'::text)
          WHERE lu.enterprise_id IS NOT NULL
        UNION
         SELECT 'enterprise'::statistical_unit_type AS unit_type,
            lu.enterprise_id AS unit_id,
            a.valid_after,
            a.valid_to
           FROM activity a
             JOIN establishment es ON a.establishment_id = es.id AND daterange(a.valid_after, a.valid_to, '(]'::text) <@ daterange(es.valid_after, es.valid_to, '(]'::text)
             JOIN legal_unit lu ON es.legal_unit_id = lu.id AND daterange(a.valid_after, a.valid_to, '(]'::text) <@ daterange(lu.valid_after, lu.valid_to, '(]'::text)
          WHERE lu.enterprise_id IS NOT NULL
        UNION
         SELECT 'enterprise'::statistical_unit_type AS unit_type,
            es.enterprise_id AS unit_id,
            l.valid_after,
            l.valid_to
           FROM location l
             JOIN establishment es ON l.establishment_id = es.id AND daterange(l.valid_after, l.valid_to, '(]'::text) <@ daterange(es.valid_after, es.valid_to, '(]'::text)
          WHERE es.enterprise_id IS NOT NULL
        UNION
         SELECT 'enterprise'::statistical_unit_type AS unit_type,
            lu.enterprise_id AS unit_id,
            l.valid_after,
            l.valid_to
           FROM location l
             JOIN legal_unit lu ON l.legal_unit_id = lu.id AND daterange(l.valid_after, l.valid_to, '(]'::text) <@ daterange(lu.valid_after, lu.valid_to, '(]'::text)
          WHERE lu.enterprise_id IS NOT NULL AND lu.primary_for_enterprise
        UNION
         SELECT 'enterprise'::statistical_unit_type AS unit_type,
            es.enterprise_id AS unit_id,
            sfu.valid_after,
            sfu.valid_to
           FROM stat_for_unit sfu
             JOIN establishment es ON sfu.establishment_id = es.id AND daterange(sfu.valid_after, sfu.valid_to, '(]'::text) <@ daterange(es.valid_after, es.valid_to, '(]'::text)
          WHERE es.enterprise_id IS NOT NULL
        UNION
         SELECT 'enterprise'::statistical_unit_type AS unit_type,
            lu.enterprise_id AS unit_id,
            sfu.valid_after,
            sfu.valid_to
           FROM stat_for_unit sfu
             JOIN legal_unit lu ON sfu.legal_unit_id = lu.id AND daterange(sfu.valid_after, sfu.valid_to, '(]'::text) <@ daterange(lu.valid_after, lu.valid_to, '(]'::text)
          WHERE lu.enterprise_id IS NOT NULL
        UNION
         SELECT 'enterprise'::statistical_unit_type AS unit_type,
            lu.enterprise_id AS unit_id,
            sfu.valid_after,
            sfu.valid_to
           FROM stat_for_unit sfu
             JOIN establishment es ON sfu.establishment_id = es.id AND daterange(sfu.valid_after, sfu.valid_to, '(]'::text) <@ daterange(es.valid_after, es.valid_to, '(]'::text)
             JOIN legal_unit lu ON es.legal_unit_id = lu.id AND daterange(sfu.valid_after, sfu.valid_to, '(]'::text) <@ daterange(lu.valid_after, lu.valid_to, '(]'::text)
          WHERE lu.enterprise_id IS NOT NULL
        ), base AS (
         SELECT es.unit_type,
            es.unit_id,
            es.valid_after,
            es.valid_to
           FROM es
        UNION ALL
         SELECT lu.unit_type,
            lu.unit_id,
            lu.valid_after,
            lu.valid_to
           FROM lu
        UNION ALL
         SELECT en.unit_type,
            en.unit_id,
            en.valid_after,
            en.valid_to
           FROM en
        ), timepoint AS (
         SELECT base.unit_type,
            base.unit_id,
            base.valid_after AS timepoint
           FROM base
        UNION
         SELECT base.unit_type,
            base.unit_id,
            base.valid_to AS timepoint
           FROM base
        )
 SELECT timepoint.unit_type,
    timepoint.unit_id,
    timepoint.timepoint
   FROM timepoint
  ORDER BY timepoint.unit_type, timepoint.unit_id, timepoint.timepoint;

```
