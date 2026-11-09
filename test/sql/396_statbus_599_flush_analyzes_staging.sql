BEGIN;

\i test/setup.sql

-- STATBUS-599: statistical_unit_flush_staging matches the staged rows against
-- statistical_unit with a DELETE and a MERGE. Staging is truncated after each
-- flush and refilled by the refresh batches, so the flush analyzes it first:
-- the planner then sees the load it is about to match, and chooses a plan for
-- its real size (hash joins for a large load, index lookups for a small one).
-- With statistics from an earlier, smaller load, 1.8M staged rows were matched
-- one unit at a time and took 221 s instead of 25 s.

CALL test.set_user_from_email('test.admin@statbus.org');

\o /dev/null
\set ECHO none
\i samples/demo/getting-started.sql
\o
\set ECHO all

\echo "1200 enterprises, each with one primary legal unit"
INSERT INTO public.enterprise (short_name, edit_by_user_id, edit_comment)
SELECT format('E396-%s', n), (SELECT id FROM auth.user LIMIT 1), 'STATBUS-599 test enterprise'
FROM generate_series(1, 1200) AS n;

INSERT INTO public.legal_unit (valid_from, name, enterprise_id, primary_for_enterprise, status_id, edit_by_user_id, edit_comment)
SELECT '2020-01-01'::date, format('LU396-%s', e.short_name), e.id, true,
       (SELECT id FROM public.status WHERE code = 'active' LIMIT 1),
       (SELECT id FROM auth.user LIMIT 1), 'STATBUS-599 test legal unit'
FROM public.enterprise AS e
WHERE e.short_name LIKE 'E396-%';

-- The worker runs the analytics as the database owner, not as an application user.
RESET ROLE;

\echo "The analytics computes the statistical units through staging and its flush"
CALL worker.process_tasks(p_queue => 'analytics');

SELECT count(*) AS statistical_units FROM public.statistical_unit;

\echo "The flush planned from statistics of the load it just matched"
\echo "(the truncate after the flush resets the row count but keeps the column statistics)"
SELECT s.analyze_count + s.autoanalyze_count > 0 AS staging_was_analyzed,
       (SELECT array_agg(v::text ORDER BY v::text)
          FROM pg_stats AS p, unnest(p.most_common_vals::text::text[]) AS v
         WHERE p.schemaname = 'public' AND p.tablename = 'statistical_unit_staging' AND p.attname = 'unit_type')
       AS unit_types_in_staging_statistics,
       (SELECT array_agg(DISTINCT unit_type::text ORDER BY unit_type::text) FROM public.statistical_unit)
       AS unit_types_flushed
FROM pg_stat_user_tables AS s
WHERE s.relid = 'public.statistical_unit_staging'::regclass;

\echo "Staging is empty after the flush"
SELECT count(*) AS staged_rows_left FROM public.statistical_unit_staging;

ROLLBACK;
