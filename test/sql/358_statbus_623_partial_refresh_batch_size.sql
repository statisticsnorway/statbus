BEGIN;

\i test/setup.sql

-- STATBUS-623: a partial recalculation refreshes in change sets as large as a
-- full one, while a small change still spreads over the workers.
--
-- worker.derive_statistical_unit with unit id ranges (the partial path, run
-- after every import or edit) splits the changed units into change sets through
-- public.get_temporally_closed_change_sets and spawns one
-- statistical_unit_refresh_batch per set. STATBUS-614 gave the full path
-- 8000-unit sets; the partial path made 1000-unit sets, so a 50 % change of the
-- Norway register ran 1,551 batches (716 s summed) where a full recalculation
-- runs 451 (STATBUS-616 bench box). The fixture has 3,000 enterprises with one
-- legal unit each (6,000 units). Renaming all legal units is a change of 6,000
-- units. The size is four batches per analytics worker, between 1000 and 8000
-- units (worker.partial_change_set_size), and each batch keeps whole
-- enterprise groups.

CALL test.set_user_from_email('test.admin@statbus.org');

\o /dev/null
\set ECHO none
\i samples/demo/getting-started.sql
\o
\set ECHO all

INSERT INTO public.enterprise (short_name, edit_by_user_id, edit_comment)
SELECT format('E623-%s', n), (SELECT id FROM auth.user LIMIT 1), 'STATBUS-623 test enterprise'
FROM generate_series(1, 3000) AS n;

INSERT INTO public.legal_unit (valid_from, name, enterprise_id, primary_for_enterprise, status_id, edit_by_user_id, edit_comment)
SELECT '2020-01-01'::date, format('LU623-%s', e.short_name), e.id, true,
       (SELECT id FROM public.status WHERE code = 'active' LIMIT 1),
       (SELECT id FROM auth.user LIMIT 1), 'STATBUS-623 test legal unit'
FROM public.enterprise AS e
WHERE e.short_name LIKE 'E623-%';

-- The worker runs the analytics as the database owner, not as an application user.
RESET ROLE;
CALL worker.process_tasks(p_queue => 'analytics');

\echo "623.1 the register: enterprises and legal units derived"
SELECT unit_type, count(*) AS rows FROM public.statistical_unit GROUP BY unit_type ORDER BY unit_type;

\echo "623.2 a change of all 3,000 legal units with one analytics worker: four batches of whole enterprise groups"
-- One worker makes the rule's size visible on this fixture: 6,000 changed units / (4 batches x 1 worker) = 1500.
-- safeupdate: the analytics queue's one registry row.
UPDATE worker.queue_registry SET default_concurrency = 1 WHERE queue = 'analytics';
-- safeupdate: every fixture legal unit is renamed, the change under test.
UPDATE public.legal_unit SET name = name || ' renamed' WHERE name LIKE 'LU623-%';
CALL worker.process_tasks(p_queue => 'analytics');
CREATE TEMP TABLE partial_batches ON COMMIT DROP AS
SELECT b.id, b.payload
FROM worker.tasks AS b
WHERE b.command = 'statistical_unit_refresh_batch'
  AND b.parent_id = (SELECT max(id) FROM worker.tasks WHERE command = 'derive_statistical_unit')
  AND jsonb_typeof(b.payload->'enterprise_ids') = 'array';
SELECT count(*) AS batches,
       max(jsonb_array_length(payload->'enterprise_ids') + jsonb_array_length(payload->'legal_unit_ids')) AS largest_batch_units,
       sum(jsonb_array_length(payload->'enterprise_ids') + jsonb_array_length(payload->'legal_unit_ids')) AS units_in_batches
FROM partial_batches;

\echo "623.3 every legal unit is in exactly one batch, with its enterprise"
SELECT count(*) AS legal_units,
       count(*) FILTER (WHERE in_batches = 1) AS in_exactly_one_batch,
       count(*) FILTER (WHERE with_enterprise) AS with_their_enterprise
FROM (
    SELECT lu.id,
           (SELECT count(*) FROM partial_batches AS b, jsonb_array_elements_text(b.payload->'legal_unit_ids') AS x WHERE x::int = lu.id) AS in_batches,
           EXISTS (SELECT 1 FROM partial_batches AS b
                    WHERE b.payload->'legal_unit_ids' @> to_jsonb(lu.id)
                      AND b.payload->'enterprise_ids' @> to_jsonb(lu.enterprise_id)) AS with_enterprise
    FROM public.legal_unit AS lu
) AS t;

\echo "623.4 the recalculation carried every new name into statistical_unit"
SELECT count(*) FILTER (WHERE name LIKE '% renamed') AS renamed_legal_units,
       count(*) AS legal_units
FROM public.statistical_unit WHERE unit_type = 'legal_unit';

\echo "623.5 change set sizes from the change, with four analytics workers: 3 and 6,000 units, 40,000, 128,000 and more"
-- safeupdate: back to the registered four analytics workers.
UPDATE worker.queue_registry SET default_concurrency = 4 WHERE queue = 'analytics';
SELECT worker.partial_change_set_size(NULL, '{[1,6001)}', NULL) AS size_for_6000_units,
       worker.partial_change_set_size('{[1,20001)}', '{[1,20001)}', NULL) AS size_for_40000_units,
       worker.partial_change_set_size(NULL, '{[1,64001)}', '{[1,64001)}') AS size_for_128000_units,
       worker.partial_change_set_size(NULL, '{[1,1000001)}', NULL) AS size_for_1000000_units,
       worker.partial_change_set_size(NULL, '{[1,4)}', NULL) AS size_for_3_units;

ROLLBACK;
