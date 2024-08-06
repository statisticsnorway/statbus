DROP AGGREGATE public.jsonb_stats_to_summary_agg(jsonb);
DROP FUNCTION public.jsonb_stats_to_summary(jsonb,jsonb);

DROP AGGREGATE public.jsonb_stats_summary_merge_agg(jsonb);
DROP FUNCTION public.jsonb_stats_summary_merge(jsonb,jsonb);

DROP FUNCTION public.jsonb_stats_to_summary_round(jsonb);

/*
 * ======================================================================================
 * Function: jsonb_stats_to_summary
 * Purpose: Aggregates and summarizes JSONB data by computing statistics for various data types.
 * 
 * This function accumulates statistics for JSONB objects, including numeric, string, boolean,
 * array, and nested object types. The function is used as the state transition function in
 * the jsonb_stats_to_summary_agg aggregate, summarizing data across multiple rows.
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
 * - The function should be used in conjunction with the jsonb_stats_to_summary_agg aggregate to process multiple rows.
 * ======================================================================================
 */

CREATE FUNCTION public.jsonb_stats_to_summary(state jsonb, stats jsonb) RETURNS jsonb AS $$
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
                            'sum_sq_diff', sum_sq_diff,
                            'variance', CASE WHEN count > 1 THEN sum_sq_diff / (count - 1) ELSE NULL END
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
                    next_stat_state := public.jsonb_stats_to_summary(prev_stat_state, stat_value);
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
                            'sum_sq_diff', 0,
                            'variance', 0
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
                    next_stat_state := public.jsonb_stats_to_summary(next_stat_state, stat_value);
                ELSE
                    RAISE EXCEPTION 'Unsupported type "%" for %', stat_type, stat_value;
            END CASE;
        END IF;

        state := state || jsonb_build_object(stat_key, next_stat_state);
    END LOOP;

    RETURN state;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;


CREATE FUNCTION public.jsonb_stats_to_summary_round(state jsonb) RETURNS jsonb AS $$
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
                IF val ? 'mean' OR val ? 'sum_sq_diff' OR val ? 'variance' THEN
                    -- Numeric statistics rounding for relevant
                    rounded_val :=
                        val - 'mean' - 'sum_sq_diff' - 'variance' ||
                        jsonb_build_object(
                            'mean', round((val->>'mean')::numeric, 2),
                            'sum_sq_diff', round((val->>'sum_sq_diff')::numeric, 2),
                            'variance', round((val->>'variance')::numeric, 2)
                        );
                ELSE
                    -- For nested objects that are not numeric statistics, recursively call jsonb_stats_to_summary_round
                    rounded_val := public.jsonb_stats_to_summary_round(val);
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


-- Create aggregate jsonb_stats_to_summary_agg
CREATE AGGREGATE public.jsonb_stats_to_summary_agg(jsonb) (
    sfunc = public.jsonb_stats_to_summary,
    stype = jsonb,
    initcond = '{}',
    finalfunc = public.jsonb_stats_to_summary_round
);


CREATE FUNCTION public.jsonb_stats_summary_merge(a jsonb, b jsonb) RETURNS jsonb AS $$
DECLARE
    key_a text;
    key_b text;
    val_a jsonb;
    val_b jsonb;
    merged_val jsonb;
    type_a text;
    type_b text;
    result jsonb := '{}';
