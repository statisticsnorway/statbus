```sql
CREATE OR REPLACE FUNCTION public.websearch_to_wildcard_tsquery(query text)
 RETURNS tsquery
 LANGUAGE plpgsql
AS $function$
    DECLARE
        query_splits text[];
        split text;
        new_query text := '';
    BEGIN
        SELECT regexp_split_to_array(d::text, '\s* \s*') INTO query_splits FROM pg_catalog.websearch_to_tsquery('simple', query) d;
        FOREACH split IN ARRAY query_splits LOOP
            CASE WHEN split = '|' OR split = '&' OR split = '!' OR split = '<->' OR split = '!('
                THEN new_query := new_query || split || ' ';
            ELSE new_query := new_query || split || ':* ';
            END CASE;
        END LOOP;
        RETURN to_tsquery('simple', new_query);
    END;
$function$
```
