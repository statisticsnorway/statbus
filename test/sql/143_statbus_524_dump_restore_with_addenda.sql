-- test-isolation: database-per-test
--
-- STATBUS-524 AC#2/#3: a pg_dump -Fc of a database with rows in
-- external_ident, tag_for_unit and unit_notes restores with pg_restore
-- --single-transaction --exit-on-error, and sql_saga.check_integrity()
-- passes on the restored database. Before STATBUS-524 the addendum tables
-- were guarded by CHECK constraints calling admin.*_id_exists functions;
-- pg_dump inlines those into CREATE TABLE and does not order table data by
-- function dependencies, so external_ident (alphabetically before
-- legal_unit) restored before its parent and the COPY failed.
--
-- After the restore block, the original test database asserts the reference
-- behaviour of the new foreign keys: an insert referencing a missing legal
-- unit is refused, deleting a legal unit that still has an addendum is
-- refused (sql_saga regular foreign keys are NO ACTION in 1.3), and
-- deleting a power group cascades to its unit_notes row (native foreign
-- key ON DELETE CASCADE).
--
-- The fixtures COMMIT (no wrapping transaction) because pg_dump is a
-- separate connection and cannot see uncommitted rows; the
-- database-per-test marker gives this test its own throwaway database.
-- auth.uid() from set_user_from_email does not survive across autocommit
-- statements, so edit_by_user_id is given explicitly. Shell output is
-- reduced to fixed markers: the test database name contains a pid and must
-- not appear in the asserted output.

\i test/setup.sql

\echo "=== Test 143: STATBUS-524 dump/restore with addendum rows ==="

CALL test.set_user_from_email('test.admin@statbus.org');

-- Statements interpolate psql variables (captured ids), so their echoed text
-- would carry run-specific values; only the \echo markers, query results and
-- ERROR lines below are part of the asserted output.
\set ECHO none

INSERT INTO public.enterprise (short_name, edit_by_user_id, edit_comment)
SELECT 'T143', id, 'Test 143 enterprise' FROM auth.user LIMIT 1;

INSERT INTO public.legal_unit (valid_from, name, enterprise_id, primary_for_enterprise, status_id, edit_by_user_id, edit_comment)
SELECT '2020-01-01'::date, 'T143 Legal Unit',
    (SELECT id FROM public.enterprise WHERE short_name = 'T143'), true,
    (SELECT id FROM public.status WHERE code = 'active'),
    (SELECT id FROM auth.user LIMIT 1), 'Test 143 legal unit'
RETURNING id \gset lu_

INSERT INTO public.establishment (valid_from, name, legal_unit_id, primary_for_legal_unit, status_id, edit_by_user_id, edit_comment)
SELECT '2020-01-01'::date, 'T143 Establishment', :lu_id, true,
    (SELECT id FROM public.status WHERE code = 'active'),
    (SELECT id FROM auth.user LIMIT 1), 'Test 143 establishment'
RETURNING id \gset es_

INSERT INTO public.power_group (ident, name, edit_by_user_id, edit_comment)
SELECT 'PG-T143', 'T143 Power Group', id, 'Test 143 power group' FROM auth.user LIMIT 1
RETURNING id \gset pg_

INSERT INTO public.tag (path, name) VALUES ('t143', 'T143 Tag') RETURNING id \gset tag_

-- One addendum row per addendum table: an identifier on the legal unit, a
-- tag on the establishment, a note on the power group.
INSERT INTO public.external_ident (type_id, ident, legal_unit_id, edit_by_user_id, edit_comment)
SELECT (SELECT id FROM public.external_ident_type WHERE code = 'stat_ident'), 'T143-LU', :lu_id, id, 'lu ident' FROM auth.user LIMIT 1;

INSERT INTO public.tag_for_unit (tag_id, establishment_id, edit_by_user_id, edit_comment)
SELECT :tag_id, :es_id, id, 'es tag' FROM auth.user LIMIT 1;

INSERT INTO public.unit_notes (power_group_id, notes, edit_by_user_id, edit_comment)
SELECT :pg_id, 't143 pg note', id, 'pg note' FROM auth.user LIMIT 1;

SELECT 'fixtures committed' AS step,
    (SELECT count(*) FROM public.external_ident WHERE ident LIKE 'T143-%') AS external_idents,
    (SELECT count(*) FROM public.tag_for_unit WHERE tag_id = :tag_id) AS tags,
    (SELECT count(*) FROM public.unit_notes WHERE notes LIKE 't143 %') AS notes;

-- \! shell commands do not interpolate psql variables, so the (pid-suffixed)
-- database name travels through a file the shell reads back.
\pset tuples_only on
\pset format unaligned
\o /statbus/tmp/143_dbname.txt
SELECT current_database();
\o
\pset tuples_only off
\pset format aligned

\! sh -c 'db=$(cat /statbus/tmp/143_dbname.txt); pg_dump -U postgres -Fc -f /statbus/tmp/143_dump_restore.dump "$db" && echo DUMP_OK || echo DUMP_FAILED'
\! sh -c "dropdb -U postgres --if-exists test_143_restore && createdb -U postgres test_143_restore && echo RESTORE_DB_READY || echo RESTORE_DB_FAILED"
\! sh -c "pg_restore -U postgres --single-transaction --exit-on-error -d test_143_restore /statbus/tmp/143_dump_restore.dump && echo RESTORE_OK || echo RESTORE_FAILED"
\! sh -c "psql -U postgres -d test_143_restore -tAc 'SELECT sql_saga.check_integrity()' >/dev/null && echo INTEGRITY_OK || echo INTEGRITY_FAILED"
\! sh -c "psql -U postgres -d test_143_restore -tAc \"SELECT 'restored counts: ' || (SELECT count(*) FROM public.external_ident WHERE ident LIKE 'T143-%') || ' idents, ' || (SELECT count(*) FROM public.tag_for_unit tf JOIN public.tag t ON t.id = tf.tag_id WHERE t.path = 't143') || ' tags, ' || (SELECT count(*) FROM public.unit_notes WHERE notes LIKE 't143 %') || ' notes'\""
\! sh -c "dropdb -U postgres --if-exists test_143_restore && rm -f /statbus/tmp/143_dump_restore.dump && echo CLEANUP_OK || echo CLEANUP_FAILED"

\echo "--- An insert referencing a missing legal unit is refused ---"
BEGIN;
SAVEPOINT before_orphan;
INSERT INTO public.external_ident (type_id, ident, legal_unit_id, edit_by_user_id)
SELECT (SELECT id FROM public.external_ident_type WHERE code = 'stat_ident'), 'T143-ORPHAN-LU', -143001, id FROM auth.user LIMIT 1;
ROLLBACK TO SAVEPOINT before_orphan;

\echo "--- Deleting the legal unit while its addendum exists is refused ---"
\echo "--- (establishment and its tag removed first, so the legal unit's own addendum is what refuses) ---"
SAVEPOINT before_lu_delete;
DELETE FROM public.tag_for_unit WHERE establishment_id = :es_id;
DELETE FROM public.establishment WHERE id = :es_id;
DELETE FROM public.legal_unit WHERE id = :lu_id;
ROLLBACK TO SAVEPOINT before_lu_delete;

\echo "--- Deleting the power group removes its unit_notes row ---"
SELECT count(*) AS notes_before FROM public.unit_notes WHERE power_group_id = :pg_id;
DELETE FROM public.power_group WHERE id = :pg_id;
SELECT count(*) AS notes_after FROM public.unit_notes WHERE power_group_id = :pg_id;
COMMIT;

\set ECHO all
\echo "=== Test 143 done ==="
