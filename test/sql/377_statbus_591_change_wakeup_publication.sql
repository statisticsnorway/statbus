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
CREATE TEMP TABLE t377_ids(id integer);

-- A domain write logs its exact changed IDs and publishes in the same statement:
-- durable pending flag, one pending collector.
WITH inserted AS (
    INSERT INTO public.enterprise(short_name, edit_by_user_id)
    SELECT 'T377 first', id FROM auth."user" WHERE email = 'test.admin@statbus.org'
    RETURNING id
) INSERT INTO t377_ids SELECT id FROM inserted;
\echo Write: exact log, pending flag, one collector
SELECT (SELECT count(*) FROM worker.base_change_log) = 1,
       (SELECT range_agg(int4range(id,id,'[]')) FROM t377_ids) =
           (SELECT enterprise_ids FROM worker.base_change_log),
       (SELECT has_pending FROM worker.base_change_log_has_pending),
       (SELECT count(*) FROM worker.tasks WHERE command='collect_changes' AND state='pending') = 1;

-- A second write while the flag is already TRUE keeps it TRUE and deduplicates
-- onto the one pending collector. Lock ordering against a running collector is
-- proven with two connections in tmp/serial-rc/lock-race.sh.
WITH inserted AS (
    INSERT INTO public.enterprise(short_name, edit_by_user_id)
    SELECT 'T377 second', id FROM auth."user" WHERE email = 'test.admin@statbus.org'
    RETURNING id
) INSERT INTO t377_ids SELECT id FROM inserted;
\echo Write with flag already TRUE: both IDs logged, pending flag, one collector
SELECT (SELECT count(*) FROM worker.base_change_log) = 2,
       (SELECT range_agg(int4range(id,id,'[]')) FROM t377_ids) =
           (SELECT range_agg(r) FROM worker.base_change_log CROSS JOIN LATERAL unnest(enterprise_ids) r),
       (SELECT has_pending FROM worker.base_change_log_has_pending),
       (SELECT count(*) FROM worker.tasks WHERE command='collect_changes' AND state='pending') = 1;

-- A statement that changes no rows logs nothing and publishes nothing.
DELETE FROM worker.tasks;
DELETE FROM worker.base_change_log;
UPDATE worker.base_change_log_has_pending SET has_pending=false;
UPDATE public.enterprise SET short_name=short_name WHERE false;
\echo Empty statement: no log, false pending flag, no collector
SELECT (SELECT count(*) FROM worker.base_change_log) = 0,
       (SELECT has_pending FROM worker.base_change_log_has_pending) = false,
       (SELECT count(*) FROM worker.tasks WHERE command='collect_changes') = 0;

-- Exercise the real specialized trigger functions with transition-table fixtures.
-- Their scheduling guards are independent of domain FK/temporal constraints.
CREATE TEMP TABLE t377_guard_results(producer text, scenario text, correct boolean);
CREATE PROCEDURE pg_temp.t377_check_guard(p_producer text,p_scenario text,p_expected boolean)
LANGUAGE plpgsql AS $test$
BEGIN
    INSERT INTO t377_guard_results
    SELECT p_producer,p_scenario,
        (SELECT has_pending FROM worker.base_change_log_has_pending)=p_expected
        AND (SELECT count(*) FROM worker.tasks WHERE command='collect_changes' AND state='pending')=p_expected::int
        AND (SELECT count(*)=0 FROM worker.base_change_log);
    DELETE FROM worker.tasks;
    UPDATE worker.base_change_log_has_pending SET has_pending=false;
