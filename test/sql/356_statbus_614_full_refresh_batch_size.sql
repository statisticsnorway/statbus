BEGIN;

\i test/setup.sql

-- STATBUS-614: a full recalculation refreshes statistical units in change sets
-- of up to 8000 units.
--
-- worker.derive_statistical_unit with no unit ranges splits the whole register
-- into change sets through public.get_temporally_closed_change_sets and spawns
-- one statistical_unit_refresh_batch per set. Work paid once per batch is
-- cheaper with fewer batches: on the full register (3,118,352 units, four
-- workers) 8000-unit sets took 514-526 s against 599-607 s for 1000-unit sets,
-- with identical rows. The fixture has 3,000 enterprises with one legal unit
-- each (6,000 units): one full-refresh batch holds them all, where 1000-unit
-- sets made six. Each set keeps whole enterprise groups, and the units the
-- batches refresh are exactly the units of the register. 614.6 covers the
-- enterprise timeline refresh that such a batch runs (see there).

CALL test.set_user_from_email('test.admin@statbus.org');

\o /dev/null
\set ECHO none
\i samples/demo/getting-started.sql
\o
\set ECHO all

INSERT INTO public.enterprise (short_name, edit_by_user_id, edit_comment)
SELECT format('E614-%s', n), (SELECT id FROM auth.user LIMIT 1), 'STATBUS-614 test enterprise'
FROM generate_series(1, 3000) AS n;

INSERT INTO public.legal_unit (valid_from, name, enterprise_id, primary_for_enterprise, status_id, edit_by_user_id, edit_comment)
SELECT '2020-01-01'::date, format('LU614-%s', e.short_name), e.id, true,
       (SELECT id FROM public.status WHERE code = 'active' LIMIT 1),
       (SELECT id FROM auth.user LIMIT 1), 'STATBUS-614 test legal unit'
FROM public.enterprise AS e
WHERE e.short_name LIKE 'E614-%';

-- The worker runs the analytics as the database owner, not as an application user.
RESET ROLE;

CALL worker.process_tasks(p_queue => 'analytics');

CREATE TEMP TABLE derived_before ON COMMIT DROP AS
SELECT unit_type, unit_id, valid_from, valid_until, name FROM public.statistical_unit;

\echo "614.1 the register: enterprises and legal units derived"
SELECT unit_type, count(*) AS rows FROM public.statistical_unit GROUP BY unit_type ORDER BY unit_type;

\echo "614.2 a full recalculation"
SELECT worker.enqueue_derive_statistical_unit_all() IS NOT NULL AS enqueued;
CALL worker.process_tasks(p_queue => 'analytics');

CREATE TEMP TABLE full_batches ON COMMIT DROP AS
SELECT b.id, b.payload
FROM worker.tasks AS b
WHERE b.command = 'statistical_unit_refresh_batch'
  AND b.parent_id = (SELECT max(id) FROM worker.tasks WHERE command = 'derive_statistical_unit')
  AND jsonb_typeof(b.payload->'enterprise_ids') = 'array';

\echo "614.3 the full refresh made one batch of all 6,000 units, within the 8000-unit target"
SELECT count(*) AS batches,
       max(jsonb_array_length(payload->'enterprise_ids') + jsonb_array_length(payload->'legal_unit_ids')) AS largest_batch_units,
       sum(jsonb_array_length(payload->'enterprise_ids') + jsonb_array_length(payload->'legal_unit_ids')) AS units_in_batches
FROM full_batches;

\echo "614.4 each enterprise and each legal unit is in exactly one batch, with its enterprise"
SELECT count(*) AS legal_units,
       count(*) FILTER (WHERE in_batches = 1) AS in_exactly_one_batch,
       count(*) FILTER (WHERE with_enterprise) AS with_their_enterprise
FROM (
    SELECT lu.id,
           (SELECT count(*) FROM full_batches AS b, jsonb_array_elements_text(b.payload->'legal_unit_ids') AS x WHERE x::int = lu.id) AS in_batches,
           EXISTS (SELECT 1 FROM full_batches AS b
                    WHERE b.payload->'legal_unit_ids' @> to_jsonb(lu.id)
                      AND b.payload->'enterprise_ids' @> to_jsonb(lu.enterprise_id)) AS with_enterprise
    FROM public.legal_unit AS lu
) AS t;

\echo "614.5 the recalculation reproduces every statistical unit row"
SELECT (SELECT count(*) FROM public.statistical_unit) AS rows_after,
       NOT EXISTS (
         (SELECT unit_type, unit_id, valid_from, valid_until, name FROM public.statistical_unit
          EXCEPT SELECT unit_type, unit_id, valid_from, valid_until, name FROM derived_before)
         UNION ALL
         (SELECT unit_type, unit_id, valid_from, valid_until, name FROM derived_before
          EXCEPT SELECT unit_type, unit_id, valid_from, valid_until, name FROM public.statistical_unit)
       ) AS same_rows;

-- A batch of this size must not cost more than linear time in timeline_enterprise_refresh, also when the planner's
-- statistics undercount the tables (a database cloned from a template, or analyzed while an earlier transaction held
-- its rows): the procedure reads the batch's enterprise segments into an analyzed table first. With statistics that
-- say each source table holds one row, the segments of all 3,000 enterprises were read once per enterprise
-- (4,504,500 rows, 22 s) before; the refresh reads each segment once.
\echo "614.6 an enterprise timeline refresh of the whole batch reads each enterprise segment once, also with undercounting statistics"
UPDATE pg_class SET reltuples = 1, relpages = greatest(relpages, 1)
 WHERE oid IN ('public.enterprise'::regclass, 'public.timesegments'::regclass, 'public.timeline_legal_unit'::regclass,
               'public.timeline_establishment'::regclass, 'public.timeline_enterprise'::regclass);
CREATE TEMP TABLE timeline_enterprise_before ON COMMIT DROP AS SELECT * FROM public.timeline_enterprise;
SELECT range_agg(int4range(id, id, '[]')) AS all_enterprises FROM public.enterprise \gset
SELECT coalesce(sum(pg_stat_get_xact_tuples_fetched(indexrelid)), 0) AS segment_reads_before
FROM pg_index WHERE indrelid = 'public.timesegments'::regclass \gset
CALL public.timeline_enterprise_refresh(:'all_enterprises');
SELECT (SELECT coalesce(sum(pg_stat_get_xact_tuples_fetched(indexrelid)), 0) FROM pg_index
         WHERE indrelid = 'public.timesegments'::regclass) - :segment_reads_before AS segment_rows_read,
       (SELECT count(*) FROM public.timesegments WHERE unit_type = 'enterprise') AS enterprise_segments,
       (SELECT count(*) FROM ((TABLE public.timeline_enterprise EXCEPT ALL TABLE timeline_enterprise_before)
                              UNION ALL (TABLE timeline_enterprise_before EXCEPT ALL TABLE public.timeline_enterprise)) AS d) AS rows_changed;

ROLLBACK;
