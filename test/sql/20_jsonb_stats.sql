DROP AGGREGATE public.jsonb_stats_agg(jsonb);
DROP FUNCTION public.jsonb_stats(jsonb,jsonb);
DROP FUNCTION public.jsonb_stats_round(jsonb);

/*
 * ======================================================================================
 * Function: jsonb_stats
 * Purpose: Aggregates and summarizes JSONB data by computing statistics for various data types.
 * 
 * This function accumulates statistics for JSONB objects, including numeric, string, boolean,
 * array, and nested object types. The function is used as the state transition function in
 * the jsonb_stats_agg aggregate, summarizing data across multiple rows.
 * 
 * Summary by Type:
 * 1. Numeric:
 *    - Computes the sum, count, mean, maximum, minimum, and variance (via sum_sq_diff).
 *    - Example:
 *      Input: {"a": 10}, {"a": 5}, {"a": 20}
 *      Output: {"a": {"sum": 35, "count": 3, "mean": 11.67, "max": 20, "min": 5, "variance": 58.33}}
 *    - Calculation References:
 *      - Mean update: https://en.wikipedia.org/wiki/Algorithms_for_calculating_variance#Online_algorithm
 *      - Variance update: Welford's method
 * 
 * 2. String:
 *    - Counts occurrences of each distinct string value.
 *    - Example:
 *      Input: {"b": "apple"}, {"b": "banana"}, {"b": "apple"}
 *      Output: {"b": {"counts": {"apple": 2, "banana": 1}}}
 * 
 * 3. Boolean:
 *    - Counts the occurrences of true and false values.
 *    - Example:
 *      Input: {"c": true}, {"c": false}, {"c": true}
 *      Output: {"c": {"counts": {"true": 2, "false": 1}}}
 * 
 * 4. Array:
 *    - Aggregates the count of each unique value item across all arrays.
 *    - Example:
 *      Input: {"d": [1, 2]}, {"d": [2, 3]}, {"d": [3, 4]}
 *      Output: {"d": {"counts": {"1": 1, "2": 2, "3": 2, "4": 1}}}
 *    - Note: An exception is raised if arrays contain mixed types.
 * 
 * 5. Object (Nested JSON):
 *    - Recursively aggregates nested JSON objects.
 *    - Example:
 *      Input: {"e": {"f": 1}}, {"e": {"f": 2}}, {"e": {"f": 3}}
 *      Output: {"e": {"f": {"sum": 6, "count": 3, "max": 3, "min": 1}}}
 * 
 * Note:
 * - The function raises an exception if it encounters a type mismatch for a key across different rows.
 * - Semantically, a single key will always have the same structure across different rows, as it is uniquely defined in a table.
 * - The function should be used in conjunction with the jsonb_stats_agg aggregate to process multiple rows.
 * ======================================================================================
 */

CREATE FUNCTION public.jsonb_stats(state jsonb, stats jsonb) RETURNS jsonb AS $$
DECLARE
    prev_stat_state jsonb;
    stat_key text;
    stat_value jsonb;
    stat_type text;
    prev_stat_type text;
    next_stat_state jsonb;
    state_type text;
    stats_type text;
    count integer;
    mean numeric;
    sum_sq_diff numeric;
    delta numeric;
