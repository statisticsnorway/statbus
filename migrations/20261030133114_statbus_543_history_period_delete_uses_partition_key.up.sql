-- Migration 20261030133114: STATBUS-543 history period DELETE uses the partition keys
--
-- derive_statistical_history_period deleted with lower(hash_partition) and
-- month IS NOT DISTINCT FROM, which no index covers: every year-month child
-- seq-scanned statistical_history (302k rows on dev, 144 ms; now 0.15 ms).
BEGIN;

CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_period(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_resolution public.history_resolution := (payload->>'resolution')::public.history_resolution;
    v_year integer := (payload->>'year')::integer;
    v_month integer := (payload->>'month')::integer;
    v_hash_partition int4range := NULLIF(payload->>'hash_partition', '')::int4range;
    v_row_count bigint;
BEGIN
    RAISE DEBUG 'Processing statistical_history for resolution=%, year=%, month=%, hash_partition=%',
                 v_resolution, v_year, v_month, v_hash_partition;

    IF v_hash_partition IS NOT NULL THEN
        -- Stored per-slot rows hold singleton ranges [s,s+1). Ranges sort by
        -- lower bound, so comparing the column with the singleton ranges of
        -- the spawn's first and past-the-end slots selects exactly the rows
        -- whose slot lies in the spawn's range, and lets the partition unique
        -- keys (hash_partition, resolution, year[, month], unit_type) bound
        -- the scan. month is matched by equality, or IS NULL for the year
        -- resolution, so the month key can use it (STATBUS-543: the former
        -- lower(hash_partition) and month IS NOT DISTINCT FROM filters
        -- scanned the whole table for every year-month child).
        DELETE FROM public.statistical_history
         WHERE resolution = v_resolution
           AND year = v_year
           AND ((v_month IS NULL AND month IS NULL) OR month = v_month)
           AND hash_partition >= int4range(lower(v_hash_partition), lower(v_hash_partition) + 1)
           AND hash_partition <  int4range(upper(v_hash_partition), upper(v_hash_partition) + 1);

        INSERT INTO public.statistical_history
        SELECT h.*
        FROM public.statistical_history_def(v_resolution, v_year, v_month, v_hash_partition) AS h;
        GET DIAGNOSTICS v_row_count := ROW_COUNT;
    ELSE
        -- Manual escape hatch: full-period rebuild. The DELETE drops the
        -- `hash_partition IS NULL` filter (vs rc.42), wiping every row for
        -- the period — both the NULL summary and any per-slot rows. The
        -- INSERT then writes fresh per-slot rows from def(...). Reduce
        -- rebuilds the NULL summary on its next run.
        DELETE FROM public.statistical_history
         WHERE resolution = v_resolution
           AND year = v_year
           AND month IS NOT DISTINCT FROM v_month;

        INSERT INTO public.statistical_history
        SELECT h.*
        FROM public.statistical_history_def(v_resolution, v_year, v_month) AS h;
        GET DIAGNOSTICS v_row_count := ROW_COUNT;
    END IF;

    RAISE DEBUG 'Completed statistical_history for resolution=%, year=%, month=%, hash_partition=%',
                 v_resolution, v_year, v_month, v_hash_partition;

    p_info := jsonb_build_object('rows_inserted', v_row_count);
END;
$procedure$
;

END;
