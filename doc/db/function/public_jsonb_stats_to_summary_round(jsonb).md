```sql
CREATE OR REPLACE FUNCTION public.jsonb_stats_to_summary_round(state jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE PARALLEL SAFE STRICT COST 50
AS $function$
DECLARE
    key text;
    val jsonb;
    result jsonb := '{}';
    rounding_keys text[] := ARRAY['mean', 'sum_sq_diff', 'variance', 'stddev', 'coefficient_of_variation_pct'];
    sub_key text;
BEGIN
    -- Iterate through the keys in the state JSONB object
    FOR key, val IN SELECT * FROM jsonb_each(state) LOOP
        CASE jsonb_typeof(val)
            WHEN 'object' THEN
                -- Iterate over the rounding keys directly and apply rounding if key exists and value is numeric
                FOR sub_key IN SELECT unnest(rounding_keys) LOOP
                    IF val ? sub_key AND jsonb_typeof(val->sub_key) = 'number' THEN
                        val := val || jsonb_build_object(sub_key, round((val->sub_key)::numeric, 2));
                    END IF;
                END LOOP;

                -- Recursively process nested objects
                result := result || jsonb_build_object(key, public.jsonb_stats_to_summary_round(val));

            ELSE
                -- Non-object types are added to the result as is
                result := result || jsonb_build_object(key, val);
        END CASE;
    END LOOP;

    RETURN result;
END;
$function$
```
