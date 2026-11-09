\set ECHO none
\set QUIET 1
BEGIN;
\i test/setup.sql
\set ECHO none
\set QUIET 1
\pset format unaligned
\pset tuples_only on
SET client_min_messages = error;
RESET ROLE;
DELETE FROM worker.tasks;
DELETE FROM worker.base_change_log;
UPDATE worker.base_change_log_has_pending SET has_pending = false;
CREATE TEMP TABLE t381_ids(id integer);
CREATE TEMP TABLE t381_scopes(name text PRIMARY KEY, previous jsonb);

-- The actual statement trigger must retain the exact changed domain IDs while
-- an explicit import scope postpones only its wakeup, not the log append.
INSERT INTO t381_scopes VALUES ('outer', worker.begin_deferred_base_change_wakeup());
WITH inserted AS (
    INSERT INTO public.enterprise(short_name, edit_by_user_id)
    SELECT 'T381 first', id FROM auth."user" WHERE email = 'test.admin@statbus.org'
    RETURNING id
) INSERT INTO t381_ids SELECT id FROM inserted;
\echo Deferred write: exact immediate log, unpublished wakeup
SELECT (SELECT count(*) FROM worker.base_change_log) = 1,
       (SELECT range_agg(int4range(id,id,'[]')) FROM t381_ids) =
           (SELECT enterprise_ids FROM worker.base_change_log),
       (SELECT has_pending FROM worker.base_change_log_has_pending) = false,
       (SELECT count(*) FROM worker.tasks WHERE command='collect_changes') = 0;

INSERT INTO t381_scopes VALUES ('nested', worker.begin_deferred_base_change_wakeup());
WITH inserted AS (
    INSERT INTO public.enterprise(short_name, edit_by_user_id)
    SELECT 'T381 second', id FROM auth."user" WHERE email = 'test.admin@statbus.org'
    RETURNING id
) INSERT INTO t381_ids SELECT id FROM inserted;
DO $test$ BEGIN
    PERFORM worker.end_deferred_base_change_wakeup((SELECT previous FROM t381_scopes WHERE name='nested'));
END $test$;
\echo Nested scope: both immediate log rows, outer dirty, no publication
SELECT (SELECT count(*) FROM worker.base_change_log) = 2,
       (SELECT range_agg(int4range(id,id,'[]')) FROM t381_ids) =
           (SELECT range_agg(r) FROM worker.base_change_log CROSS JOIN LATERAL unnest(enterprise_ids) r),
       current_setting('statbus.defer_base_change_wakeup') = 'on',
       current_setting('statbus.base_change_wakeup_dirty') = 'on',
       (SELECT has_pending FROM worker.base_change_log_has_pending) = false;

-- A failing nested scope rolls back its own domain row and settings while
-- preserving the dirty changes its caller already owns.
SAVEPOINT t381_failed;
INSERT INTO t381_scopes VALUES ('failed', worker.begin_deferred_base_change_wakeup());
INSERT INTO public.enterprise(short_name,edit_by_user_id)
SELECT 'T381 rollback',id FROM auth."user" WHERE email='test.admin@statbus.org';
ROLLBACK TO SAVEPOINT t381_failed;
\echo Nested rollback: caller dirty changes and exact prior domain preserved
SELECT current_setting('statbus.defer_base_change_wakeup') = 'on',
       current_setting('statbus.base_change_wakeup_dirty') = 'on',
       (SELECT count(*) FROM public.enterprise WHERE short_name LIKE 'T381 %') = 2,
       (SELECT count(*) FROM worker.base_change_log) = 2;
DO $test$ BEGIN
    PERFORM worker.end_deferred_base_change_wakeup((SELECT previous FROM t381_scopes WHERE name='outer'));
END $test$;
\echo Outermost tail: flag, one pending collector, caller settings restored
SELECT (SELECT has_pending FROM worker.base_change_log_has_pending),
       (SELECT count(*) FROM worker.tasks WHERE command='collect_changes' AND state='pending') = 1,
       NULLIF(current_setting('statbus.defer_base_change_wakeup',true),'') IS NULL,
       NULLIF(current_setting('statbus.base_change_wakeup_dirty',true),'') IS NULL;

DELETE FROM worker.tasks;
DELETE FROM worker.base_change_log;
UPDATE worker.base_change_log_has_pending SET has_pending=false;
INSERT INTO t381_scopes VALUES ('empty',worker.begin_deferred_base_change_wakeup());
UPDATE public.enterprise SET short_name=short_name WHERE false;
DO $test$ BEGIN
    PERFORM worker.end_deferred_base_change_wakeup((SELECT previous FROM t381_scopes WHERE name='empty'));
END $test$;
\echo Empty scope: unchanged log, false pending flag, empty collector queue
SELECT (SELECT count(*) FROM worker.base_change_log) = 0,
       (SELECT has_pending FROM worker.base_change_log_has_pending) = false,
       (SELECT count(*) FROM worker.tasks WHERE command='collect_changes') = 0;