BEGIN
    -- Ensure both a and b are objects
    IF jsonb_typeof(a) <> 'object' OR jsonb_typeof(b) <> 'object' THEN
        RAISE EXCEPTION 'Both arguments must be JSONB objects';
    END IF;

    -- Iterate over keys in both JSONB objects
    FOR key_a, val_a IN SELECT * FROM jsonb_each(a) LOOP
        IF b ? key_a THEN
            val_b := b->key_a;
            type_a := val_a->>'type';
            type_b := val_b->>'type';

            -- Ensure the types are the same for the same key
            IF type_a <> type_b THEN
                RAISE EXCEPTION 'Type mismatch for key "%": % vs %', key_a, type_a, type_b;
            END IF;

            -- Merge the values based on their type
            CASE type_a
                WHEN 'number' THEN
                    DECLARE
                       count_a integer := (val_a->'count')::integer;
                       count_b integer := (val_b->'count')::integer;
                       count integer := count_a + count_b;
                       mean_a numeric := (val_a->'mean')::numeric;
                       mean_b numeric := (val_b->'mean')::numeric;
                       mean numeric := (mean_a * count_a + mean_b * count_b) / count;
                       sum_sq_diff numeric := (val_a->'sum_sq_diff')::numeric + (val_b->'sum_sq_diff')::numeric + (mean_a - mean_b)^2 * count_a * count_b / count;
                       variance numeric := CASE WHEN count > 1 THEN sum_sq_diff / (count - 1) ELSE NULL END;
                    BEGIN
                        merged_val := jsonb_build_object(
                            'sum', (val_a->'sum')::numeric + (val_b->'sum')::numeric,
                            'count', count,
                            'mean', mean,
                            'min', LEAST((val_a->'min')::numeric, (val_b->'min')::numeric),
                            'max', GREATEST((val_a->'max')::numeric, (val_b->'max')::numeric),
                            'sum_sq_diff', sum_sq_diff,
                            'variance', variance
                        );
                    END;
                WHEN 'string' THEN
                    merged_val := jsonb_build_object(
                        'counts', (
                            SELECT jsonb_object_agg(key, value)
                            FROM (
                                SELECT key, SUM(value) AS value
                                FROM (
                                    SELECT key, value::integer FROM jsonb_each(val_a->'counts')
                                    UNION ALL
                                    SELECT key, value::integer FROM jsonb_each(val_b->'counts')
                                ) AS enumerated
                                GROUP BY key
                            ) AS merged_counts
                        )
                    );
                WHEN 'boolean' THEN
                    merged_val := jsonb_build_object(
                        'counts', jsonb_build_object(
                            'true', (val_a->'counts'->>'true')::integer + (val_b->'counts'->>'true')::integer,
                            'false', (val_a->'counts'->>'false')::integer + (val_b->'counts'->>'false')::integer
                        )
                    );
                WHEN 'array' THEN
                    merged_val := jsonb_build_object(
                        'counts', (
                            SELECT jsonb_object_agg(key, value)
                            FROM (
                                SELECT key, SUM(value) AS value
                                FROM (
                                    SELECT key, value::integer FROM jsonb_each(val_a->'counts')
                                    UNION ALL
                                    SELECT key, value::integer FROM jsonb_each(val_b->'counts')
                                ) AS enumerated
                                GROUP BY key
                            ) AS merged_counts
                        )
                    );
                WHEN 'object' THEN
                    merged_val := jsonb_stats_summary_merge(val_a, val_b);
                ELSE
                    RAISE EXCEPTION 'Unsupported type "%" for key "%"', type_a, key_a;
            END CASE;

            -- Add the merged value to the result
            result := result || jsonb_build_object(key_a, jsonb_build_object('type', type_a) || merged_val);
        ELSE
            -- Key only in a
            result := result || jsonb_build_object(key_a, val_a);
        END IF;
    END LOOP;

    -- Add keys only in b
    FOR key_b, val_b IN SELECT key, value FROM jsonb_each(b) WHERE NOT (a ? key) LOOP
        result := result || jsonb_build_object(key_b, val_b);
    END LOOP;

    RETURN result;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;


CREATE AGGREGATE public.jsonb_stats_summary_merge_agg(jsonb) (
    sfunc = public.jsonb_stats_summary_merge,
    stype = jsonb,
    initcond = '{}',
    finalfunc = public.jsonb_stats_to_summary_round
);


-- Test Setup

-- Create a temporary table for testing
CREATE TEMPORARY TABLE test_stats (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    test_case integer,
    stats jsonb
);

