BEGIN;

-- Ref https://stackoverflow.com/a/76356252/1023558
CREATE FUNCTION public.websearch_to_wildcard_tsquery(query text)
RETURNS tsquery AS $$
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
$$ LANGUAGE plpgsql;
--

END;
