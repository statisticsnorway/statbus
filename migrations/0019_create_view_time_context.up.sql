\echo public.time_context_type
CREATE TYPE public.time_context_type AS ENUM (
    'relative_period',
    'tag'
);

\echo public.time_context
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
  ,      name_when_query                       AS name_when_query
  ,      name_when_input                       AS name_when_input
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
  ,      't:'||path::VARCHAR                             AS ident
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
    AND context_valid_from IS NOT NULL
    AND context_valid_to   IS NOT NULL
    AND context_valid_on   IS NOT NULL
)
SELECT *
FROM combined_data
ORDER BY type, code, path;
