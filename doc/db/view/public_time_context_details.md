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
            relative_period_with_time.name_when_query,
            relative_period_with_time.name_when_input,
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
            't:'::text || tag.path::character varying::text AS ident,
            tag.description AS name_when_query,
            tag.description AS name_when_input,
            'input_and_query'::relative_period_scope AS scope,
            tag.context_valid_from AS valid_from,
            tag.context_valid_to AS valid_to,
            tag.context_valid_on AS valid_on,
            NULL::relative_period_code AS code,
            tag.path
           FROM tag
          WHERE tag.active AND tag.context_valid_from IS NOT NULL AND tag.context_valid_to IS NOT NULL AND tag.context_valid_on IS NOT NULL
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
  ORDER BY type, code, path;

```