-- Ordinary writes outside import scopes retain their immediate wakeup behavior.
WITH inserted AS (
    INSERT INTO public.enterprise(short_name,edit_by_user_id)
    SELECT 'T381 ordinary',id FROM auth."user" WHERE email='test.admin@statbus.org'
    RETURNING id
) INSERT INTO t381_ids SELECT id FROM inserted;
\echo Ordinary write: immediate log, pending flag, one collector
SELECT (SELECT count(*) FROM worker.base_change_log) = 1,
       (SELECT has_pending FROM worker.base_change_log_has_pending),
       (SELECT count(*) FROM worker.tasks WHERE command='collect_changes' AND state='pending') = 1;

-- A caller's prior settings survive a clean nested scope, including a dirty
-- outer scope that this callee did not itself change.
DO $test$
DECLARE previous jsonb;
BEGIN
    PERFORM set_config('statbus.defer_base_change_wakeup','on',true);
    PERFORM set_config('statbus.base_change_wakeup_dirty','on',true);
    previous := worker.begin_deferred_base_change_wakeup();
    PERFORM worker.end_deferred_base_change_wakeup(previous);
END $test$;
\echo Clean nested scope: caller scope and dirty state preserved
SELECT current_setting('statbus.defer_base_change_wakeup')='on',
       current_setting('statbus.base_change_wakeup_dirty')='on';
-- Exercise the real specialized trigger functions with transition-table fixtures.
-- Their scheduling guards are independent of domain FK/temporal constraints.
DO $test$ BEGIN
    PERFORM set_config('statbus.defer_base_change_wakeup','on',true);
    PERFORM set_config('statbus.base_change_wakeup_dirty','off',true);
END $test$;
DELETE FROM worker.tasks;
DELETE FROM worker.base_change_log;
UPDATE worker.base_change_log_has_pending SET has_pending=false;
CREATE TEMP TABLE t381_guard_results(producer text, scenario text, correct boolean);
CREATE PROCEDURE pg_temp.t381_check_guard(p_producer text,p_scenario text,p_expected boolean)
LANGUAGE plpgsql AS $test$
BEGIN
    INSERT INTO t381_guard_results
    SELECT p_producer,p_scenario,
        (current_setting('statbus.base_change_wakeup_dirty')='on')=p_expected
        AND (SELECT has_pending=false FROM worker.base_change_log_has_pending)
        AND (SELECT count(*)=0 FROM worker.tasks WHERE command='collect_changes')
        AND (SELECT count(*)=0 FROM worker.base_change_log);
    PERFORM set_config('statbus.base_change_wakeup_dirty','off',true);
END $test$;
DO $test$
DECLARE producer text; table_name text; column_name text;
BEGIN
    FOREACH producer IN ARRAY ARRAY['legal_relationship','power_root'] LOOP
        table_name := 't381_guard_'||producer;
        column_name := CASE producer WHEN 'legal_relationship' THEN 'derived_power_group_id' ELSE 'custom_root_legal_unit_id' END;
        EXECUTE format('CREATE TEMP TABLE %I(%I integer)',table_name,column_name);
        EXECUTE format('CREATE TRIGGER t381_insert AFTER INSERT ON %I REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION worker.ensure_collect_changes_for_%s()',table_name,producer);
        EXECUTE format('CREATE TRIGGER t381_update AFTER UPDATE ON %I REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION worker.ensure_collect_changes_for_%s()',table_name,producer);
        EXECUTE format('CREATE TRIGGER t381_delete AFTER DELETE ON %I FOR EACH STATEMENT EXECUTE FUNCTION worker.ensure_collect_changes_for_%s()',table_name,producer);
        EXECUTE format('INSERT INTO %I VALUES(NULL)',table_name);
        CALL pg_temp.t381_check_guard(p_producer => producer, p_scenario => 'insert_null', p_expected => false);
        EXECUTE format('UPDATE %I SET %I=NULL',table_name,column_name);
        CALL pg_temp.t381_check_guard(p_producer => producer, p_scenario => 'update_null', p_expected => false);
        EXECUTE format('INSERT INTO %I SELECT NULL::integer WHERE false',table_name);
        CALL pg_temp.t381_check_guard(p_producer => producer, p_scenario => 'insert_empty', p_expected => false);
        EXECUTE format('UPDATE %I SET %I=1 WHERE false',table_name,column_name);
        CALL pg_temp.t381_check_guard(p_producer => producer, p_scenario => 'update_empty', p_expected => false);
        EXECUTE format('UPDATE %I SET %I=1',table_name,column_name);
        CALL pg_temp.t381_check_guard(p_producer => producer, p_scenario => 'update_qualified', p_expected => true);
        EXECUTE format('INSERT INTO %I VALUES(2)',table_name);
        CALL pg_temp.t381_check_guard(p_producer => producer, p_scenario => 'insert_qualified', p_expected => true);
        EXECUTE format('DELETE FROM %I WHERE false',table_name);
        CALL pg_temp.t381_check_guard(p_producer => producer, p_scenario => 'delete_empty_unconditional', p_expected => true);
        EXECUTE format('UPDATE %I SET %I=NULL',table_name,column_name);
        CALL pg_temp.t381_check_guard(p_producer => producer, p_scenario => 'update_cleared', p_expected => false);
        EXECUTE format('DELETE FROM %I',table_name);
        CALL pg_temp.t381_check_guard(p_producer => producer, p_scenario => 'delete_null_unconditional', p_expected => true);
    END LOOP;