BEGIN
    IF state IS NULL OR stats IS NULL THEN
        RAISE EXCEPTION 'Logic error: STRICT function should never be called with NULL';
    END IF;

    state_type := jsonb_typeof(state);
    IF state_type <> 'object' THEN
        RAISE EXCEPTION 'Type mismatch for state "%": % <> object', state, state_type;
    END IF;

    stats_type := jsonb_typeof(stats);
    IF stats_type <> 'object' THEN
        RAISE EXCEPTION 'Type mismatch for stats "%": % <> object', stats, stats_type;
    END IF;

    -- Update state with data from `value`
    FOR stat_key, stat_value IN SELECT * FROM jsonb_each(stats) LOOP
        stat_type := jsonb_typeof(stat_value);

        IF state ? stat_key THEN
            prev_stat_state := state->stat_key;
            prev_stat_type := prev_stat_state->>'type';
            IF stat_type <> prev_stat_type THEN
                RAISE EXCEPTION 'Type mismatch between values for key "%" was "%" became "%"', stat_key, prev_stat_type, stat_type;
            END IF;
            next_stat_state = jsonb_build_object('type', stat_type);

            CASE stat_type
                -- Handle numeric values with iterative mean and variance
                WHEN 'number' THEN
                    count := (prev_stat_state->'count')::integer + 1;
                    delta := stat_value::numeric - (prev_stat_state->'mean')::numeric;
                    mean := (prev_stat_state->'mean')::numeric + delta / count;
                    sum_sq_diff := (prev_stat_state->'sum_sq_diff')::numeric + delta * (stat_value::numeric - mean);

                    next_stat_state :=  next_stat_state ||
                        jsonb_build_object(
                            'sum', (prev_stat_state->'sum')::numeric + stat_value::numeric,
                            'count', count,
                            'mean', mean,
                            'min', LEAST((prev_stat_state->'min')::numeric, stat_value::numeric),
                            'max', GREATEST((prev_stat_state->'max')::numeric, stat_value::numeric),
                            'sum_sq_diff', sum_sq_diff
                        );

                -- Handle string values
                WHEN 'string' THEN
                    next_stat_state :=  next_stat_state ||
                        jsonb_build_object(
                            'counts',
                            -- The previous dictionary with count for each key.
                            (prev_stat_state->'counts')
                            -- Appending to it
                            ||
                            -- The updated count for this particular key.
                            jsonb_build_object(
                                -- Notice that `->>0` extracts the non quoted string,
                                -- otherwise the key would be double quoted.
                                stat_value->>0,
                                COALESCE((prev_stat_state->'counts'->(stat_value->>0))::integer, 0) + 1
                            )
                        );
                -- Handle boolean types
                WHEN 'boolean' THEN
                    next_stat_state :=  next_stat_state ||
                        jsonb_build_object(
                            'counts', jsonb_build_object(
                                'true', COALESCE((prev_stat_state->'counts'->'true')::integer, 0) + (stat_value::boolean)::integer,
                                'false', COALESCE((prev_stat_state->'counts'->'false')::integer, 0) + (NOT stat_value::boolean)::integer
                            )
                        );

                -- Handle array types
                WHEN 'array' THEN
                    DECLARE
                        element text;
                        element_count integer;
                    BEGIN
                        -- Start with the previous state, to preserve previous counts.
                        next_stat_state := prev_stat_state;

                        FOR element IN SELECT jsonb_array_elements_text(stat_value) LOOP
                            -- Retrieve the old count for this element, defaulting to 0 if not present
                            count := COALESCE((next_stat_state->'counts'->element)::integer, 0) + 1;

                            -- Update the next state with the incremented count
                            next_stat_state := jsonb_set(
                                next_stat_state,
                                ARRAY['counts',element],
                                to_jsonb(count)
                            );
                        END LOOP;
                    END;

                -- Handle object (nested JSON)
                WHEN 'object' THEN
                    next_stat_state := jsonb_stats(prev_stat_state, stat_value);
                ELSE
                    RAISE EXCEPTION 'Unsupported type "%" for %', stat_type, stat_value;
            END CASE;
        ELSE
            -- Initialize new entry in state
            next_stat_state = jsonb_build_object('type', stat_type);
            CASE stat_type
                WHEN 'number' THEN
                    next_stat_state := next_stat_state ||
                        jsonb_build_object(
                            'sum', stat_value::numeric,
                            'count', 1,
                            'mean', stat_value::numeric,
                            'min', stat_value::numeric,
                            'max', stat_value::numeric,
                            'sum_sq_diff', 0
                        );
                WHEN 'string' THEN
                    next_stat_state :=  next_stat_state ||
                        jsonb_build_object(
                            -- Notice that `->>0` extracts the non quoted string,
                            -- otherwise the key would be double quoted.
                            'counts', jsonb_build_object(stat_value->>0, 1)
                        );
                WHEN 'boolean' THEN
                    next_stat_state :=  next_stat_state ||
                            jsonb_build_object(
                            'counts', jsonb_build_object(
                                'true', (stat_value::boolean)::integer,
                                'false', (NOT stat_value::boolean)::integer
                            )
                        );
                WHEN 'array' THEN
                    -- Initialize array with counts of each unique value
                    next_stat_state :=  next_stat_state ||
                        jsonb_build_object(
                            'counts',
                            (
                            SELECT jsonb_object_agg(element,1)
                            FROM jsonb_array_elements_text(stat_value) AS element
                            )
                        );
                WHEN 'object' THEN
                    next_stat_state := jsonb_stats(next_stat_state, stat_value);
                ELSE
                    RAISE EXCEPTION 'Unsupported type "%" for %', stat_type, stat_value;
            END CASE;
        END IF;

        state := state || jsonb_build_object(stat_key, next_stat_state);
    END LOOP;

    RETURN state;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;


CREATE FUNCTION public.jsonb_stats_round(state jsonb) RETURNS jsonb AS $$
DECLARE
    key text;
    val jsonb;
    rounded_val jsonb;
    result jsonb := '{}';
    type_val text;
