```sql
CREATE OR REPLACE FUNCTION public.remove_ephemeral_data_from_hierarchy(data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE STRICT
AS $function$
DECLARE
    result JSONB;
    key TEXT;
    value JSONB;
    new_value JSONB;
    ephemeral_keys TEXT[] := ARRAY['id', 'created_at', 'updated_at'];
    ephemeral_patterns TEXT[] := ARRAY['%_id','%_ids'];
BEGIN
    -- Handle both object and array types at the first level
    CASE jsonb_typeof(data)
        WHEN 'object' THEN
            result := '{}';  -- Initialize result as an empty object
            FOR key, value IN SELECT * FROM jsonb_each(data) LOOP
                IF key = ANY(ephemeral_keys) OR key LIKE ANY(ephemeral_patterns) THEN
                    CONTINUE;
                END IF;
                new_value := public.remove_ephemeral_data_from_hierarchy(value);
                result := jsonb_set(result, ARRAY[key], new_value, true);
            END LOOP;
        WHEN 'array' THEN
            -- No need to initialize result as '{}', let the SELECT INTO handle it
            SELECT COALESCE
                ( jsonb_agg(public.remove_ephemeral_data_from_hierarchy(elem))
                , '[]'::JSONB
            )
            INTO result
            FROM jsonb_array_elements(data) AS elem;
        ELSE
            -- If data is neither object nor array, return it as is
            result := data;
    END CASE;

    RETURN result;
END;
$function$
```
