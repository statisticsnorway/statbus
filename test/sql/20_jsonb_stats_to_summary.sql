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
    -- Calculate Standard Deviation
    CASE WHEN COUNT((stats->'num')::integer) > 1
         THEN SQRT(VARIANCE((stats->'num')::integer))
         ELSE NULL END AS num_stddev,
    -- Calculate Coefficient of Variation (CV)
    CASE WHEN AVG((stats->'num')::integer) <> 0 THEN
        (CASE WHEN COUNT((stats->'num')::integer) > 1 THEN
            SQRT(VARIANCE((stats->'num')::integer)) / AVG((stats->'num')::integer)
        ELSE NULL END)
    ELSE NULL END AS num_coefficient_of_variation,
    -- Calculate Rate of Change
    CASE WHEN MIN((stats->'num')::integer) <> 0 THEN
        (MAX((stats->'num')::integer) - MIN((stats->'num')::integer)) / MIN((stats->'num')::integer) 
    ELSE NULL END AS num_rate_of_change,
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