-- Insert test cases into the temporary table
INSERT INTO test_stats (test_case, stats)
VALUES
    (1, '{"num": 1, "str": "a", "bool": true}'::jsonb),
    (1, '{"num": 2, "str": "a", "bool": false}'::jsonb),
    (1, '{"num": 3, "str": "b", "bool": true}'::jsonb),
    (2, '{"num": 0, "str": "a", "bool": true}'::jsonb),
    (2, '{"num": 100, "str": "b", "bool": false}'::jsonb),
    (2, '{"num": 200, "str": "b", "bool": true}'::jsonb),
    (2, '{"num": 300, "str": "c", "bool": true}'::jsonb),
    (2, '{"num": 400, "str": "c", "bool": false}'::jsonb),
    (2, '{"num": 500, "str": "c", "bool": true}'::jsonb),
    (2, '{"num": 600, "str": "d", "bool": true}'::jsonb),
    (2, '{"num": 700, "str": "d", "bool": true}'::jsonb),
    (2, '{"num": 800, "str": "d", "bool": false}'::jsonb),
    (2, '{"num": 900, "str": "d", "bool": false}'::jsonb),
    (3, '{"a": 1}'::jsonb),
    (3, '{"a": "1"}'::jsonb),
    (4, '{"arr": [1, 2]}'::jsonb),
    (4, '{"arr": [2, 3]}'::jsonb),
    (5, '{"arr": ["a", "b"]}'::jsonb),
    (5, '{"arr": ["b", "c"]}'::jsonb),
    (6, '{"arr": [1, 2, "a"]}'::jsonb),
    (6, '{"arr": ["a", "b", "c"]}'::jsonb),
    (7, '{"num": 0  , "str": "a", "bool": true , "arr": [1]}'::jsonb),
    (7, '{"num": 100, "str": "b", "bool": false, "arr": [2,3]}'::jsonb),
    (7, '{"num": 200, "str": "b", "bool": true , "arr": [3,4,5]}'::jsonb),
    (7, '{"num": 300, "str": "c", "bool": true , "arr": [4,5]}'::jsonb),
    (7, '{"num": 400, "str": "c", "bool": false, "arr": [5]}'::jsonb),
    (7, '{"num": 500, "str": "c", "bool": true , "arr": ["1"]}'::jsonb),
    (7, '{"num": 600, "str": "d", "bool": true , "arr": ["2","3"]}'::jsonb),
    (7, '{"num": 700, "str": "d", "bool": true , "arr": ["3","4","5"]}'::jsonb),
    (7, '{"num": 800, "str": "d", "bool": false, "arr": ["4","5"]}'::jsonb),
    (7, '{"num": 900, "str": "d", "bool": false, "arr": ["5"]}'::jsonb);


-- Output reference numbers using sql, to validate the implementation.
CREATE TEMPORARY VIEW reference AS
SELECT
    test_case,
    SUM((stats->'num')::integer) AS num_sum,
    COUNT((stats->'num')::integer) AS num_count,
    MIN((stats->'num')::integer) AS num_min,
    MAX((stats->'num')::integer) AS num_max,
    AVG((stats->'num')::integer) AS num_mean,
    VARIANCE((stats->'num')::integer) AS num_variance,
    SUM(CASE WHEN (stats->>'bool')::boolean THEN 1 ELSE 0 END) AS bool_true_count,
    SUM(CASE WHEN NOT (stats->>'bool')::boolean THEN 1 ELSE 0 END) AS bool_false_count,
    -- Use a lateral join to unnest array elements and count distinct items
    COALESCE(SUM((SELECT COUNT(*)
                  FROM jsonb_array_elements_text(stats->'arr') AS element
                  WHERE element = '1')), 0) AS arr_1_count,
    COALESCE(SUM((SELECT COUNT(*)
                  FROM jsonb_array_elements_text(stats->'arr') AS element
                  WHERE element = '2')), 0) AS arr_2_count,
    COALESCE(SUM((SELECT COUNT(*)
                  FROM jsonb_array_elements_text(stats->'arr') AS element
                  WHERE element = '3')), 0) AS arr_3_count,
    COALESCE(SUM((SELECT COUNT(*)
                  FROM jsonb_array_elements_text(stats->'arr') AS element
                  WHERE element = 'a')), 0) AS arr_a_count,
    COALESCE(SUM((SELECT COUNT(*)
                  FROM jsonb_array_elements_text(stats->'arr') AS element
                  WHERE element = 'b')), 0) AS arr_b_count,
    COALESCE(SUM((SELECT COUNT(*)
                  FROM jsonb_array_elements_text(stats->'arr') AS element
                  WHERE element = 'c')), 0) AS arr_c_count,
    COUNT(*) FILTER (WHERE stats->>'str' = 'a') AS str_a_count,
    COUNT(*) FILTER (WHERE stats->>'str' = 'b') AS str_b_count,
    COUNT(*) FILTER (WHERE stats->>'str' = 'c') AS str_c_count,
    COUNT(*) FILTER (WHERE stats->>'str' = 'd') AS str_d_count
