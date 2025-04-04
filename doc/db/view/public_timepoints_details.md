```sql
                                  View "public.timepoints"
  Column   |         Type          | Collation | Nullable | Default | Storage | Description 
-----------+-----------------------+-----------+----------+---------+---------+-------------
 unit_type | statistical_unit_type |           |          |         | plain   | 
 unit_id   | integer               |           |          |         | plain   | 
 timepoint | date                  |           |          |         | plain   | 
View definition:
 WITH es_base AS (
         SELECT 'establishment'::statistical_unit_type AS unit_type,
            establishment.id AS unit_id,
            establishment.valid_after,
            establishment.valid_to
           FROM establishment
        ), es_activity AS (
         SELECT 'establishment'::statistical_unit_type AS unit_type,
            a.establishment_id AS unit_id,
            GREATEST(a.valid_after, es.valid_after) AS valid_after,
            LEAST(a.valid_to, es.valid_to) AS valid_to
           FROM activity a
             JOIN establishment es ON a.establishment_id = es.id
          WHERE a.establishment_id IS NOT NULL AND after_to_overlaps(a.valid_after, a.valid_to, es.valid_after, es.valid_to)
        ), es_location AS (
         SELECT 'establishment'::statistical_unit_type AS unit_type,
            l.establishment_id AS unit_id,
            GREATEST(l.valid_after, es.valid_after) AS valid_after,
            LEAST(l.valid_to, es.valid_to) AS valid_to
           FROM location l
             JOIN establishment es ON l.establishment_id = es.id
          WHERE l.establishment_id IS NOT NULL AND after_to_overlaps(l.valid_after, l.valid_to, es.valid_after, es.valid_to)
        ), es_stat AS (
         SELECT 'establishment'::statistical_unit_type AS unit_type,
            sfu.establishment_id AS unit_id,
            GREATEST(sfu.valid_after, es.valid_after) AS valid_after,
            LEAST(sfu.valid_to, es.valid_to) AS valid_to
           FROM stat_for_unit sfu
             JOIN establishment es ON sfu.establishment_id = es.id
          WHERE sfu.establishment_id IS NOT NULL AND after_to_overlaps(sfu.valid_after, sfu.valid_to, es.valid_after, es.valid_to)
        ), es_combined AS (
         SELECT es_base.unit_type,
            es_base.unit_id,
            es_base.valid_after,
            es_base.valid_to
           FROM es_base
        UNION ALL
         SELECT es_activity.unit_type,
            es_activity.unit_id,
            es_activity.valid_after,
            es_activity.valid_to
           FROM es_activity
        UNION ALL
         SELECT es_location.unit_type,
            es_location.unit_id,
            es_location.valid_after,
            es_location.valid_to
           FROM es_location
        UNION ALL
         SELECT es_stat.unit_type,
            es_stat.unit_id,
            es_stat.valid_after,
            es_stat.valid_to
           FROM es_stat
        ), lu_base AS (
         SELECT 'legal_unit'::statistical_unit_type AS unit_type,
            legal_unit.id AS unit_id,
            legal_unit.valid_after,
            legal_unit.valid_to
           FROM legal_unit
        ), lu_activity AS (
         SELECT 'legal_unit'::statistical_unit_type AS unit_type,
            a.legal_unit_id AS unit_id,
            GREATEST(a.valid_after, lu.valid_after) AS valid_after,
            LEAST(a.valid_to, lu.valid_to) AS valid_to
           FROM activity a
             JOIN legal_unit lu ON a.legal_unit_id = lu.id
          WHERE a.legal_unit_id IS NOT NULL AND after_to_overlaps(a.valid_after, a.valid_to, lu.valid_after, lu.valid_to)
        ), lu_location AS (
         SELECT 'legal_unit'::statistical_unit_type AS unit_type,
            l.legal_unit_id AS unit_id,
            GREATEST(l.valid_after, lu.valid_after) AS valid_after,
            LEAST(l.valid_to, lu.valid_to) AS valid_to
           FROM location l
             JOIN legal_unit lu ON l.legal_unit_id = lu.id
          WHERE l.legal_unit_id IS NOT NULL AND after_to_overlaps(l.valid_after, l.valid_to, lu.valid_after, lu.valid_to)
        ), lu_stat AS (
         SELECT 'legal_unit'::statistical_unit_type AS unit_type,
            sfu.legal_unit_id AS unit_id,
            GREATEST(sfu.valid_after, lu.valid_after) AS valid_after,
            LEAST(sfu.valid_to, lu.valid_to) AS valid_to
           FROM stat_for_unit sfu
             JOIN legal_unit lu ON sfu.legal_unit_id = lu.id
          WHERE sfu.legal_unit_id IS NOT NULL AND after_to_overlaps(sfu.valid_after, sfu.valid_to, lu.valid_after, lu.valid_to)
        ), lu_establishment AS (
         SELECT 'legal_unit'::statistical_unit_type AS unit_type,
            es.legal_unit_id AS unit_id,
            GREATEST(es.valid_after, lu.valid_after) AS valid_after,
            LEAST(es.valid_to, lu.valid_to) AS valid_to
           FROM establishment es
             JOIN legal_unit lu ON es.legal_unit_id = lu.id
          WHERE es.legal_unit_id IS NOT NULL AND after_to_overlaps(es.valid_after, es.valid_to, lu.valid_after, lu.valid_to)
        ), lu_activity_establishment AS (
         SELECT 'legal_unit'::statistical_unit_type AS unit_type,
            es.legal_unit_id AS unit_id,
            GREATEST(a.valid_after, es.valid_after, lu.valid_after) AS valid_after,
            LEAST(a.valid_to, es.valid_to, lu.valid_to) AS valid_to
           FROM activity a
             JOIN establishment es ON a.establishment_id = es.id
             JOIN legal_unit lu ON es.legal_unit_id = lu.id
          WHERE es.legal_unit_id IS NOT NULL AND after_to_overlaps(a.valid_after, a.valid_to, es.valid_after, es.valid_to) AND after_to_overlaps(a.valid_after, a.valid_to, lu.valid_after, lu.valid_to)
        ), lu_stat_establishment AS (
         SELECT 'legal_unit'::statistical_unit_type AS unit_type,
            es.legal_unit_id AS unit_id,
            GREATEST(sfu.valid_after, es.valid_after, lu.valid_after) AS valid_after,
            LEAST(sfu.valid_to, es.valid_to, lu.valid_to) AS valid_to
           FROM stat_for_unit sfu
             JOIN establishment es ON sfu.establishment_id = es.id
             JOIN legal_unit lu ON es.legal_unit_id = lu.id
          WHERE es.legal_unit_id IS NOT NULL AND after_to_overlaps(sfu.valid_after, sfu.valid_to, es.valid_after, es.valid_to) AND after_to_overlaps(sfu.valid_after, sfu.valid_to, lu.valid_after, lu.valid_to)
        ), lu_combined AS (
         SELECT lu_base.unit_type,
            lu_base.unit_id,
            lu_base.valid_after,
            lu_base.valid_to
           FROM lu_base
        UNION ALL
         SELECT lu_activity.unit_type,
            lu_activity.unit_id,
            lu_activity.valid_after,
            lu_activity.valid_to
           FROM lu_activity
        UNION ALL
         SELECT lu_location.unit_type,
            lu_location.unit_id,
            lu_location.valid_after,
            lu_location.valid_to
           FROM lu_location
        UNION ALL
         SELECT lu_stat.unit_type,
            lu_stat.unit_id,
            lu_stat.valid_after,
            lu_stat.valid_to
           FROM lu_stat
        UNION ALL
         SELECT lu_establishment.unit_type,
            lu_establishment.unit_id,
            lu_establishment.valid_after,
            lu_establishment.valid_to
           FROM lu_establishment
        UNION ALL
         SELECT lu_activity_establishment.unit_type,
            lu_activity_establishment.unit_id,
            lu_activity_establishment.valid_after,
            lu_activity_establishment.valid_to
           FROM lu_activity_establishment
        UNION ALL
         SELECT lu_stat_establishment.unit_type,
            lu_stat_establishment.unit_id,
            lu_stat_establishment.valid_after,
            lu_stat_establishment.valid_to
           FROM lu_stat_establishment
        ), en_legal_unit AS (
         SELECT 'enterprise'::statistical_unit_type AS unit_type,
            legal_unit.enterprise_id AS unit_id,
            legal_unit.valid_after,
            legal_unit.valid_to
           FROM legal_unit
          WHERE legal_unit.enterprise_id IS NOT NULL
        ), en_establishment AS (
         SELECT 'enterprise'::statistical_unit_type AS unit_type,
            es.enterprise_id AS unit_id,
            es.valid_after,
            es.valid_to
           FROM establishment es
          WHERE es.enterprise_id IS NOT NULL
        ), en_establishment_legal_unit AS (
         SELECT 'enterprise'::statistical_unit_type AS unit_type,
            lu.enterprise_id AS unit_id,
            GREATEST(es.valid_after, lu.valid_after) AS valid_after,
            LEAST(es.valid_to, lu.valid_to) AS valid_to
           FROM establishment es
             JOIN legal_unit lu ON es.legal_unit_id = lu.id
          WHERE lu.enterprise_id IS NOT NULL AND after_to_overlaps(es.valid_after, es.valid_to, lu.valid_after, lu.valid_to)
        ), en_activity_establishment AS (
         SELECT 'enterprise'::statistical_unit_type AS unit_type,
            es.enterprise_id AS unit_id,
            GREATEST(a.valid_after, es.valid_after) AS valid_after,
            LEAST(a.valid_to, es.valid_to) AS valid_to
           FROM activity a
             JOIN establishment es ON a.establishment_id = es.id
          WHERE es.enterprise_id IS NOT NULL AND after_to_overlaps(a.valid_after, a.valid_to, es.valid_after, es.valid_to)
        ), en_activity_legal_unit AS (
         SELECT 'enterprise'::statistical_unit_type AS unit_type,
            lu.enterprise_id AS unit_id,
            GREATEST(a.valid_after, lu.valid_after) AS valid_after,
            LEAST(a.valid_to, lu.valid_to) AS valid_to
           FROM activity a
             JOIN legal_unit lu ON a.legal_unit_id = lu.id
          WHERE lu.enterprise_id IS NOT NULL AND after_to_overlaps(a.valid_after, a.valid_to, lu.valid_after, lu.valid_to)
        ), en_activity_establishment_legal_unit AS (
         SELECT 'enterprise'::statistical_unit_type AS unit_type,
            lu.enterprise_id AS unit_id,
            GREATEST(a.valid_after, es.valid_after, lu.valid_after) AS valid_after,
            LEAST(a.valid_to, es.valid_to, lu.valid_to) AS valid_to
           FROM activity a
             JOIN establishment es ON a.establishment_id = es.id
             JOIN legal_unit lu ON es.legal_unit_id = lu.id
          WHERE lu.enterprise_id IS NOT NULL AND after_to_overlaps(a.valid_after, a.valid_to, es.valid_after, es.valid_to) AND after_to_overlaps(a.valid_after, a.valid_to, lu.valid_after, lu.valid_to)
        ), en_location_establishment AS (
         SELECT 'enterprise'::statistical_unit_type AS unit_type,
            es.enterprise_id AS unit_id,
            GREATEST(l.valid_after, es.valid_after) AS valid_after,
            LEAST(l.valid_to, es.valid_to) AS valid_to
           FROM location l
             JOIN establishment es ON l.establishment_id = es.id
          WHERE es.enterprise_id IS NOT NULL AND after_to_overlaps(l.valid_after, l.valid_to, es.valid_after, es.valid_to)
        ), en_location_legal_unit AS (
         SELECT 'enterprise'::statistical_unit_type AS unit_type,
            lu.enterprise_id AS unit_id,
            GREATEST(l.valid_after, lu.valid_after) AS valid_after,
            LEAST(l.valid_to, lu.valid_to) AS valid_to
           FROM location l
             JOIN legal_unit lu ON l.legal_unit_id = lu.id
          WHERE lu.enterprise_id IS NOT NULL AND lu.primary_for_enterprise AND after_to_overlaps(l.valid_after, l.valid_to, lu.valid_after, lu.valid_to)
        ), en_stat_establishment AS (
         SELECT 'enterprise'::statistical_unit_type AS unit_type,
            es.enterprise_id AS unit_id,
            GREATEST(sfu.valid_after, es.valid_after) AS valid_after,
            LEAST(sfu.valid_to, es.valid_to) AS valid_to
           FROM stat_for_unit sfu
             JOIN establishment es ON sfu.establishment_id = es.id
          WHERE es.enterprise_id IS NOT NULL AND after_to_overlaps(sfu.valid_after, sfu.valid_to, es.valid_after, es.valid_to)
        ), en_stat_legal_unit AS (
         SELECT 'enterprise'::statistical_unit_type AS unit_type,
            lu.enterprise_id AS unit_id,
            GREATEST(sfu.valid_after, lu.valid_after) AS valid_after,
            LEAST(sfu.valid_to, lu.valid_to) AS valid_to
           FROM stat_for_unit sfu
             JOIN legal_unit lu ON sfu.legal_unit_id = lu.id
          WHERE lu.enterprise_id IS NOT NULL AND after_to_overlaps(sfu.valid_after, sfu.valid_to, lu.valid_after, lu.valid_to)
        ), en_stat_establishment_legal_unit AS (
         SELECT 'enterprise'::statistical_unit_type AS unit_type,
            lu.enterprise_id AS unit_id,
            GREATEST(sfu.valid_after, es.valid_after, lu.valid_after) AS valid_after,
            LEAST(sfu.valid_to, es.valid_to, lu.valid_to) AS valid_to
           FROM stat_for_unit sfu
             JOIN establishment es ON sfu.establishment_id = es.id
             JOIN legal_unit lu ON es.legal_unit_id = lu.id
          WHERE lu.enterprise_id IS NOT NULL AND after_to_overlaps(sfu.valid_after, sfu.valid_to, es.valid_after, es.valid_to) AND after_to_overlaps(sfu.valid_after, sfu.valid_to, lu.valid_after, lu.valid_to)
        ), en_combined AS (
         SELECT en_legal_unit.unit_type,
            en_legal_unit.unit_id,
            en_legal_unit.valid_after,
            en_legal_unit.valid_to
           FROM en_legal_unit
        UNION ALL
         SELECT en_establishment.unit_type,
            en_establishment.unit_id,
            en_establishment.valid_after,
            en_establishment.valid_to
           FROM en_establishment
        UNION ALL
         SELECT en_establishment_legal_unit.unit_type,
            en_establishment_legal_unit.unit_id,
            en_establishment_legal_unit.valid_after,
            en_establishment_legal_unit.valid_to
           FROM en_establishment_legal_unit
        UNION ALL
         SELECT en_activity_establishment.unit_type,
            en_activity_establishment.unit_id,
            en_activity_establishment.valid_after,
            en_activity_establishment.valid_to
           FROM en_activity_establishment
        UNION ALL
         SELECT en_activity_legal_unit.unit_type,
            en_activity_legal_unit.unit_id,
            en_activity_legal_unit.valid_after,
            en_activity_legal_unit.valid_to
           FROM en_activity_legal_unit
        UNION ALL
         SELECT en_activity_establishment_legal_unit.unit_type,
            en_activity_establishment_legal_unit.unit_id,
            en_activity_establishment_legal_unit.valid_after,
            en_activity_establishment_legal_unit.valid_to
           FROM en_activity_establishment_legal_unit
        UNION ALL
         SELECT en_location_establishment.unit_type,
            en_location_establishment.unit_id,
            en_location_establishment.valid_after,
            en_location_establishment.valid_to
           FROM en_location_establishment
        UNION ALL
         SELECT en_location_legal_unit.unit_type,
            en_location_legal_unit.unit_id,
            en_location_legal_unit.valid_after,
            en_location_legal_unit.valid_to
           FROM en_location_legal_unit
        UNION ALL
         SELECT en_stat_establishment.unit_type,
            en_stat_establishment.unit_id,
            en_stat_establishment.valid_after,
            en_stat_establishment.valid_to
           FROM en_stat_establishment
        UNION ALL
         SELECT en_stat_legal_unit.unit_type,
            en_stat_legal_unit.unit_id,
            en_stat_legal_unit.valid_after,
            en_stat_legal_unit.valid_to
           FROM en_stat_legal_unit
        UNION ALL
         SELECT en_stat_establishment_legal_unit.unit_type,
            en_stat_establishment_legal_unit.unit_id,
            en_stat_establishment_legal_unit.valid_after,
            en_stat_establishment_legal_unit.valid_to
           FROM en_stat_establishment_legal_unit
        ), all_combined AS (
         SELECT es_combined.unit_type,
            es_combined.unit_id,
            es_combined.valid_after,
            es_combined.valid_to
           FROM es_combined
        UNION ALL
         SELECT lu_combined.unit_type,
            lu_combined.unit_id,
            lu_combined.valid_after,
            lu_combined.valid_to
           FROM lu_combined
        UNION ALL
         SELECT en_combined.unit_type,
            en_combined.unit_id,
            en_combined.valid_after,
            en_combined.valid_to
           FROM en_combined
        ), timepoint AS (
         SELECT all_combined.unit_type,
            all_combined.unit_id,
            all_combined.valid_after AS timepoint
           FROM all_combined
        UNION
         SELECT all_combined.unit_type,
            all_combined.unit_id,
            all_combined.valid_to AS timepoint
           FROM all_combined
        )
 SELECT DISTINCT unit_type,
    unit_id,
    timepoint
   FROM timepoint
  ORDER BY unit_type, unit_id, timepoint;

```
