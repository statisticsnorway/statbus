-- Test: jsonb_stats extension functions
-- Tests the full pipeline used by timeline views for statistical aggregation

-- Create test table mirroring stat_for_unit's typed columns
CREATE TEMPORARY TABLE test_stat_rows (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    test_case integer,
    entity_id integer,
    code text,
    value_int integer,
    value_float double precision,
    value_string text,
    value_bool boolean,
    stat JSONB GENERATED ALWAYS AS (
        COALESCE(stat(value_int), stat(value_float), stat(value_string), stat(value_bool))
    ) STORED
);

-- Test case 1: 3 entities, each with (num, str, bool) stats
-- Entity 1: num=1, str='a', bool=true
-- Entity 2: num=2, str='a', bool=false
-- Entity 3: num=3, str='b', bool=true
INSERT INTO test_stat_rows (test_case, entity_id, code, value_int) VALUES
    (1, 1, 'num', 1), (1, 2, 'num', 2), (1, 3, 'num', 3);
INSERT INTO test_stat_rows (test_case, entity_id, code, value_string) VALUES
    (1, 1, 'str', 'a'), (1, 2, 'str', 'a'), (1, 3, 'str', 'b');
INSERT INTO test_stat_rows (test_case, entity_id, code, value_bool) VALUES
    (1, 1, 'bool', true), (1, 2, 'bool', false), (1, 3, 'bool', true);

-- Test case 2: 10 entities for numeric accuracy testing
INSERT INTO test_stat_rows (test_case, entity_id, code, value_int) VALUES
    (2, 1, 'num', 0), (2, 2, 'num', 100), (2, 3, 'num', 200), (2, 4, 'num', 300), (2, 5, 'num', 400),
    (2, 6, 'num', 500), (2, 7, 'num', 600), (2, 8, 'num', 700), (2, 9, 'num', 800), (2, 10, 'num', 900);
INSERT INTO test_stat_rows (test_case, entity_id, code, value_string) VALUES
    (2, 1, 'str', 'a'), (2, 2, 'str', 'b'), (2, 3, 'str', 'b'), (2, 4, 'str', 'c'), (2, 5, 'str', 'c'),
    (2, 6, 'str', 'c'), (2, 7, 'str', 'd'), (2, 8, 'str', 'd'), (2, 9, 'str', 'd'), (2, 10, 'str', 'd');
INSERT INTO test_stat_rows (test_case, entity_id, code, value_bool) VALUES
    (2, 1, 'bool', true), (2, 2, 'bool', false), (2, 3, 'bool', true), (2, 4, 'bool', true), (2, 5, 'bool', false),
    (2, 6, 'bool', true), (2, 7, 'bool', true), (2, 8, 'bool', true), (2, 9, 'bool', false), (2, 10, 'bool', false);

-- Reference view for SQL-native aggregation (for verification)
CREATE TEMPORARY VIEW reference AS
SELECT
    test_case,
    SUM(value_int) AS num_sum,
    COUNT(value_int) AS num_count,
    MIN(value_int) AS num_min,
    MAX(value_int) AS num_max,
    ROUND(AVG(value_int), 2) AS num_mean,
    SUM(CASE WHEN value_bool THEN 1 ELSE 0 END) AS bool_true_count,
    SUM(CASE WHEN NOT value_bool THEN 1 ELSE 0 END) AS bool_false_count,
    COUNT(*) FILTER (WHERE value_string = 'a') AS str_a_count,
    COUNT(*) FILTER (WHERE value_string = 'b') AS str_b_count,
    COUNT(*) FILTER (WHERE value_string = 'c') AS str_c_count,
    COUNT(*) FILTER (WHERE value_string = 'd') AS str_d_count
FROM test_stat_rows
GROUP BY test_case
ORDER BY test_case;

\t
\a

-- Test 1: stat() constructors
SELECT '## stat() constructors' AS test;
SELECT stat(42);
SELECT stat(3.14::float8);
SELECT stat('hello'::text);
SELECT stat(true);