END $test$;
\echo Specialized producers: nine exact guard cases each, including unconditional empty DELETE
SELECT producer,count(*),bool_and(correct) FROM t381_guard_results GROUP BY producer ORDER BY producer;
DO $test$ BEGIN
    PERFORM set_config('statbus.defer_base_change_wakeup','',true);
    PERFORM set_config('statbus.base_change_wakeup_dirty','',true);
END $test$;
DELETE FROM t381_guard_legal_relationship;
DELETE FROM t381_guard_power_root;
\echo Ordinary specialized DELETE: immediate publication without requiring a new log append
SELECT (SELECT has_pending FROM worker.base_change_log_has_pending),
       (SELECT count(*) FROM worker.tasks WHERE command='collect_changes' AND state='pending')=1,
       (SELECT count(*) FROM worker.base_change_log)=0;

-- Region metadata changes log the exact real units and validity ranges reached
-- through locations. Metadata changes without affected locations remain no-ops.
CALL test.set_user_from_email('test.admin@statbus.org');
\o /dev/null
\i samples/norway/getting-started.sql
\o
\set ECHO none
\set QUIET 1
RESET ROLE;
INSERT INTO public.legal_unit(valid_from,valid_until,name,enterprise_id,primary_for_enterprise,status_id,edit_by_user_id)
SELECT '2020-01-01','infinity','T381 region unit',
    (SELECT id FROM public.enterprise WHERE short_name='T381 first'),true,
    (SELECT id FROM public.status WHERE code='active'),
    (SELECT id FROM auth."user" WHERE email='test.admin@statbus.org');
INSERT INTO public.location(valid_from,valid_until,type,region_id,region_version_id,country_id,legal_unit_id,edit_by_user_id)
SELECT '2020-01-01','infinity','physical',r.id,r.version_id,c.id,lu.id,u.id
FROM (SELECT id,version_id FROM public.region ORDER BY path LIMIT 1) r
CROSS JOIN public.country c CROSS JOIN public.legal_unit lu CROSS JOIN auth."user" u
WHERE c.iso_2='NO' AND lu.name='T381 region unit' AND u.email='test.admin@statbus.org';
DELETE FROM worker.tasks;
DELETE FROM worker.base_change_log;
UPDATE worker.base_change_log_has_pending SET has_pending=false;
INSERT INTO t381_scopes VALUES('region',worker.begin_deferred_base_change_wakeup());
UPDATE public.region SET name=name WHERE false;
UPDATE public.region SET name=name
WHERE id=(SELECT id FROM public.region WHERE id NOT IN(SELECT region_id FROM public.location) ORDER BY path LIMIT 1);
\echo Region no affected locations: no request, no log, no publication
SELECT current_setting('statbus.base_change_wakeup_dirty')='off',
       (SELECT count(*) FROM worker.base_change_log)=0,
       (SELECT has_pending FROM worker.base_change_log_has_pending)=false,
       (SELECT count(*) FROM worker.tasks WHERE command='collect_changes')=0;
UPDATE public.region SET name=name WHERE id=(SELECT region_id FROM public.location WHERE legal_unit_id=(SELECT id FROM public.legal_unit WHERE name='T381 region unit'));
\echo Affected region: exact immediate unit and validity log, deferred wakeup
SELECT current_setting('statbus.base_change_wakeup_dirty')='on',
       (SELECT count(*) FROM worker.base_change_log)=1,
       (SELECT legal_unit_ids=int4multirange(int4range(lu.id,lu.id,'[]'))
           AND valid_ranges=datemultirange(lu.valid_range)
        FROM worker.base_change_log CROSS JOIN public.legal_unit lu WHERE lu.name='T381 region unit'),
       (SELECT has_pending FROM worker.base_change_log_has_pending)=false,
       (SELECT count(*) FROM worker.tasks WHERE command='collect_changes')=0;
DO $test$ BEGIN
    PERFORM worker.end_deferred_base_change_wakeup((SELECT previous FROM t381_scopes WHERE name='region'));
END $test$;
\echo Region scope tail: pending witness and one collector
SELECT (SELECT has_pending FROM worker.base_change_log_has_pending),
       (SELECT count(*) FROM worker.tasks WHERE command='collect_changes' AND state='pending')=1;
DELETE FROM worker.tasks;
DELETE FROM worker.base_change_log;
UPDATE worker.base_change_log_has_pending SET has_pending=false;
UPDATE public.region SET name=name WHERE id=(SELECT region_id FROM public.location WHERE legal_unit_id=(SELECT id FROM public.legal_unit WHERE name='T381 region unit'));
\echo Ordinary region write: immediate exact log and wakeup
SELECT (SELECT count(*) FROM worker.base_change_log)=1,
       (SELECT has_pending FROM worker.base_change_log_has_pending),
       (SELECT count(*) FROM worker.tasks WHERE command='collect_changes' AND state='pending')=1;
ROLLBACK;
