```sql
                                    View "public.time_context"
     Column      |         Type          | Collation | Nullable | Default | Storage  | Description 
-----------------+-----------------------+-----------+----------+---------+----------+-------------
 type            | time_context_type     |           |          |         | plain    | 
 ident           | text                  |           |          |         | extended | 
 name_when_query | character varying     |           |          |         | extended | 
 name_when_input | character varying     |           |          |         | extended | 
 scope           | relative_period_scope |           |          |         | plain    | 
 valid_from      | date                  |           |          |         | plain    | 
 valid_to        | date                  |           |          |         | plain    | 
 valid_on        | date                  |           |          |         | plain    | 
 code            | relative_period_code  |           |          |         | plain    | 
 path            | ltree                 |           |          |         | extended | 
View definition:
 WITH combined_data AS (
         SELECT 'relative_period'::time_context_type AS type,
            'r_'::text || relative_period_with_time.code::character varying::text AS ident,
                CASE
                    WHEN relative_period_with_time.code = ANY (ARRAY['year_curr'::relative_period_code, 'year_curr_only'::relative_period_code]) THEN format('%s (%s)'::text, relative_period_with_time.name_when_query, EXTRACT(year FROM CURRENT_DATE))::character varying
                    WHEN relative_period_with_time.code = 'year_prev'::relative_period_code THEN format('%s (%s)'::text, relative_period_with_time.name_when_query, EXTRACT(year FROM CURRENT_DATE) - 1::numeric)::character varying
                    ELSE relative_period_with_time.name_when_query
                END AS name_when_query,
                CASE
                    WHEN relative_period_with_time.code = 'year_curr'::relative_period_code THEN format('%s (%s->)'::text, relative_period_with_time.name_when_input, EXTRACT(year FROM CURRENT_DATE))::character varying
                    WHEN relative_period_with_time.code = 'year_prev'::relative_period_code THEN format('%s (%s->)'::text, relative_period_with_time.name_when_input, EXTRACT(year FROM CURRENT_DATE) - 1::numeric)::character varying
                    WHEN relative_period_with_time.code = 'year_curr_only'::relative_period_code THEN format('%s (%s)'::text, relative_period_with_time.name_when_input, EXTRACT(year FROM CURRENT_DATE))::character varying
                    WHEN relative_period_with_time.code = 'year_prev_only'::relative_period_code THEN format('%s (%s)'::text, relative_period_with_time.name_when_input, EXTRACT(year FROM CURRENT_DATE) - 1::numeric)::character varying
                    ELSE relative_period_with_time.name_when_input
                END AS name_when_input,
            relative_period_with_time.scope,
            relative_period_with_time.valid_from,
            relative_period_with_time.valid_to,
            relative_period_with_time.valid_on,
            relative_period_with_time.code,
            NULL::ltree AS path
           FROM relative_period_with_time
          WHERE relative_period_with_time.active
        UNION ALL
         SELECT 'tag'::time_context_type AS type,
            't_'::text || tag.path::character varying::text AS ident,
            tag.description AS name_when_query,
            tag.description AS name_when_input,
            'input_and_query'::relative_period_scope AS scope,
            tag.context_valid_from AS valid_from,
            tag.context_valid_to AS valid_to,
            tag.context_valid_on AS valid_on,
            NULL::relative_period_code AS code,
            tag.path
           FROM tag
          WHERE tag.active AND tag.path IS NOT NULL AND tag.context_valid_from IS NOT NULL AND tag.context_valid_to IS NOT NULL AND tag.context_valid_on IS NOT NULL
        UNION ALL
         SELECT 'year'::time_context_type AS type,
            'y_'::text || ty.year::text AS ident,
            ty.year::text || ' (Data)'::text AS name_when_query,
            ty.year::text AS name_when_input,
            'input_and_query'::relative_period_scope AS scope,
            make_date(ty.year, 1, 1) AS valid_from,
            make_date(ty.year, 12, 31) AS valid_to,
            make_date(ty.year, 12, 31) AS valid_on,
            NULL::relative_period_code AS code,
            NULL::ltree AS path
           FROM timesegments_years ty
          WHERE ty.year <> ALL (ARRAY[EXTRACT(year FROM CURRENT_DATE)::integer, (EXTRACT(year FROM CURRENT_DATE) - 1::numeric)::integer])
        )
 SELECT type,
    ident,
    name_when_query,
    name_when_input,
    scope,
    valid_from,
    valid_to,
    valid_on,
    code,
    path
   FROM combined_data
  ORDER BY type, (
        CASE
            WHEN type = 'year'::time_context_type THEN EXTRACT(year FROM valid_from)
            ELSE NULL::numeric
        END) DESC, code, path;

```
