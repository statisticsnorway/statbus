BEGIN;

\i test/setup.sql

-- STATBUS-613: the staging flush and the history reduce do only the work
-- their result needs.
--
-- public.statistical_unit_flush_staging matches each staged unit to its rows
-- in statistical_unit, in its DELETE (rows whose period is no longer staged)
-- and its MERGE (changed and new periods). statistical_unit_unit_idx, a btree
-- on (unit_type, unit_id), answers that lookup; the GiST temporal key answers
-- it several times slower. The test stages a changed load for some units and
-- checks that the flush leaves exactly the staged rows for those units, every
-- other unit untouched, and that it found the main rows through the btree.
-- Index scans are counted from pg_stat_get_xact_numscans, this transaction's
-- own scans. The index check runs with enable_seqscan off, as in test 398: on
-- this small fixture a sequential scan is as cheap, and the check asserts that
-- the lookup can be driven by the btree, which is what a large register needs.
--
-- worker.statistical_history_facet_delta_apply collects each group's unit ids
-- unordered; worker.unit_ids_apply sorts them. The test checks that every
-- history delta row lists its contributing units in ascending order and
-- exactly once.

CALL test.set_user_from_email('test.admin@statbus.org');

\o /dev/null
\set ECHO none
\i samples/demo/getting-started.sql
\o
\set ECHO all

\echo "600 enterprises, each with one primary legal unit, in reverse id order of creation"
INSERT INTO public.enterprise (short_name, edit_by_user_id, edit_comment)
SELECT format('E399-%s', n), (SELECT id FROM auth.user LIMIT 1), 'STATBUS-613 test enterprise'
FROM generate_series(600, 1, -1) AS n;

INSERT INTO public.legal_unit (valid_from, name, enterprise_id, primary_for_enterprise, status_id, edit_by_user_id, edit_comment)
SELECT '2020-01-01'::date, format('LU399-%s', e.short_name), e.id, true,
       (SELECT id FROM public.status WHERE code = 'active' LIMIT 1),
       (SELECT id FROM auth.user LIMIT 1), 'STATBUS-613 test legal unit'
FROM public.enterprise AS e
WHERE e.short_name LIKE 'E399-%'
ORDER BY e.id DESC;

-- The worker runs the analytics as the database owner, not as an application user.
RESET ROLE;

CALL worker.process_tasks(p_queue => 'analytics');

\echo "399.1 statistical units and history delta rows derived"
SELECT unit_type, count(*) AS rows FROM public.statistical_unit GROUP BY unit_type ORDER BY unit_type;
SELECT count(*) > 0 AS history_delta_rows FROM public.statistical_history_facet_delta;

\echo "399.2 every history delta row lists its units ascending and once"
SELECT count(*) AS history_rows,
       count(*) FILTER (WHERE unit_ids = (SELECT array_agg(DISTINCT u ORDER BY u) FROM unnest(unit_ids) AS u)) AS rows_sorted_and_distinct
FROM public.statistical_history_facet_delta;

\echo "399.3 the legal units of the history delta rows are exactly the derived legal units"
SELECT (SELECT array_agg(DISTINCT u ORDER BY u)
          FROM public.statistical_history_facet_delta AS h, unnest(h.unit_ids) AS u
         WHERE h.unit_type = 'legal_unit')
     = (SELECT array_agg(DISTINCT unit_id ORDER BY unit_id)
          FROM public.statistical_unit WHERE unit_type = 'legal_unit') AS history_units_are_the_legal_units;

-- The changed load: every tenth legal unit. Its one period becomes two (split
-- at 2022-01-01, the second renamed), so the flush deletes the old period,
-- inserts both new ones, and leaves every other unit as it was.
CREATE TEMP TABLE before_flush ON COMMIT DROP AS
SELECT unit_type, unit_id, valid_from, valid_to, valid_until, name
FROM public.statistical_unit;

CREATE TEMP TABLE changed ON COMMIT DROP AS
SELECT unit_type, unit_id FROM public.statistical_unit
WHERE unit_type = 'legal_unit' AND unit_id % 10 = 0;

INSERT INTO public.statistical_unit_staging (unit_type, unit_id, valid_from, valid_to, valid_until, name, external_idents, search, used_for_counting, stats, stats_summary)
SELECT su.unit_type, su.unit_id, p.valid_from, p.valid_to, p.valid_until, p.name, su.external_idents, su.search, su.used_for_counting, su.stats, su.stats_summary
FROM public.statistical_unit AS su
JOIN changed USING (unit_type, unit_id)
CROSS JOIN LATERAL (VALUES
    (su.valid_from, '2021-12-31'::date, '2022-01-01'::date, su.name),
    ('2022-01-01'::date, su.valid_to, su.valid_until, su.name || ' renamed')
) AS p(valid_from, valid_to, valid_until, name);

SET LOCAL enable_seqscan = off;

CALL public.statistical_unit_flush_staging();

\echo "399.4 the flush found the affected units' rows through the (unit_type, unit_id) btree"
SELECT coalesce(pg_stat_get_xact_numscans(to_regclass('public.statistical_unit_unit_idx')), 0) > 0 AS flush_used_unit_index;

\echo "399.5 changed units have exactly their two staged periods"
SELECT count(DISTINCT c.unit_id) AS changed_units,
       count(*) AS rows_of_changed_units,
       count(*) FILTER (WHERE su.valid_from < '2022-01-01' AND su.valid_until = '2022-01-01' AND su.name NOT LIKE '% renamed') AS first_periods,
       count(*) FILTER (WHERE su.valid_from = '2022-01-01' AND su.name LIKE '% renamed') AS second_periods
FROM changed AS c
JOIN public.statistical_unit AS su USING (unit_type, unit_id);

\echo "399.6 every other unit is unchanged"
SELECT count(*) AS rows_of_other_units,
       count(*) = (SELECT count(*) FROM before_flush AS b WHERE NOT EXISTS (SELECT 1 FROM changed AS c WHERE c.unit_type = b.unit_type AND c.unit_id = b.unit_id)) AS same_row_count,
       NOT EXISTS (
         (SELECT unit_type, unit_id, valid_from, valid_to, valid_until, name FROM public.statistical_unit AS su
           WHERE NOT EXISTS (SELECT 1 FROM changed AS c WHERE c.unit_type = su.unit_type AND c.unit_id = su.unit_id))
         EXCEPT
         (SELECT unit_type, unit_id, valid_from, valid_to, valid_until, name FROM before_flush)
       ) AS same_rows
FROM public.statistical_unit AS su
WHERE NOT EXISTS (SELECT 1 FROM changed AS c WHERE c.unit_type = su.unit_type AND c.unit_id = su.unit_id);

\echo "399.7 staging is empty after the flush"
SELECT count(*) AS staged_rows_left FROM public.statistical_unit_staging;

ROLLBACK;