-- Test 2: jsonb_stats_agg(code, stat) - builds stats per entity
-- This is Level 1: build one stats object per entity (like establishment_stats CTE)
SELECT '## Level 1: stats per entity (test_case=1, entity_id=1)' AS test;
SELECT jsonb_pretty(jsonb_stats_agg(code, stat)) AS stats
FROM test_stat_rows
WHERE test_case = 1 AND entity_id = 1;

-- Test 3: jsonb_stats_to_agg - convert single entity stats to stats_agg
-- This is Level 2: convert per-entity stats to stats_agg (like stats_summary in timeline views)
SELECT '## Level 2: stats_agg per entity (test_case=1, entity_id=1)' AS test;
WITH entity_stats AS (
    SELECT jsonb_stats_agg(code, stat) AS stats
    FROM test_stat_rows
    WHERE test_case = 1 AND entity_id = 1
)
SELECT jsonb_pretty(jsonb_stats_to_agg(stats)) AS stats_agg
FROM entity_stats;

-- Test 4: Full pipeline - build per-entity stats_agg, then merge across entities
-- This is Level 3: merge multiple entities' stats_agg (like establishment_aggs CTE)
SELECT '## Level 3: merged stats_agg across all entities (test_case=1)' AS test;
WITH entity_stats AS (
    SELECT entity_id,
           jsonb_stats_to_agg(jsonb_stats_agg(code, stat)) AS stats_agg
    FROM test_stat_rows
    WHERE test_case = 1
    GROUP BY entity_id
)
SELECT jsonb_pretty(jsonb_stats_merge_agg(stats_agg)) AS merged
FROM entity_stats;

\x
\a
SELECT * FROM reference WHERE test_case = 1;
\a
\x

-- Test 5: Full pipeline with 10 entities
SELECT '## Level 3: merged stats_agg (test_case=2)' AS test;
WITH entity_stats AS (
    SELECT entity_id,
           jsonb_stats_to_agg(jsonb_stats_agg(code, stat)) AS stats_agg
    FROM test_stat_rows
    WHERE test_case = 2
    GROUP BY entity_id
)
SELECT jsonb_pretty(jsonb_stats_merge_agg(stats_agg)) AS merged
FROM entity_stats;

\x
\a
SELECT * FROM reference WHERE test_case = 2;
\a
\x

-- Test 6: Split-merge test
-- Split entities into two halves, merge separately, then merge the halves
-- Verifies merge associativity: merge(merge(A), merge(B)) == merge(A ∪ B)
SELECT '## Split-merge test' AS test;
WITH entity_stats AS (
    SELECT entity_id,
           jsonb_stats_to_agg(jsonb_stats_agg(code, stat)) AS stats_agg
    FROM test_stat_rows
    WHERE test_case = 2
    GROUP BY entity_id
),
first_half AS (
    SELECT jsonb_stats_merge_agg(stats_agg) AS agg
    FROM entity_stats
    WHERE entity_id <= 5
),
second_half AS (
    SELECT jsonb_stats_merge_agg(stats_agg) AS agg
    FROM entity_stats
    WHERE entity_id > 5
),
ordered_groups AS (
    SELECT agg AS stats_summary FROM first_half
    UNION ALL
    SELECT agg AS stats_summary FROM second_half
)
SELECT '## first_half' AS stats_summary
UNION ALL
SELECT jsonb_pretty(agg) FROM first_half
UNION ALL
SELECT '## second_half' AS stats_summary
UNION ALL
SELECT jsonb_pretty(agg) FROM second_half
UNION ALL
SELECT '## jsonb_stats_merge_agg'
UNION ALL
SELECT jsonb_pretty(jsonb_stats_merge_agg(stats_summary)) FROM ordered_groups
UNION ALL
SELECT '## jsonb_stats_merge'
UNION ALL
SELECT jsonb_pretty(jsonb_stats_merge(f.agg, s.agg)) FROM first_half f, second_half s;
