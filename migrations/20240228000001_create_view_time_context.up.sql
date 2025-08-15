BEGIN;

CREATE TYPE public.time_context_type AS ENUM (
    'relative_period',
    'tag',
    'year'
);

CREATE VIEW public.time_context
  ( type
  , ident
  , name_when_query
  , name_when_input
  , scope
  , valid_from
  , valid_to
  , valid_on
  , code         -- Exposing the code for ordering
  , path         -- Exposing the path for ordering
  ) AS
WITH combined_data AS (
  SELECT 'relative_period'::public.time_context_type AS type
  ,      'r_'||code::VARCHAR                   AS ident
  ,      CASE
           WHEN code IN ('year_curr', 'year_curr_only') THEN format('%s (%s)', name_when_query, EXTRACT(YEAR FROM current_date))
           WHEN code IN ('year_prev') THEN format('%s (%s)', name_when_query, EXTRACT(YEAR FROM current_date) - 1)
           ELSE name_when_query
         END                                   AS name_when_query
  ,      CASE
           WHEN code = 'year_curr' THEN format('%s (%s->)', name_when_input, EXTRACT(YEAR FROM current_date))
           WHEN code = 'year_prev' THEN format('%s (%s->)', name_when_input, EXTRACT(YEAR FROM current_date) - 1)
           WHEN code = 'year_curr_only' THEN format('%s (%s)', name_when_input, EXTRACT(YEAR FROM current_date))
           WHEN code = 'year_prev_only' THEN format('%s (%s)', name_when_input, EXTRACT(YEAR FROM current_date) - 1)
           ELSE name_when_input
         END                                   AS name_when_input
  ,      scope                                 AS scope
  ,      valid_from                            AS valid_from
  ,      valid_to                              AS valid_to
  ,      valid_on                              AS valid_on
  ,      code                                  AS code  -- Specific order column for relative_period
  ,      NULL::public.LTREE                    AS path  -- Null for path as not applicable here
  FROM public.relative_period_with_time
  WHERE active

  UNION ALL

  SELECT 'tag'::public.time_context_type                 AS type
  ,      't_' || path::VARCHAR                           AS ident
  ,      description                                     AS name_when_query
  ,      description                                     AS name_when_input
  ,      'input_and_query'::public.relative_period_scope AS scope
  ,      context_valid_from                              AS valid_from
  ,      context_valid_to                                AS valid_to
  ,      context_valid_on                                AS valid_on
  ,      NULL::public.relative_period_code               AS code  -- Null for code as not applicable here
  ,      path                                            AS path  -- Specific order column for tag
  FROM public.tag
  WHERE active
    AND path IS NOT NULL
    AND context_valid_from IS NOT NULL
    AND context_valid_to   IS NOT NULL
    AND context_valid_on   IS NOT NULL

  UNION ALL

  SELECT 'year'::public.time_context_type                  AS type
  ,      'y_' || ty.year::TEXT                             AS ident
  ,      ty.year::TEXT || ' (Data)'                        AS name_when_query
  ,      ty.year::TEXT                                     AS name_when_input
  ,      'input_and_query'::public.relative_period_scope   AS scope
  ,      make_date(ty.year, 1, 1)                          AS valid_from
  ,      make_date(ty.year, 12, 31)                        AS valid_to
  ,      make_date(ty.year, 12, 31)                        AS valid_on
  ,      NULL::public.relative_period_code                 AS code
  ,      NULL::public.LTREE                                AS path
  FROM public.timesegments_years ty
  WHERE ty.year NOT IN (EXTRACT(YEAR FROM current_date)::integer, (EXTRACT(YEAR FROM current_date) - 1)::integer)
)
SELECT *
FROM combined_data
ORDER BY
    type,
    CASE WHEN type = 'year' THEN EXTRACT(YEAR FROM valid_from) END DESC,
    code,
    path;

END;
