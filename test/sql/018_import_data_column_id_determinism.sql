BEGIN;

\i test/setup.sql

-- SCOPE (STATBUS-116): this test ENFORCES + documents the invariant that the
-- legal_relationship step's import_data_column ids follow priority order — i.e.
-- the GENERATED-ALWAYS ids are priority-determined after migration
-- 20260218215337 gained ORDER BY derived_priority. It does NOT reproduce the
-- cross-build divergence locally: on one machine two from-empty builds share a
-- physical layout, so the ids are co-monotonic even without the fix. The
-- differential evidence that the bug was real is the AC#6 multi-delta oracle RED
-- against the rc.03 published seed (recorded on STATBUS-116); the true
-- cross-build regression gate is the deferred post-fix seed run (Part 2).

CALL test.set_user_from_email('test.admin@statbus.org');

\echo "Test: import_data_column identity ids are assigned deterministically by priority (STATBUS-116)"
\echo "----------------------------------------------------------------------------------------------"
\echo "The legal_relationship step's data columns are inserted by migration 20260218215337 via an"
\echo "INSERT ... SELECT that carries ORDER BY derived_priority. import_data_column.id is GENERATED"
\echo "ALWAYS AS IDENTITY (assigned in row-emission order), so the ORDER BY makes id a pure function"
\echo "of priority — independent of physical/engine layout. Without it, two from-empty builds could"
\echo "assign the same logical columns DIFFERENT ids (the AC#6 multi-delta INCR-vs-FULL drift this"
\echo "fix closes). Assert: sorting the step's columns by priority yields the same id sequence as"
\echo "sorting by id (id ascends with priority). The absolute id values are intentionally NOT"
\echo "asserted — they depend on how many columns precede this step and are not the invariant here."

SELECT
    s.code AS step,
    array_agg(idc.id ORDER BY idc.priority) = array_agg(idc.id ORDER BY idc.id) AS ids_follow_priority
FROM public.import_data_column AS idc
JOIN public.import_step AS s ON idc.step_id = s.id
WHERE s.code = 'legal_relationship'
GROUP BY s.code;

ROLLBACK;