FROM test_stats
GROUP BY test_case
ORDER BY test_case;

-- Test cases
-- Show results suitable for jsonb_pretty for easy diffing.
\t
\a

-- Test 1: Each supported data type iterative case
SELECT jsonb_pretty(jsonb_stats_to_summary_agg(stats)) AS computed_stats
FROM test_stats
WHERE test_case = 1;
\x
\a
SELECT * FROM reference WHERE test_case = 1;
\a
\x

-- Test 2: Algorithms for many data points
SELECT jsonb_pretty(jsonb_stats_to_summary_agg(stats)) AS computed_stats
FROM test_stats
WHERE test_case = 2;
\x
\a
SELECT * FROM reference WHERE test_case = 2;
\a
\x

-- Test 3: Type mismatch
SELECT jsonb_pretty(jsonb_stats_to_summary_agg(stats)) AS computed_stats
FROM test_stats
WHERE test_case = 3;
-- Expected output: ERROR: Type mismatch for key "a": number vs string

-- Test 4: Array of numeric values
SELECT jsonb_pretty(jsonb_stats_to_summary_agg(stats)) AS computed_stats
FROM test_stats
WHERE test_case = 4;
\x
\a
SELECT * FROM reference WHERE test_case = 4;
\a
\x

-- Test 5: Array of string values
SELECT jsonb_pretty(jsonb_stats_to_summary_agg(stats)) AS computed_stats
FROM test_stats
WHERE test_case = 5;
\x
\a
SELECT * FROM reference WHERE test_case = 5;
\a
\x

-- Test 6: Array with type mismatch, each occurrence is just counted
SELECT jsonb_pretty(jsonb_stats_to_summary_agg(stats)) AS computed_stats
FROM test_stats
WHERE test_case = 6;
\x
\a
SELECT * FROM reference WHERE test_case = 6;
\a
\x

-- Additional tests for jsonb_stats_summary_merge function

-- Test 7: Merging two JSONB objects with different keys
WITH ordered_data AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY id) AS row_num,
        stats
    FROM test_stats
    WHERE test_case = 7
),
total_count AS (
    SELECT COUNT(*) AS total FROM ordered_data
),
grouped_data AS (
    SELECT
        jsonb_stats_to_summary_agg(stats) FILTER (WHERE row_num <= total.total / 2) AS first_summary,
        jsonb_stats_to_summary_agg(stats) FILTER (WHERE row_num > total.total / 2) AS last_summary
    FROM ordered_data, total_count total
),
ordered_groups AS (
    SELECT first_summary AS stats_summary FROM grouped_data
    UNION ALL
    SELECT last_summary  AS stats_summary FROM grouped_data
)
SELECT '## first_summary' AS stats_summary
UNION ALL
SELECT jsonb_pretty(first_summary) AS stats_summary FROM grouped_data
UNION ALL
SELECT '## last_summary' AS stats_summary
UNION ALL
SELECT jsonb_pretty(last_summary) AS stats_summary FROM grouped_data
UNION ALL
SELECT '## jsonb_stats_summary_merge_agg' AS stats_summary
UNION ALL
SELECT jsonb_pretty(jsonb_stats_summary_merge_agg(stats_summary)) AS stats_summary
FROM ordered_groups
UNION ALL
SELECT '## jsonb_stats_summary_merge' AS stats_summary
UNION ALL
SELECT jsonb_pretty(jsonb_stats_summary_merge(first_summary, last_summary)) AS stats_summary
FROM grouped_data
UNION ALL
SELECT '## jsonb_stats_to_summary_agg' AS stats_summary
UNION ALL
SELECT jsonb_pretty(jsonb_stats_to_summary_agg(stats)) AS stats_summary
FROM ordered_data;