END $test$;
DO $test$
DECLARE producer text; table_name text; column_name text;
BEGIN
    FOREACH producer IN ARRAY ARRAY['legal_relationship','power_root'] LOOP
        table_name := 't377_guard_'||producer;
        column_name := CASE producer WHEN 'legal_relationship' THEN 'derived_power_group_id' ELSE 'custom_root_legal_unit_id' END;
        EXECUTE format('CREATE TEMP TABLE %I(%I integer)',table_name,column_name);
        EXECUTE format('CREATE TRIGGER t377_insert AFTER INSERT ON %I REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION worker.ensure_collect_changes_for_%s()',table_name,producer);
        EXECUTE format('CREATE TRIGGER t377_update AFTER UPDATE ON %I REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION worker.ensure_collect_changes_for_%s()',table_name,producer);
        EXECUTE format('CREATE TRIGGER t377_delete AFTER DELETE ON %I FOR EACH STATEMENT EXECUTE FUNCTION worker.ensure_collect_changes_for_%s()',table_name,producer);
        EXECUTE format('INSERT INTO %I VALUES(NULL)',table_name);
        CALL pg_temp.t377_check_guard(p_producer => producer, p_scenario => 'insert_null', p_expected => false);
        EXECUTE format('UPDATE %I SET %I=NULL',table_name,column_name);
        CALL pg_temp.t377_check_guard(p_producer => producer, p_scenario => 'update_null', p_expected => false);
        EXECUTE format('INSERT INTO %I SELECT NULL::integer WHERE false',table_name);
        CALL pg_temp.t377_check_guard(p_producer => producer, p_scenario => 'insert_empty', p_expected => false);
        EXECUTE format('UPDATE %I SET %I=1 WHERE false',table_name,column_name);
        CALL pg_temp.t377_check_guard(p_producer => producer, p_scenario => 'update_empty', p_expected => false);
        EXECUTE format('UPDATE %I SET %I=1',table_name,column_name);
        CALL pg_temp.t377_check_guard(p_producer => producer, p_scenario => 'update_qualified', p_expected => true);
        EXECUTE format('INSERT INTO %I VALUES(2)',table_name);
        CALL pg_temp.t377_check_guard(p_producer => producer, p_scenario => 'insert_qualified', p_expected => true);
        EXECUTE format('DELETE FROM %I WHERE false',table_name);
        CALL pg_temp.t377_check_guard(p_producer => producer, p_scenario => 'delete_empty_unconditional', p_expected => true);
        EXECUTE format('UPDATE %I SET %I=NULL',table_name,column_name);
        CALL pg_temp.t377_check_guard(p_producer => producer, p_scenario => 'update_cleared', p_expected => false);
        EXECUTE format('DELETE FROM %I',table_name);
        CALL pg_temp.t377_check_guard(p_producer => producer, p_scenario => 'delete_null_unconditional', p_expected => true);
    END LOOP;
END $test$;
\echo Specialized producers: nine exact guard cases each, including unconditional empty DELETE
SELECT producer,count(*),bool_and(correct) FROM t377_guard_results GROUP BY producer ORDER BY producer;

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
SELECT '2020-01-01','infinity','T377 region unit',
    (SELECT id FROM public.enterprise WHERE short_name='T377 first'),true,
    (SELECT id FROM public.status WHERE code='active'),
    (SELECT id FROM auth."user" WHERE email='test.admin@statbus.org');
INSERT INTO public.location(valid_from,valid_until,type,region_id,region_version_id,country_id,legal_unit_id,edit_by_user_id)
SELECT '2020-01-01','infinity','physical',r.id,r.version_id,c.id,lu.id,u.id
FROM (SELECT id,version_id FROM public.region ORDER BY path LIMIT 1) r
CROSS JOIN public.country c CROSS JOIN public.legal_unit lu CROSS JOIN auth."user" u
WHERE c.iso_2='NO' AND lu.name='T377 region unit' AND u.email='test.admin@statbus.org';
DELETE FROM worker.tasks;
DELETE FROM worker.base_change_log;
UPDATE worker.base_change_log_has_pending SET has_pending=false;
UPDATE public.region SET name=name WHERE false;
UPDATE public.region SET name=name
WHERE id=(SELECT id FROM public.region WHERE id NOT IN(SELECT region_id FROM public.location) ORDER BY path LIMIT 1);
\echo Region with no affected locations: no log, no publication
SELECT (SELECT count(*) FROM worker.base_change_log)=0,
       (SELECT has_pending FROM worker.base_change_log_has_pending)=false,
       (SELECT count(*) FROM worker.tasks WHERE command='collect_changes')=0;
UPDATE public.region SET name=name WHERE id=(SELECT region_id FROM public.location WHERE legal_unit_id=(SELECT id FROM public.legal_unit WHERE name='T377 region unit'));
\echo Affected region: exact unit and validity log, pending flag, one collector
SELECT (SELECT count(*) FROM worker.base_change_log)=1,
       (SELECT legal_unit_ids=int4multirange(int4range(lu.id,lu.id,'[]'))
           AND valid_ranges=datemultirange(lu.valid_range)
        FROM worker.base_change_log CROSS JOIN public.legal_unit lu WHERE lu.name='T377 region unit'),
       (SELECT has_pending FROM worker.base_change_log_has_pending),
       (SELECT count(*) FROM worker.tasks WHERE command='collect_changes' AND state='pending')=1;
ROLLBACK;
