```sql
CREATE OR REPLACE FUNCTION public.statistical_unit_refreshed_at()
 RETURNS TABLE(view_name text, modified_at timestamp without time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    path_separator char;
    materialized_view_schema text := 'public';
    materialized_view_names text[] := ARRAY
        [ 'statistical_unit'
        , 'activity_category_used'
        , 'region_used'
        , 'sector_used'
        , 'legal_form_used'
        , 'country_used'
        , 'statistical_unit_facet'
        , 'statistical_history'
        , 'statistical_history_facet'
        ];
BEGIN
    SELECT INTO path_separator
    CASE WHEN SUBSTR(setting, 1, 1) = '/' THEN '/' ELSE '\\' END
    FROM pg_settings WHERE name = 'data_directory';

    FOR view_name, modified_at IN
        SELECT
              c.relname AS view_name
            , (pg_stat_file(
                (SELECT setting FROM pg_settings WHERE name = 'data_directory')
                || path_separator || pg_relation_filepath(c.oid)
            )).modification AS modified_at
        FROM
            pg_class c
            JOIN pg_namespace ns ON c.relnamespace = ns.oid
        WHERE
            c.relkind = 'm'
            AND ns.nspname = materialized_view_schema
            AND c.relname = ANY(materialized_view_names)
    LOOP
        RETURN NEXT;
    END LOOP;
END;
$function$
```
