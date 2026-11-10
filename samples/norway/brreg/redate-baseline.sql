-- STATBUS-600: re-date a BRREG baseline to its real snapshot date.
--
-- rune's only BRREG import loaded the files BRREG built about 2025-08-07 with
-- valid_from 2026-11-07. This moves every record that starts on :old_date to
-- start on :new_date instead, in one transaction, so the change feed can be
-- replayed month by month from the real date (owner, STATBUS-600 Q10).
--
-- Each base table's sql_saga sync trigger keeps valid_range in step with
-- valid_from. Records starting on any other date are left alone; so are
-- births and deaths, which carry their own dates. The derived tables
-- (statistical_unit, history, facets) are rebuilt afterwards by
-- public.recalculate_all().
--
-- Usage: ./sb psql -v old_date=2026-11-07 -v new_date=2025-08-07 < samples/norway/brreg/redate-baseline.sql
\set ON_ERROR_STOP on
BEGIN;

SELECT set_config('statbus.redate_old', :'old_date', true), set_config('statbus.redate_new', :'new_date', true);

-- A record that starts on old_date must not also have a record of the same unit
-- that starts between new_date and old_date; then moving its start would overlap.
DO $$
DECLARE
    v_old date := current_setting('statbus.redate_old')::date;
    v_new date := current_setting('statbus.redate_new')::date;
    v_table text;
    v_conflicts bigint;
BEGIN
    IF v_new >= v_old THEN
        RAISE EXCEPTION 'new_date % must be before old_date %', v_new, v_old;
    END IF;
    FOREACH v_table IN ARRAY ARRAY['legal_unit', 'establishment', 'activity', 'location', 'contact',
                                   'stat_for_unit', 'person_for_unit', 'legal_relationship'] LOOP
        EXECUTE format('SELECT count(*) FROM public.%I WHERE valid_from > $1 AND valid_from < $2', v_table)
            INTO v_conflicts USING v_new, v_old;
        IF v_conflicts > 0 THEN
            RAISE EXCEPTION '%: % records start between % and %; re-dating would overlap them',
                v_table, v_conflicts, v_new, v_old;
        END IF;
    END LOOP;
END $$;

-- Children before parents would break the temporal foreign keys mid-statement;
-- they are deferrable, so defer them to the commit.
SET CONSTRAINTS ALL DEFERRED;

\echo 'records re-dated per table'
WITH
  lu AS (UPDATE public.legal_unit SET valid_from = :'new_date' WHERE valid_from = :'old_date' RETURNING 1),
  es AS (UPDATE public.establishment SET valid_from = :'new_date' WHERE valid_from = :'old_date' RETURNING 1),
  ac AS (UPDATE public.activity SET valid_from = :'new_date' WHERE valid_from = :'old_date' RETURNING 1),
  lo AS (UPDATE public.location SET valid_from = :'new_date' WHERE valid_from = :'old_date' RETURNING 1),
  co AS (UPDATE public.contact SET valid_from = :'new_date' WHERE valid_from = :'old_date' RETURNING 1),
  st AS (UPDATE public.stat_for_unit SET valid_from = :'new_date' WHERE valid_from = :'old_date' RETURNING 1),
  pe AS (UPDATE public.person_for_unit SET valid_from = :'new_date' WHERE valid_from = :'old_date' RETURNING 1),
  lr AS (UPDATE public.legal_relationship SET valid_from = :'new_date' WHERE valid_from = :'old_date' RETURNING 1)
SELECT (SELECT count(*) FROM lu) AS legal_unit, (SELECT count(*) FROM es) AS establishment,
       (SELECT count(*) FROM ac) AS activity, (SELECT count(*) FROM lo) AS location,
       (SELECT count(*) FROM co) AS contact, (SELECT count(*) FROM st) AS stat_for_unit,
       (SELECT count(*) FROM pe) AS person_for_unit, (SELECT count(*) FROM lr) AS legal_relationship;

-- The import jobs that loaded the baseline now say the same date as their records.
UPDATE public.import_job SET default_valid_from = :'new_date' WHERE default_valid_from = :'old_date';

\echo 'records still starting on the old date (all 0)'
SELECT (SELECT count(*) FROM public.legal_unit WHERE valid_from = :'old_date') AS legal_unit,
       (SELECT count(*) FROM public.establishment WHERE valid_from = :'old_date') AS establishment,
       (SELECT count(*) FROM public.activity WHERE valid_from = :'old_date') AS activity,
       (SELECT count(*) FROM public.location WHERE valid_from = :'old_date') AS location,
       (SELECT count(*) FROM public.stat_for_unit WHERE valid_from = :'old_date') AS stat_for_unit,
       (SELECT count(*) FROM public.legal_relationship WHERE valid_from = :'old_date') AS legal_relationship;
COMMIT;

\echo 'rebuild the derived tables'
SELECT public.recalculate_all();
