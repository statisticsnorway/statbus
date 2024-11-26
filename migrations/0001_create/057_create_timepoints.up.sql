BEGIN;

\echo public.timepoints
CREATE VIEW public.timepoints AS
    WITH es AS (
        -- establishment
        SELECT 'establishment'::public.statistical_unit_type AS unit_type
             , id AS unit_id
             , valid_after
             , valid_to
         FROM public.establishment
        UNION
        -- activity -> establishment
        SELECT 'establishment'::public.statistical_unit_type AS unit_type
             , a.establishment_id AS unit_id
             , a.valid_after
             , a.valid_to
         FROM public.activity AS a
         INNER JOIN public.establishment AS es
            ON a.establishment_id = es.id
           AND daterange(a.valid_after, a.valid_to, '(]')
               <@ daterange(es.valid_after, es.valid_to, '(]')
         WHERE a.establishment_id IS NOT NULL
        UNION
        -- location -> establishment
        SELECT 'establishment'::public.statistical_unit_type AS unit_type
             , l.establishment_id AS unit_id
             , l.valid_after
             , l.valid_to
         FROM public.location AS l
         INNER JOIN public.establishment AS es
            ON l.establishment_id = es.id
           AND daterange(l.valid_after, l.valid_to, '(]')
               <@ daterange(es.valid_after, es.valid_to, '(]')
         WHERE l.establishment_id IS NOT NULL
        UNION
        -- stat_for_unit -> establishment
        SELECT 'establishment'::public.statistical_unit_type AS unit_type
             , sfu.establishment_id AS unit_id
             , sfu.valid_after
             , sfu.valid_to
         FROM public.stat_for_unit AS sfu
         INNER JOIN public.establishment AS es
            ON sfu.establishment_id = es.id
           AND daterange(sfu.valid_after, sfu.valid_to, '(]')
               <@ daterange(es.valid_after, es.valid_to, '(]')
         WHERE sfu.establishment_id IS NOT NULL
    ), lu AS (
        -- legal_unit
        SELECT 'legal_unit'::public.statistical_unit_type AS unit_type
             , id AS unit_id
             , valid_after
             , valid_to
         FROM public.legal_unit
        UNION
        -- activity -> legal_unit
        SELECT 'legal_unit'::public.statistical_unit_type AS unit_type
             , a.legal_unit_id AS unit_id
             , a.valid_after
             , a.valid_to
         FROM public.activity AS a
         INNER JOIN public.legal_unit AS lu
            ON a.legal_unit_id = lu.id
           AND daterange(a.valid_after, a.valid_to, '(]')
               <@ daterange(lu.valid_after, lu.valid_to, '(]')
         WHERE a.legal_unit_id IS NOT NULL
        UNION
        -- location -> legal_unit
        SELECT 'legal_unit'::public.statistical_unit_type AS unit_type
             , l.legal_unit_id AS unit_id
             , l.valid_after
             , l.valid_to
         FROM public.location AS l
         INNER JOIN public.legal_unit AS lu
            ON l.legal_unit_id = lu.id
           AND daterange(l.valid_after, l.valid_to, '(]')
               <@ daterange(lu.valid_after, lu.valid_to, '(]')
         WHERE l.legal_unit_id IS NOT NULL
        UNION
        -- stat_for_unit -> legal_unit
        SELECT 'legal_unit'::public.statistical_unit_type AS unit_type
             , sfu.legal_unit_id AS unit_id
             , sfu.valid_after
             , sfu.valid_to
         FROM public.stat_for_unit AS sfu
         INNER JOIN public.legal_unit AS lu
            ON sfu.legal_unit_id = lu.id
           AND daterange(sfu.valid_after, sfu.valid_to, '(]')
               <@ daterange(lu.valid_after, lu.valid_to, '(]')
         WHERE sfu.legal_unit_id IS NOT NULL
        UNION
        -- establishment -> legal_unit
        SELECT 'legal_unit'::public.statistical_unit_type AS unit_type
             , lu.id AS unit_id
             , es.valid_after
             , es.valid_to
         FROM public.establishment AS es
         INNER JOIN public.legal_unit AS lu
            ON es.legal_unit_id = lu.id
           AND daterange(es.valid_after, es.valid_to, '(]')
               <@ daterange(lu.valid_after, lu.valid_to, '(]')
         WHERE es.legal_unit_id IS NOT NULL
        UNION
        -- activity -> establishment -> legal_unit
        SELECT 'legal_unit'::public.statistical_unit_type AS unit_type
             , es.legal_unit_id AS unit_id
             , a.valid_after
             , a.valid_to
         FROM public.activity AS a
         INNER JOIN public.establishment AS es
            ON a.establishment_id = es.id
           AND daterange(a.valid_after, a.valid_to, '(]')
               <@ daterange(es.valid_after, es.valid_to, '(]')
         INNER JOIN public.legal_unit AS lu
            ON es.legal_unit_id = lu.id
           AND daterange(a.valid_after, a.valid_to, '(]')
               <@ daterange(lu.valid_after, lu.valid_to, '(]')
         WHERE es.legal_unit_id IS NOT NULL
        UNION
        -- stat_for_unit -> establishment -> legal_unit
        SELECT 'legal_unit'::public.statistical_unit_type AS unit_type
             , lu.id AS unit_id
             , sfu.valid_after
             , sfu.valid_to
         FROM public.stat_for_unit AS sfu
         INNER JOIN public.establishment AS es
            ON sfu.establishment_id = es.id
           AND daterange(sfu.valid_after, sfu.valid_to, '(]')
               <@ daterange(es.valid_after, es.valid_to, '(]')
         INNER JOIN public.legal_unit AS lu
            ON es.legal_unit_id = lu.id
           AND daterange(sfu.valid_after, sfu.valid_to, '(]')
               <@ daterange(lu.valid_after, lu.valid_to, '(]')
         WHERE es.legal_unit_id IS NOT NULL
    ), en AS (
        -- legal_unit -> enterprise
        SELECT 'enterprise'::public.statistical_unit_type AS unit_type
             , enterprise_id AS unit_id
             , valid_after
             , valid_to
         FROM public.legal_unit
        UNION
        -- establishment -> enterprise
        SELECT 'enterprise'::public.statistical_unit_type AS unit_type
             , es.enterprise_id AS unit_id
             , es.valid_after
             , es.valid_to
         FROM public.establishment AS es
         WHERE es.enterprise_id IS NOT NULL
        UNION
        -- establishment -> legal_unit -> enterprise
        SELECT 'enterprise'::public.statistical_unit_type AS unit_type
             , lu.enterprise_id AS unit_id
             , es.valid_after
             , es.valid_to
         FROM public.establishment AS es
         INNER JOIN public.legal_unit AS lu
            ON es.legal_unit_id = lu.id
           AND daterange(es.valid_after, es.valid_to, '(]')
               <@ daterange(lu.valid_after, lu.valid_to, '(]')
         WHERE lu.enterprise_id IS NOT NULL
        UNION
        -- activity -> establishment -> enterprise
        SELECT 'enterprise'::public.statistical_unit_type AS unit_type
             , es.enterprise_id AS unit_id
             , a.valid_after
             , a.valid_to
         FROM public.activity AS a
         INNER JOIN public.establishment AS es
            ON a.establishment_id = es.id
           AND daterange(a.valid_after, a.valid_to, '(]')
               <@ daterange(es.valid_after, es.valid_to, '(]')
         WHERE es.enterprise_id IS NOT NULL
        UNION
        -- activity -> legal_unit -> enterprise
        SELECT 'enterprise'::public.statistical_unit_type AS unit_type
             , lu.enterprise_id AS unit_id
             , a.valid_after
             , a.valid_to
         FROM public.activity AS a
         INNER JOIN public.legal_unit AS lu
            ON a.legal_unit_id = lu.id
           AND daterange(a.valid_after, a.valid_to, '(]')
               <@ daterange(lu.valid_after, lu.valid_to, '(]')
         WHERE lu.enterprise_id IS NOT NULL
        UNION
        -- activity -> establishment -> legal_unit -> enterprise
        SELECT 'enterprise'::public.statistical_unit_type AS unit_type
             , lu.enterprise_id AS unit_id
             , a.valid_after
             , a.valid_to
         FROM public.activity AS a
         INNER JOIN public.establishment AS es
            ON a.establishment_id = es.id
           AND daterange(a.valid_after, a.valid_to, '(]')
               <@ daterange(es.valid_after, es.valid_to, '(]')
         INNER JOIN public.legal_unit AS lu
            ON es.legal_unit_id = lu.id
           AND daterange(a.valid_after, a.valid_to, '(]')
               <@ daterange(lu.valid_after, lu.valid_to, '(]')
         WHERE lu.enterprise_id IS NOT NULL
        UNION
        -- location -> establishment -> enterprise
        SELECT 'enterprise'::public.statistical_unit_type AS unit_type
             , es.enterprise_id AS unit_id
             , l.valid_after
             , l.valid_to
         FROM public.location AS l
         INNER JOIN public.establishment AS es
            ON l.establishment_id = es.id
           AND daterange(l.valid_after, l.valid_to, '(]')
               <@ daterange(es.valid_after, es.valid_to, '(]')
         WHERE es.enterprise_id IS NOT NULL
        UNION
        -- location -> legal_unit -> enterprise
        SELECT 'enterprise'::public.statistical_unit_type AS unit_type
             , lu.enterprise_id AS unit_id
             , l.valid_after
             , l.valid_to
         FROM public.location AS l
         INNER JOIN public.legal_unit AS lu
            ON l.legal_unit_id = lu.id
           AND daterange(l.valid_after, l.valid_to, '(]')
               <@ daterange(lu.valid_after, lu.valid_to, '(]')
         WHERE lu.enterprise_id IS NOT NULL
           AND lu.primary_for_enterprise
        UNION
        -- stat_for_unit -> establishment -> enterprise
        SELECT 'enterprise'::public.statistical_unit_type AS unit_type
             , es.enterprise_id AS unit_id
             , sfu.valid_after
             , sfu.valid_to
         FROM public.stat_for_unit AS sfu
         INNER JOIN public.establishment AS es
            ON sfu.establishment_id = es.id
           AND daterange(sfu.valid_after, sfu.valid_to, '(]')
               <@ daterange(es.valid_after, es.valid_to, '(]')
         WHERE es.enterprise_id IS NOT NULL
        UNION
        -- stat_for_unit -> legal_unit -> enterprise
        SELECT 'enterprise'::public.statistical_unit_type AS unit_type
             , lu.enterprise_id AS unit_id
             , sfu.valid_after
             , sfu.valid_to
         FROM public.stat_for_unit AS sfu
         INNER JOIN public.legal_unit AS lu
            ON sfu.legal_unit_id = lu.id
           AND daterange(sfu.valid_after, sfu.valid_to, '(]')
               <@ daterange(lu.valid_after, lu.valid_to, '(]')
         WHERE lu.enterprise_id IS NOT NULL
        UNION
        -- stat_for_unit -> establishment -> legal_unit -> enterprise
        SELECT 'enterprise'::public.statistical_unit_type AS unit_type
             , lu.enterprise_id AS unit_id
             , sfu.valid_after
             , sfu.valid_to
         FROM public.stat_for_unit AS sfu
         INNER JOIN public.establishment AS es
            ON sfu.establishment_id = es.id
           AND daterange(sfu.valid_after, sfu.valid_to, '(]')
               <@ daterange(es.valid_after, es.valid_to, '(]')
         INNER JOIN public.legal_unit AS lu
            ON es.legal_unit_id = lu.id
           AND daterange(sfu.valid_after, sfu.valid_to, '(]')
               <@ daterange(lu.valid_after, lu.valid_to, '(]')
         WHERE lu.enterprise_id IS NOT NULL
    ), base AS (
          SELECT * FROM es
          UNION ALL
          SELECT * FROM lu
          UNION ALL
          SELECT * FROM en
    ), timepoint AS (
          SELECT unit_type, unit_id, valid_after AS timepoint FROM base
            UNION
          SELECT unit_type, unit_id, valid_to AS timepoint FROM base
    )
    SELECT *
    FROM timepoint
    ORDER BY unit_type, unit_id, timepoint
;

END;