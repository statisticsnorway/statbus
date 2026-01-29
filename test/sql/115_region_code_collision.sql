BEGIN;

\i test/setup.sql

\echo "Testing region code uniqueness constraint"

-- Test that regions with the same numeric code cannot coexist
-- The code column is generated from the path: only digits are kept
-- e.g., path '01' -> code '01', path 'AL.01' -> code '01' (collision!)

\echo "Load first region with path '01' (code='01')"
\copy public.region_upload(path,name) FROM stdin WITH (FORMAT csv, DELIMITER ',');
01,First Region 01
\.

SELECT path, code, name FROM public.region WHERE code = '01';

\echo "Attempt to load second region with path 'AL.01' (code='01') - should fail due to unique constraint"
SAVEPOINT before_collision;
\set ON_ERROR_STOP off
\copy public.region_upload(path,name) FROM stdin WITH (FORMAT csv, DELIMITER ',');
AL,Albania
AL.01,Second Region with same code 01
\.
\set ON_ERROR_STOP on
ROLLBACK TO before_collision;

\echo "Verify only one region with code '01' exists"
SELECT path, code, name FROM public.region WHERE code = '01';

\echo "Test that different codes work fine"
\copy public.region_upload(path,name) FROM stdin WITH (FORMAT csv, DELIMITER ',');
02,Region 02
03,Region 03
\.

SELECT path, code, name FROM public.region ORDER BY code;

\echo "Test that regions without codes (NULL code) can coexist"
\copy public.region_upload(path,name) FROM stdin WITH (FORMAT csv, DELIMITER ',');
AA,Region AA
BB,Region BB
\.

-- These should both have NULL codes since paths contain no digits
SELECT path, code, name FROM public.region WHERE code IS NULL ORDER BY path;

\echo "Region code uniqueness tests completed"

ROLLBACK;