BEGIN
    -- Iterate through the keys in the state JSONB object
    FOR key, val IN SELECT * FROM jsonb_each(state) LOOP
        type_val := jsonb_typeof(val);
        CASE type_val
            WHEN 'object' THEN
                -- Further iterate if the value is an object
                IF val ? 'mean' AND val ? 'sum_sq_diff' THEN
                    -- Numeric statistics rounding for relevant
                    rounded_val :=
                        val - 'mean' - 'sum_sq_diff' ||
                        jsonb_build_object(
                            'mean', round((val->>'mean')::numeric, 2),
                            'sum_sq_diff', round((val->>'sum_sq_diff')::numeric, 2)
                        );
                ELSE
                    -- For nested objects that are not numeric statistics, recursively call jsonb_stats_round
                    rounded_val := jsonb_stats_round(val);
                END IF;
            ELSE
                -- Other types are kept as is
                rounded_val := val;
        END CASE;

        -- Construct the result JSONB object
        result := result || jsonb_build_object(key, rounded_val);
    END LOOP;

    RETURN result;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;


-- Create aggregate jsonb_stats_agg
CREATE AGGREGATE public.jsonb_stats_agg(jsonb) (
    sfunc = public.jsonb_stats,
    stype = jsonb,
    initcond = '{}',
    finalfunc = public.jsonb_stats_round
);

-- Test cases
-- Show results suitable for jsonb_pretty for easy diffing.
\t
\a

-- Test 1: No data
-- Base case for the aggretation function when there is no data.
SELECT jsonb_pretty(jsonb_stats_agg(NULL));
-- Expected output: {}

-- Test 2: Each supported data type base case
SELECT jsonb_pretty(jsonb_stats_agg('{"num": 1, "str": "a", "bool": true}'::jsonb));
-- Expected output: {"num": {"max": 1, "min": 1, "sum": 1, "mean": 1, "count": 1, "sum_sq_diff": 0}, "str": {"counts": {"a": 1}}, "bool": {"counts": {"true": 1, "false": 0}}}

-- Test 3: Each supported data type iterative case
SELECT jsonb_pretty(jsonb_stats_agg(value))
FROM (
    VALUES ('{"num": 1, "str": "a", "bool": true}'::jsonb)
         , ('{"num": 2, "str": "a", "bool": false}'::jsonb)
         , ('{"num": 3, "str": "b", "bool": true}'::jsonb)
) AS test(value);
-- Expected output: 

-- Test 4: Algorithms for many data points.
SELECT jsonb_pretty(jsonb_stats_agg(value))
FROM (
    VALUES ('{"num": 0, "str": "a", "bool": true}'::jsonb)
         , ('{"num": 100, "str": "b", "bool": false}'::jsonb)
         , ('{"num": 200, "str": "b", "bool": true}'::jsonb)
         , ('{"num": 300, "str": "c", "bool": true}'::jsonb)
         , ('{"num": 400, "str": "c", "bool": false}'::jsonb)
         , ('{"num": 500, "str": "c", "bool": true}'::jsonb)
         , ('{"num": 600, "str": "d", "bool": true}'::jsonb)
         , ('{"num": 700, "str": "d", "bool": true}'::jsonb)
         , ('{"num": 800, "str": "d", "bool": false}'::jsonb)
         , ('{"num": 900, "str": "d", "bool": false}'::jsonb)
) AS test(value);
-- Expected output: 

-- Test 5: Type mismatch
SELECT jsonb_pretty(jsonb_stats_agg(value))
FROM (
    VALUES ('{"a": 1}'::jsonb)
         , ('{"a": "1"}'::jsonb)
) AS test(value);
-- Expected output: ERROR: Type mismatch for key "a": number vs string

-- Test 6: Array of numeric values
SELECT jsonb_pretty(jsonb_stats_agg(value))
FROM (
    VALUES ('{"arr": [1, 2]}'::jsonb)
         , ('{"arr": [2, 3]}'::jsonb)
) AS test(value);
-- Expected output: {"arr": {"counts": {"1": 1, "2": 2, "3": 1}}}

-- Test 7: Array of string values
SELECT jsonb_pretty(jsonb_stats_agg(value))
FROM (
    VALUES ('{"arr": ["a", "b"]}'::jsonb)
         , ('{"arr": ["b", "c"]}'::jsonb)
) AS test(value);
-- Expected output: {"arr": {"counts": {"a": 1, "b": 2, "c": 1}}}

-- Test 8: Array with type mismatch, each occurence is just counted.
SELECT jsonb_pretty(jsonb_stats_agg(value))
FROM (
    VALUES ('{"arr": [1, 2, "a"]}'::jsonb)
         , ('{"arr": ["a", "b", "c"]}'::jsonb)
) AS test(value);
-- Expected output: {"arr": {"counts": {"a": 1, "b": 2, "c": 1}}}

