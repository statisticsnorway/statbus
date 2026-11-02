-- Migration 20261102151943: STATBUS-558 facet reduces scoped to changed and removed combinations
--
-- Restores the design of 20260324232001 (March 2026), which 20260429233218
-- (April) replaced by a global MERGE after a demo over-count. STATBUS-558
-- reproduced that over-count: deleted units' hash slots were never marked
-- dirty (fixed 20260520204526), and the global MERGE over-counted the same
-- way, since the stale rows sat in the per-slot cache it sums. The global
-- MERGE re-aggregated the whole cache every cycle: 46 s of a 129 s selection
-- import, and the step that ran out of memory at 4 GiB (STATBUS-555).
--
-- The removed part is captured where it is removed: each per-slot child
-- already deletes its slice before rewriting it, so it records every facet
-- combination whose partial rows differ between the old and the new slice.
-- The reduce then recomputes only those combinations, and deletes the ones
-- left without support.
BEGIN;

CREATE UNLOGGED TABLE worker.statistical_unit_facet_changed (
    valid_from                     date,
    valid_to                       date,
    valid_until                    date,
    unit_type                      public.statistical_unit_type,
    physical_region_path           public.ltree,
    primary_activity_category_path public.ltree,
    sector_path                    public.ltree,
    legal_form_id                  integer,
    physical_country_id            integer,
    status_id                      integer,
    UNIQUE NULLS NOT DISTINCT (valid_from, valid_to, valid_until, unit_type,
        physical_region_path, primary_activity_category_path, sector_path,
        legal_form_id, physical_country_id, status_id)
);
COMMENT ON TABLE worker.statistical_unit_facet_changed IS
'The public.statistical_unit_facet combinations whose rows in public.statistical_unit_facet_staging changed since the last worker.statistical_unit_facet_reduce: added, altered or removed. worker.derive_statistical_unit_facet_partition records them when it rewrites a slice in dirty mode, comparing the slice before and after. The reduce recomputes exactly these combinations, deletes the ones without support left, and empties the table. A combination recorded twice, or left over from an interrupted cycle, is only recomputed again, so the table may over-state but never miss a change.';

CREATE UNLOGGED TABLE worker.statistical_history_facet_changed (
    resolution                       public.history_resolution,
    year                             integer,
    month                            integer,
    unit_type                        public.statistical_unit_type,
    primary_activity_category_path   public.ltree,
    secondary_activity_category_path public.ltree,
    sector_path                      public.ltree,
    legal_form_id                    integer,
    physical_region_path             public.ltree,
    physical_country_id              integer,
    unit_size_id                     integer,
    status_id                        integer,
    UNIQUE NULLS NOT DISTINCT (resolution, year, month, unit_type,
        primary_activity_category_path, secondary_activity_category_path,
        sector_path, legal_form_id, physical_region_path,
        physical_country_id, unit_size_id, status_id)
);
COMMENT ON TABLE worker.statistical_history_facet_changed IS
'The public.statistical_history_facet combinations whose rows in public.statistical_history_facet_partitions changed since the last worker.statistical_history_facet_reduce: added, altered or removed. worker.derive_statistical_history_facet_period records them when it rewrites a period and slot range in dirty mode, comparing the slice before and after. The reduce recomputes exactly these combinations, deletes the ones without support left, and empties the table. A combination recorded twice, or left over from an interrupted cycle, is only recomputed again, so the table may over-state but never miss a change.';

CREATE OR REPLACE PROCEDURE worker.derive_statistical_unit_facet(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
    v_task_id bigint;
    v_dirty_hash_slots integer[];
    v_child_count integer := 0;
    v_partition_count_target integer;
    v_hash_partition_size integer;
    v_hash_partition int4range;
BEGIN
    v_partition_count_target := public.get_partition_count_target();
    v_hash_partition_size := GREATEST(1, 16384 / v_partition_count_target);

    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY id DESC LIMIT 1;

    SELECT array_agg(dirty_hash_slot ORDER BY dirty_hash_slot) INTO v_dirty_hash_slots
    FROM public.statistical_unit_facet_dirty_hash_slots;

    -- Full rebuild when the request covers all time, valid_from = -infinity
    -- and valid_until = infinity (STATBUS-538, see
    -- worker.enqueue_derive_statistical_unit_all), or when the staging cache
    -- is empty (fresh install, unclean shutdown of the UNLOGGED table). A
    -- full rebuild drops the whole cache first: slots whose units no longer
    -- exist are never dirty and would otherwise keep counting in the reduce.
    IF v_valid_from = '-infinity'::date AND v_valid_until = 'infinity'::date THEN
        DELETE FROM public.statistical_unit_facet_staging;
        v_dirty_hash_slots := NULL;
    ELSIF NOT EXISTS (SELECT 1 FROM public.statistical_unit_facet_staging LIMIT 1) THEN
        v_dirty_hash_slots := NULL;
    END IF;

    IF v_dirty_hash_slots IS NOT NULL THEN
        -- One child per partition range holding a dirty slot, the same ranges
        -- as the full rebuild (STATBUS-543).
        FOR v_hash_partition IN
            SELECT DISTINCT int4range(
                (d.slot / v_hash_partition_size) * v_hash_partition_size,
                LEAST((d.slot / v_hash_partition_size) * v_hash_partition_size + v_hash_partition_size, 16384)
            )
            FROM unnest(v_dirty_hash_slots) AS d(slot)
            ORDER BY 1
        LOOP
            PERFORM worker.spawn(
                p_command => 'derive_statistical_unit_facet_partition',
                p_payload => jsonb_build_object(
                    'command', 'derive_statistical_unit_facet_partition',
                    'hash_partition', v_hash_partition::text,
                    -- The child records the combinations its rewrite changes,
                    -- for the scoped reduce (worker.statistical_unit_facet_changed).
                    'record_changes', true
                ),
                p_parent_id => v_task_id
            );
            v_child_count := v_child_count + 1;
        END LOOP;
    ELSE
        FOR v_hash_partition IN
            SELECT DISTINCT int4range(
                (su.hash_slot / v_hash_partition_size) * v_hash_partition_size,
                LEAST((su.hash_slot / v_hash_partition_size) * v_hash_partition_size + v_hash_partition_size, 16384)
            )
            FROM public.statistical_unit AS su
            WHERE su.used_for_counting
            ORDER BY 1
        LOOP
            PERFORM worker.spawn(
                p_command => 'derive_statistical_unit_facet_partition',
                p_payload => jsonb_build_object(
                    'command', 'derive_statistical_unit_facet_partition',
                    'hash_partition', v_hash_partition::text
                ),
                p_parent_id => v_task_id
            );
            v_child_count := v_child_count + 1;
        END LOOP;
    END IF;

    -- mode tells worker.statistical_unit_facet_reduce how to reduce: 'dirty'
    -- recomputes the combinations the children recorded, 'full' the whole cache.
    p_info := jsonb_build_object(
        'child_count', v_child_count,
        'mode', CASE WHEN v_dirty_hash_slots IS NOT NULL THEN 'dirty' ELSE 'full' END);
END;
$procedure$
;

CREATE OR REPLACE PROCEDURE worker.derive_statistical_unit_facet_partition(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_hash_partition int4range := (payload->>'hash_partition')::int4range;
    -- Pre-compute explicit half-open bounds so the btree index on hash_slot is
    -- used. Range containment (<@) via a variable int4range is not planned as a
    -- btree scan at 2.2M rows; explicit bounds are. Mirrors the sibling
    -- derive_statistical_history_facet_period which passes scalar bounds.
    v_from  integer := lower(v_hash_partition);
    v_until integer := upper(v_hash_partition);
    v_record_changes boolean := COALESCE((payload->>'record_changes')::boolean, false);
    v_row_count bigint;
BEGIN
    -- The slice as it was, so the combinations this rewrite changes, including
    -- the removed ones, can be recorded for the scoped reduce.
    IF v_record_changes THEN
        IF to_regclass('pg_temp._unit_facet_slice_before') IS NOT NULL THEN DROP TABLE _unit_facet_slice_before; END IF;
        CREATE TEMP TABLE _unit_facet_slice_before ON COMMIT DROP AS
        SELECT * FROM public.statistical_unit_facet_staging
         WHERE hash_slot >= v_from AND hash_slot < v_until;
    END IF;

    DELETE FROM public.statistical_unit_facet_staging
     WHERE hash_slot >= v_from AND hash_slot < v_until;

    -- STATBUS-475: aggregate by the unit's EXISTENCE window within each record
    -- (canonical rule, STATBUS-460), not by the record window, so the
    -- drilldown's valid_from <= valid_on < valid_until counts existing units.
    INSERT INTO public.statistical_unit_facet_staging
    SELECT su.hash_slot,
           e.existence_from, e.existence_until - 1, e.existence_until, su.unit_type,
           su.physical_region_path, su.primary_activity_category_path,
           su.sector_path, su.legal_form_id, su.physical_country_id, su.status_id,
           COUNT(*)::integer,
           public.jsonb_stats_merge_agg(su.stats_summary)
    FROM public.statistical_unit AS su
    CROSS JOIN LATERAL (
        SELECT public.unit_existence_from(su.valid_from, su.birth_date) AS existence_from,
               public.unit_existence_until(su.valid_until, su.death_date) AS existence_until
    ) AS e
    WHERE su.used_for_counting
      AND su.hash_slot >= v_from AND su.hash_slot < v_until
      AND e.existence_from < e.existence_until
    GROUP BY su.hash_slot, e.existence_from, e.existence_until, su.unit_type,
             su.physical_region_path, su.primary_activity_category_path,
             su.sector_path, su.legal_form_id, su.physical_country_id, su.status_id;
    GET DIAGNOSTICS v_row_count := ROW_COUNT;

    -- A combination changed when any of its rows in the slice was added,
    -- altered or removed: the symmetric difference of before and after.
    -- Inserted in key order, so concurrent children wait on each other's
    -- uncommitted keys in the same order and cannot deadlock.
    IF v_record_changes THEN
        INSERT INTO worker.statistical_unit_facet_changed
        SELECT DISTINCT d.valid_from, d.valid_to, d.valid_until, d.unit_type,
               d.physical_region_path, d.primary_activity_category_path,
               d.sector_path, d.legal_form_id, d.physical_country_id, d.status_id
        FROM (
            (SELECT * FROM _unit_facet_slice_before
             EXCEPT ALL
             SELECT * FROM public.statistical_unit_facet_staging
              WHERE hash_slot >= v_from AND hash_slot < v_until)
            UNION ALL
            (SELECT * FROM public.statistical_unit_facet_staging
              WHERE hash_slot >= v_from AND hash_slot < v_until
             EXCEPT ALL
             SELECT * FROM _unit_facet_slice_before)
        ) AS d
        ORDER BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
        ON CONFLICT DO NOTHING;
    END IF;

    p_info := jsonb_build_object('rows_inserted', v_row_count);
END;
$procedure$
;

CREATE OR REPLACE PROCEDURE worker.statistical_unit_facet_reduce(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_dirty_hash_slots int[];
    v_row_count bigint;
    v_mode text;
    v_changed_count bigint;
BEGIN
    -- Read dirty hash slots for diagnostic logging.
    SELECT array_agg(dp.dirty_hash_slot)
      INTO v_dirty_hash_slots
      FROM public.statistical_unit_facet_dirty_hash_slots AS dp;

    -- Reduce as the sibling worker.derive_statistical_unit_facet derived: in
    -- 'dirty' mode its children recorded every changed combination, so only
    -- those are recomputed. Anything else (a full derive, or a direct CALL
    -- outside the pipeline) recomputes the whole cache.
    SELECT sibling.info->>'mode'
      INTO v_mode
      FROM worker.tasks AS self
      JOIN worker.tasks AS sibling
        ON sibling.parent_id = self.parent_id
       AND sibling.command = 'derive_statistical_unit_facet'
     WHERE self.state = 'processing' AND self.worker_pid = pg_backend_pid()
       AND self.command = 'statistical_unit_facet_reduce'
     ORDER BY self.id DESC, sibling.id DESC
     LIMIT 1;

    IF v_mode = 'dirty' THEN
        -- Each changed combination with its total over the whole cache, or
        -- NULL when no slot supports it any more.
        IF to_regclass('pg_temp._unit_facet_changed_total') IS NOT NULL THEN DROP TABLE _unit_facet_changed_total; END IF;
        CREATE TEMP TABLE _unit_facet_changed_total ON COMMIT DROP AS
        SELECT c.valid_from, c.valid_to, c.valid_until, c.unit_type,
               c.physical_region_path, c.primary_activity_category_path,
               c.sector_path, c.legal_form_id, c.physical_country_id, c.status_id,
               SUM(s.count)::BIGINT AS count,
               jsonb_stats_merge_agg(s.stats_summary) AS stats_summary
          FROM worker.statistical_unit_facet_changed AS c
          LEFT JOIN public.statistical_unit_facet_staging AS s
            ON s.valid_from = c.valid_from
           AND s.valid_to = c.valid_to
           AND COALESCE(s.valid_until, 'infinity'::date) = COALESCE(c.valid_until, 'infinity'::date)
           AND s.unit_type = c.unit_type
           AND COALESCE(s.physical_region_path::text, '') = COALESCE(c.physical_region_path::text, '')
           AND COALESCE(s.primary_activity_category_path::text, '') = COALESCE(c.primary_activity_category_path::text, '')
           AND COALESCE(s.sector_path::text, '') = COALESCE(c.sector_path::text, '')
           AND COALESCE(s.legal_form_id, -1) = COALESCE(c.legal_form_id, -1)
           AND COALESCE(s.physical_country_id, -1) = COALESCE(c.physical_country_id, -1)
           AND COALESCE(s.status_id, -1) = COALESCE(c.status_id, -1)
         GROUP BY c.valid_from, c.valid_to, c.valid_until, c.unit_type,
                  c.physical_region_path, c.primary_activity_category_path,
                  c.sector_path, c.legal_form_id, c.physical_country_id, c.status_id;

        MERGE INTO public.statistical_unit_facet AS target
        USING _unit_facet_changed_total AS source
           ON target.valid_from = source.valid_from
          AND target.valid_to = source.valid_to
          AND COALESCE(target.valid_until, 'infinity'::date) = COALESCE(source.valid_until, 'infinity'::date)
          AND target.unit_type = source.unit_type
          AND COALESCE(target.physical_region_path::text, '') = COALESCE(source.physical_region_path::text, '')
          AND COALESCE(target.primary_activity_category_path::text, '') = COALESCE(source.primary_activity_category_path::text, '')
          AND COALESCE(target.sector_path::text, '') = COALESCE(source.sector_path::text, '')
          AND COALESCE(target.legal_form_id, -1) = COALESCE(source.legal_form_id, -1)
          AND COALESCE(target.physical_country_id, -1) = COALESCE(source.physical_country_id, -1)
          AND COALESCE(target.status_id, -1) = COALESCE(source.status_id, -1)
        WHEN MATCHED AND source.count IS NULL
            THEN DELETE
        WHEN MATCHED AND (target.count <> source.count
                          OR target.stats_summary IS DISTINCT FROM source.stats_summary)
            THEN UPDATE SET count = source.count,
                            stats_summary = source.stats_summary
        WHEN NOT MATCHED BY TARGET AND source.count IS NOT NULL
            THEN INSERT (valid_from, valid_to, valid_until, unit_type,
                         physical_region_path, primary_activity_category_path,
                         sector_path, legal_form_id, physical_country_id, status_id,
                         count, stats_summary)
                 VALUES (source.valid_from, source.valid_to, source.valid_until, source.unit_type,
                         source.physical_region_path, source.primary_activity_category_path,
                         source.sector_path, source.legal_form_id, source.physical_country_id, source.status_id,
                         source.count, source.stats_summary);
        GET DIAGNOSTICS v_row_count := ROW_COUNT;
        SELECT count(*) INTO v_changed_count FROM _unit_facet_changed_total;

        TRUNCATE worker.statistical_unit_facet_changed;

        p_info := jsonb_build_object(
            'mode', 'dirty',
            'changed_combinations', v_changed_count,
            'dirty_hash_slots', to_jsonb(v_dirty_hash_slots),
            'rows_merged', v_row_count);
        RETURN;
    END IF;

    MERGE INTO public.statistical_unit_facet AS target
    USING (
        SELECT s.valid_from, s.valid_to, s.valid_until, s.unit_type,
               s.physical_region_path, s.primary_activity_category_path,
               s.sector_path, s.legal_form_id, s.physical_country_id, s.status_id,
               SUM(s.count)::BIGINT AS count,
               jsonb_stats_merge_agg(s.stats_summary) AS stats_summary
          FROM public.statistical_unit_facet_staging AS s
         GROUP BY s.valid_from, s.valid_to, s.valid_until, s.unit_type,
                  s.physical_region_path, s.primary_activity_category_path,
                  s.sector_path, s.legal_form_id, s.physical_country_id, s.status_id
    ) AS source
       ON target.valid_from = source.valid_from
      AND target.valid_to = source.valid_to
      AND COALESCE(target.valid_until, 'infinity'::date) = COALESCE(source.valid_until, 'infinity'::date)
      AND target.unit_type = source.unit_type
      AND COALESCE(target.physical_region_path::text, '') = COALESCE(source.physical_region_path::text, '')
      AND COALESCE(target.primary_activity_category_path::text, '') = COALESCE(source.primary_activity_category_path::text, '')
      AND COALESCE(target.sector_path::text, '') = COALESCE(source.sector_path::text, '')
      AND COALESCE(target.legal_form_id, -1) = COALESCE(source.legal_form_id, -1)
      AND COALESCE(target.physical_country_id, -1) = COALESCE(source.physical_country_id, -1)
      AND COALESCE(target.status_id, -1) = COALESCE(source.status_id, -1)
    WHEN MATCHED AND (target.count <> source.count
                      OR target.stats_summary IS DISTINCT FROM source.stats_summary)
        THEN UPDATE SET count = source.count,
                        stats_summary = source.stats_summary
    WHEN NOT MATCHED BY TARGET
        THEN INSERT (valid_from, valid_to, valid_until, unit_type,
                     physical_region_path, primary_activity_category_path,
                     sector_path, legal_form_id, physical_country_id, status_id,
                     count, stats_summary)
             VALUES (source.valid_from, source.valid_to, source.valid_until, source.unit_type,
                     source.physical_region_path, source.primary_activity_category_path,
                     source.sector_path, source.legal_form_id, source.physical_country_id, source.status_id,
                     source.count, source.stats_summary)
    WHEN NOT MATCHED BY SOURCE THEN DELETE;
    GET DIAGNOSTICS v_row_count := ROW_COUNT;

    -- The whole cache is reduced, which covers every recorded change.
    TRUNCATE worker.statistical_unit_facet_changed;

    p_info := jsonb_build_object(
        'mode', 'full',
        'dirty_hash_slots', to_jsonb(v_dirty_hash_slots),
        'rows_merged', v_row_count);
END;
$procedure$
;

CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_facet(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_valid_from date := COALESCE((payload->>'valid_from')::date, '-infinity'::date);
    v_valid_until date := COALESCE((payload->>'valid_until')::date, 'infinity'::date);
    v_task_id bigint;
    v_period record;
    v_dirty_hash_slots integer[];
    v_child_count integer := 0;
    v_partition_count_target integer;
    v_hash_partition_size integer;
    v_hash_partition int4range;
BEGIN
    v_partition_count_target := public.get_partition_count_target();
    v_hash_partition_size := GREATEST(1, 16384 / v_partition_count_target);

    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY id DESC LIMIT 1;

    SELECT array_agg(dirty_hash_slot ORDER BY dirty_hash_slot) INTO v_dirty_hash_slots
    FROM public.statistical_unit_facet_dirty_hash_slots;

    -- Full rebuild when the request covers all time, valid_from = -infinity
    -- and valid_until = infinity (STATBUS-538, see
    -- worker.enqueue_derive_statistical_unit_all), or when the per-slot cache
    -- is empty (fresh install). A full rebuild drops the whole cache first,
    -- so slots and periods without units do not survive into the reduce.
    IF (payload->>'valid_from')::date = '-infinity'::date
       AND (payload->>'valid_until')::date = 'infinity'::date THEN
        DELETE FROM public.statistical_history_facet_partitions;
        v_dirty_hash_slots := NULL;
    ELSIF NOT EXISTS (SELECT 1 FROM public.statistical_history_facet_partitions LIMIT 1) THEN
        v_dirty_hash_slots := NULL;
    END IF;

    FOR v_period IN
        SELECT resolution, year, month
        FROM public.get_statistical_history_periods(
            p_resolution => null::public.history_resolution,
            p_valid_from => v_valid_from,
            p_valid_until => v_valid_until
        )
    LOOP
        IF v_dirty_hash_slots IS NOT NULL THEN
            -- One child per partition range holding a dirty slot, the same
            -- ranges as the full rebuild (STATBUS-543).
            FOR v_hash_partition IN
                SELECT DISTINCT int4range(
                    (d.slot / v_hash_partition_size) * v_hash_partition_size,
                    LEAST((d.slot / v_hash_partition_size) * v_hash_partition_size + v_hash_partition_size, 16384)
                )
                FROM unnest(v_dirty_hash_slots) AS d(slot)
                ORDER BY 1
            LOOP
                PERFORM worker.spawn(
                    p_command => 'derive_statistical_history_facet_period',
                    p_payload => jsonb_build_object(
                        'command', 'derive_statistical_history_facet_period',
                        'resolution', v_period.resolution::text,
                        'year', v_period.year,
                        'month', v_period.month,
                        'hash_partition', v_hash_partition::text,
                        -- The child records the combinations its rewrite changes,
                        -- for the scoped reduce (worker.statistical_history_facet_changed).
                        'record_changes', true
                    ),
                    p_parent_id => v_task_id
                );
                v_child_count := v_child_count + 1;
            END LOOP;
        ELSE
            FOR v_hash_partition IN
                SELECT DISTINCT int4range(
                    (su.hash_slot / v_hash_partition_size) * v_hash_partition_size,
                    LEAST((su.hash_slot / v_hash_partition_size) * v_hash_partition_size + v_hash_partition_size, 16384)
                )
                FROM public.statistical_unit AS su
                ORDER BY 1
            LOOP
                PERFORM worker.spawn(
                    p_command => 'derive_statistical_history_facet_period',
                    p_payload => jsonb_build_object(
                        'command', 'derive_statistical_history_facet_period',
                        'resolution', v_period.resolution::text,
                        'year', v_period.year,
                        'month', v_period.month,
                        'hash_partition', v_hash_partition::text
                    ),
                    p_parent_id => v_task_id
                );
                v_child_count := v_child_count + 1;
            END LOOP;
        END IF;
    END LOOP;

    -- mode tells worker.statistical_history_facet_reduce how to reduce: 'dirty'
    -- recomputes the combinations the children recorded, 'full' the whole cache.
    p_info := jsonb_build_object(
        'child_count', v_child_count,
        'mode', CASE WHEN v_dirty_hash_slots IS NOT NULL THEN 'dirty' ELSE 'full' END);
END;
$procedure$
;

CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_facet_period(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_resolution public.history_resolution := (payload->>'resolution')::public.history_resolution;
    v_year integer := (payload->>'year')::integer;
    v_month integer := (payload->>'month')::integer;
    v_hash_partition int4range := (payload->>'hash_partition')::int4range;
    v_record_changes boolean := COALESCE((payload->>'record_changes')::boolean, false);
    v_row_count bigint;
BEGIN
    -- The slice as it was, so the combinations this rewrite changes, including
    -- the removed ones, can be recorded for the scoped reduce.
    IF v_record_changes THEN
        IF to_regclass('pg_temp._history_facet_slice_before') IS NOT NULL THEN DROP TABLE _history_facet_slice_before; END IF;
        CREATE TEMP TABLE _history_facet_slice_before ON COMMIT DROP AS
        SELECT * FROM public.statistical_history_facet_partitions
         WHERE resolution = v_resolution
           AND year = v_year
           AND month IS NOT DISTINCT FROM v_month
           AND hash_slot >= lower(v_hash_partition)
           AND hash_slot <  upper(v_hash_partition);
    END IF;

    DELETE FROM public.statistical_history_facet_partitions
     WHERE resolution = v_resolution
       AND year = v_year
       AND month IS NOT DISTINCT FROM v_month
       AND hash_slot >= lower(v_hash_partition)
       AND hash_slot <  upper(v_hash_partition);

    INSERT INTO public.statistical_history_facet_partitions
    SELECT * FROM public.statistical_history_facet_def(
        v_resolution, v_year, v_month, v_hash_partition
    );

    GET DIAGNOSTICS v_row_count := ROW_COUNT;

    -- A combination changed when any of its rows in the slice was added,
    -- altered or removed: the symmetric difference of before and after.
    -- Inserted in key order, so concurrent children wait on each other's
    -- uncommitted keys in the same order and cannot deadlock.
    IF v_record_changes THEN
        INSERT INTO worker.statistical_history_facet_changed
        SELECT DISTINCT d.resolution, d.year, d.month, d.unit_type,
               d.primary_activity_category_path, d.secondary_activity_category_path,
               d.sector_path, d.legal_form_id, d.physical_region_path,
               d.physical_country_id, d.unit_size_id, d.status_id
        FROM (
            (SELECT * FROM _history_facet_slice_before
             EXCEPT ALL
             SELECT * FROM public.statistical_history_facet_partitions
              WHERE resolution = v_resolution
                AND year = v_year
                AND month IS NOT DISTINCT FROM v_month
                AND hash_slot >= lower(v_hash_partition)
                AND hash_slot <  upper(v_hash_partition))
            UNION ALL
            (SELECT * FROM public.statistical_history_facet_partitions
              WHERE resolution = v_resolution
                AND year = v_year
                AND month IS NOT DISTINCT FROM v_month
                AND hash_slot >= lower(v_hash_partition)
                AND hash_slot <  upper(v_hash_partition)
             EXCEPT ALL
             SELECT * FROM _history_facet_slice_before)
        ) AS d
        ORDER BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12
        ON CONFLICT DO NOTHING;
    END IF;

    p_info := jsonb_build_object('rows_inserted', v_row_count);
END;
$procedure$
;

CREATE OR REPLACE PROCEDURE worker.statistical_history_facet_reduce(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_dirty_hash_slots int[];
    v_row_count bigint;
    v_mode text;
    v_changed_count bigint;
BEGIN
    -- Read dirty hash slots for diagnostic logging.
    SELECT array_agg(dp.dirty_hash_slot)
      INTO v_dirty_hash_slots
      FROM public.statistical_unit_facet_dirty_hash_slots AS dp;

    -- Reduce as the sibling worker.derive_statistical_history_facet derived:
    -- in 'dirty' mode its children recorded every changed combination, so
    -- only those are recomputed. Anything else (a full derive, or a direct
    -- CALL outside the pipeline) recomputes the whole cache.
    SELECT sibling.info->>'mode'
      INTO v_mode
      FROM worker.tasks AS self
      JOIN worker.tasks AS sibling
        ON sibling.parent_id = self.parent_id
       AND sibling.command = 'derive_statistical_history_facet'
     WHERE self.state = 'processing' AND self.worker_pid = pg_backend_pid()
       AND self.command = 'statistical_history_facet_reduce'
     ORDER BY self.id DESC, sibling.id DESC
     LIMIT 1;

    IF v_mode = 'dirty' THEN
        -- Each changed combination with its totals over the whole cache, or
        -- NULL when no slot supports it any more.
        IF to_regclass('pg_temp._history_facet_changed_total') IS NOT NULL THEN DROP TABLE _history_facet_changed_total; END IF;
        CREATE TEMP TABLE _history_facet_changed_total ON COMMIT DROP AS
        SELECT
            c.resolution, c.year, c.month, c.unit_type,
            c.primary_activity_category_path, c.secondary_activity_category_path,
            c.sector_path, c.legal_form_id, c.physical_region_path,
            c.physical_country_id, c.unit_size_id, c.status_id,
            COUNT(p.hash_slot) AS supporting_rows,
            SUM(p.exists_count)::integer AS exists_count,
            SUM(p.exists_change)::integer AS exists_change,
            SUM(p.exists_added_count)::integer AS exists_added_count,
            SUM(p.exists_removed_count)::integer AS exists_removed_count,
            SUM(p.countable_count)::integer AS countable_count,
            SUM(p.countable_change)::integer AS countable_change,
            SUM(p.countable_added_count)::integer AS countable_added_count,
            SUM(p.countable_removed_count)::integer AS countable_removed_count,
            SUM(p.births)::integer AS births,
            SUM(p.deaths)::integer AS deaths,
            SUM(p.name_change_count)::integer AS name_change_count,
            SUM(p.primary_activity_category_change_count)::integer AS primary_activity_category_change_count,
            SUM(p.secondary_activity_category_change_count)::integer AS secondary_activity_category_change_count,
            SUM(p.sector_change_count)::integer AS sector_change_count,
            SUM(p.legal_form_change_count)::integer AS legal_form_change_count,
            SUM(p.physical_region_change_count)::integer AS physical_region_change_count,
            SUM(p.physical_country_change_count)::integer AS physical_country_change_count,
            SUM(p.physical_address_change_count)::integer AS physical_address_change_count,
            SUM(p.unit_size_change_count)::integer AS unit_size_change_count,
            SUM(p.status_change_count)::integer AS status_change_count,
            jsonb_stats_merge_agg(p.stats_summary) AS stats_summary
        FROM worker.statistical_history_facet_changed AS c
        LEFT JOIN public.statistical_history_facet_partitions AS p
          ON p.resolution = c.resolution
         AND p.year = c.year
         AND COALESCE(p.month, -1) = COALESCE(c.month, -1)
         AND p.unit_type = c.unit_type
         AND COALESCE(p.primary_activity_category_path::text, '') = COALESCE(c.primary_activity_category_path::text, '')
         AND COALESCE(p.secondary_activity_category_path::text, '') = COALESCE(c.secondary_activity_category_path::text, '')
         AND COALESCE(p.sector_path::text, '') = COALESCE(c.sector_path::text, '')
         AND COALESCE(p.legal_form_id, -1) = COALESCE(c.legal_form_id, -1)
         AND COALESCE(p.physical_region_path::text, '') = COALESCE(c.physical_region_path::text, '')
         AND COALESCE(p.physical_country_id, -1) = COALESCE(c.physical_country_id, -1)
         AND COALESCE(p.unit_size_id, -1) = COALESCE(c.unit_size_id, -1)
         AND COALESCE(p.status_id, -1) = COALESCE(c.status_id, -1)
        GROUP BY c.resolution, c.year, c.month, c.unit_type,
                 c.primary_activity_category_path, c.secondary_activity_category_path,
                 c.sector_path, c.legal_form_id, c.physical_region_path,
                 c.physical_country_id, c.unit_size_id, c.status_id;

        MERGE INTO public.statistical_history_facet AS target
        USING _history_facet_changed_total AS source
           ON target.resolution = source.resolution
          AND target.year = source.year
          AND COALESCE(target.month, -1) = COALESCE(source.month, -1)
          AND target.unit_type = source.unit_type
          AND COALESCE(target.primary_activity_category_path::text, '') = COALESCE(source.primary_activity_category_path::text, '')
          AND COALESCE(target.secondary_activity_category_path::text, '') = COALESCE(source.secondary_activity_category_path::text, '')
          AND COALESCE(target.sector_path::text, '') = COALESCE(source.sector_path::text, '')
          AND COALESCE(target.legal_form_id, -1) = COALESCE(source.legal_form_id, -1)
          AND COALESCE(target.physical_region_path::text, '') = COALESCE(source.physical_region_path::text, '')
          AND COALESCE(target.physical_country_id, -1) = COALESCE(source.physical_country_id, -1)
          AND COALESCE(target.unit_size_id, -1) = COALESCE(source.unit_size_id, -1)
          AND COALESCE(target.status_id, -1) = COALESCE(source.status_id, -1)
        WHEN MATCHED AND source.supporting_rows = 0
            THEN DELETE
        WHEN MATCHED AND (
                target.exists_count <> source.exists_count
             OR target.stats_summary IS DISTINCT FROM source.stats_summary)
            THEN UPDATE SET
                exists_count = source.exists_count,
                exists_change = source.exists_change,
                exists_added_count = source.exists_added_count,
                exists_removed_count = source.exists_removed_count,
                countable_count = source.countable_count,
                countable_change = source.countable_change,
                countable_added_count = source.countable_added_count,
                countable_removed_count = source.countable_removed_count,
                births = source.births,
                deaths = source.deaths,
                name_change_count = source.name_change_count,
                primary_activity_category_change_count = source.primary_activity_category_change_count,
                secondary_activity_category_change_count = source.secondary_activity_category_change_count,
                sector_change_count = source.sector_change_count,
                legal_form_change_count = source.legal_form_change_count,
                physical_region_change_count = source.physical_region_change_count,
                physical_country_change_count = source.physical_country_change_count,
                physical_address_change_count = source.physical_address_change_count,
                unit_size_change_count = source.unit_size_change_count,
                status_change_count = source.status_change_count,
                stats_summary = source.stats_summary
        WHEN NOT MATCHED BY TARGET AND source.supporting_rows > 0
            THEN INSERT (
                resolution, year, month, unit_type,
                primary_activity_category_path, secondary_activity_category_path,
                sector_path, legal_form_id, physical_region_path,
                physical_country_id, unit_size_id, status_id,
                exists_count, exists_change, exists_added_count, exists_removed_count,
                countable_count, countable_change, countable_added_count, countable_removed_count,
                births, deaths,
                name_change_count, primary_activity_category_change_count,
                secondary_activity_category_change_count, sector_change_count,
                legal_form_change_count, physical_region_change_count,
                physical_country_change_count, physical_address_change_count,
                unit_size_change_count, status_change_count,
                stats_summary)
            VALUES (
                source.resolution, source.year, source.month, source.unit_type,
                source.primary_activity_category_path, source.secondary_activity_category_path,
                source.sector_path, source.legal_form_id, source.physical_region_path,
                source.physical_country_id, source.unit_size_id, source.status_id,
                source.exists_count, source.exists_change, source.exists_added_count, source.exists_removed_count,
                source.countable_count, source.countable_change, source.countable_added_count, source.countable_removed_count,
                source.births, source.deaths,
                source.name_change_count, source.primary_activity_category_change_count,
                source.secondary_activity_category_change_count, source.sector_change_count,
                source.legal_form_change_count, source.physical_region_change_count,
                source.physical_country_change_count, source.physical_address_change_count,
                source.unit_size_change_count, source.status_change_count,
                source.stats_summary);
        GET DIAGNOSTICS v_row_count := ROW_COUNT;
        SELECT count(*) INTO v_changed_count FROM _history_facet_changed_total;

        TRUNCATE worker.statistical_history_facet_changed;

        p_info := jsonb_build_object(
            'mode', 'dirty',
            'changed_combinations', v_changed_count,
            'dirty_hash_slots', to_jsonb(v_dirty_hash_slots),
            'rows_merged', v_row_count);
    ELSE
    MERGE INTO public.statistical_history_facet AS target
    USING (
        SELECT
            resolution, year, month, unit_type,
            primary_activity_category_path, secondary_activity_category_path,
            sector_path, legal_form_id, physical_region_path,
            physical_country_id, unit_size_id, status_id,
            SUM(exists_count)::integer AS exists_count,
            SUM(exists_change)::integer AS exists_change,
            SUM(exists_added_count)::integer AS exists_added_count,
            SUM(exists_removed_count)::integer AS exists_removed_count,
            SUM(countable_count)::integer AS countable_count,
            SUM(countable_change)::integer AS countable_change,
            SUM(countable_added_count)::integer AS countable_added_count,
            SUM(countable_removed_count)::integer AS countable_removed_count,
            SUM(births)::integer AS births,
            SUM(deaths)::integer AS deaths,
            SUM(name_change_count)::integer AS name_change_count,
            SUM(primary_activity_category_change_count)::integer AS primary_activity_category_change_count,
            SUM(secondary_activity_category_change_count)::integer AS secondary_activity_category_change_count,
            SUM(sector_change_count)::integer AS sector_change_count,
            SUM(legal_form_change_count)::integer AS legal_form_change_count,
            SUM(physical_region_change_count)::integer AS physical_region_change_count,
            SUM(physical_country_change_count)::integer AS physical_country_change_count,
            SUM(physical_address_change_count)::integer AS physical_address_change_count,
            SUM(unit_size_change_count)::integer AS unit_size_change_count,
            SUM(status_change_count)::integer AS status_change_count,
            jsonb_stats_merge_agg(stats_summary) AS stats_summary
        FROM public.statistical_history_facet_partitions
        GROUP BY resolution, year, month, unit_type,
                 primary_activity_category_path, secondary_activity_category_path,
                 sector_path, legal_form_id, physical_region_path,
                 physical_country_id, unit_size_id, status_id
    ) AS source
       ON target.resolution = source.resolution
      AND target.year = source.year
      AND COALESCE(target.month, -1) = COALESCE(source.month, -1)
      AND target.unit_type = source.unit_type
      AND COALESCE(target.primary_activity_category_path::text, '') = COALESCE(source.primary_activity_category_path::text, '')
      AND COALESCE(target.secondary_activity_category_path::text, '') = COALESCE(source.secondary_activity_category_path::text, '')
      AND COALESCE(target.sector_path::text, '') = COALESCE(source.sector_path::text, '')
      AND COALESCE(target.legal_form_id, -1) = COALESCE(source.legal_form_id, -1)
      AND COALESCE(target.physical_region_path::text, '') = COALESCE(source.physical_region_path::text, '')
      AND COALESCE(target.physical_country_id, -1) = COALESCE(source.physical_country_id, -1)
      AND COALESCE(target.unit_size_id, -1) = COALESCE(source.unit_size_id, -1)
      AND COALESCE(target.status_id, -1) = COALESCE(source.status_id, -1)
    WHEN MATCHED AND (
            target.exists_count <> source.exists_count
         OR target.stats_summary IS DISTINCT FROM source.stats_summary)
        THEN UPDATE SET
            exists_count = source.exists_count,
            exists_change = source.exists_change,
            exists_added_count = source.exists_added_count,
            exists_removed_count = source.exists_removed_count,
            countable_count = source.countable_count,
            countable_change = source.countable_change,
            countable_added_count = source.countable_added_count,
            countable_removed_count = source.countable_removed_count,
            births = source.births,
            deaths = source.deaths,
            name_change_count = source.name_change_count,
            primary_activity_category_change_count = source.primary_activity_category_change_count,
            secondary_activity_category_change_count = source.secondary_activity_category_change_count,
            sector_change_count = source.sector_change_count,
            legal_form_change_count = source.legal_form_change_count,
            physical_region_change_count = source.physical_region_change_count,
            physical_country_change_count = source.physical_country_change_count,
            physical_address_change_count = source.physical_address_change_count,
            unit_size_change_count = source.unit_size_change_count,
            status_change_count = source.status_change_count,
            stats_summary = source.stats_summary
    WHEN NOT MATCHED BY TARGET
        THEN INSERT (
            resolution, year, month, unit_type,
            primary_activity_category_path, secondary_activity_category_path,
            sector_path, legal_form_id, physical_region_path,
            physical_country_id, unit_size_id, status_id,
            exists_count, exists_change, exists_added_count, exists_removed_count,
            countable_count, countable_change, countable_added_count, countable_removed_count,
            births, deaths,
            name_change_count, primary_activity_category_change_count,
            secondary_activity_category_change_count, sector_change_count,
            legal_form_change_count, physical_region_change_count,
            physical_country_change_count, physical_address_change_count,
            unit_size_change_count, status_change_count,
            stats_summary)
        VALUES (
            source.resolution, source.year, source.month, source.unit_type,
            source.primary_activity_category_path, source.secondary_activity_category_path,
            source.sector_path, source.legal_form_id, source.physical_region_path,
            source.physical_country_id, source.unit_size_id, source.status_id,
            source.exists_count, source.exists_change, source.exists_added_count, source.exists_removed_count,
            source.countable_count, source.countable_change, source.countable_added_count, source.countable_removed_count,
            source.births, source.deaths,
            source.name_change_count, source.primary_activity_category_change_count,
            source.secondary_activity_category_change_count, source.sector_change_count,
            source.legal_form_change_count, source.physical_region_change_count,
            source.physical_country_change_count, source.physical_address_change_count,
            source.unit_size_change_count, source.status_change_count,
            source.stats_summary)
    WHEN NOT MATCHED BY SOURCE THEN DELETE;
    GET DIAGNOSTICS v_row_count := ROW_COUNT;

    -- The whole cache is reduced, which covers every recorded change.
    TRUNCATE worker.statistical_history_facet_changed;

    p_info := jsonb_build_object(
        'mode', 'full',
        'dirty_hash_slots', to_jsonb(v_dirty_hash_slots),
        'rows_merged', v_row_count);
    END IF;

    -- Clean up dirty partitions at the very end, after all consumers have read them.
    -- (statistical_unit_facet_reduce ran earlier in the pipeline and read dirty_hash_slots
    -- for diagnostic logging; truncating here is safe because no later step needs it.)
    TRUNCATE public.statistical_unit_facet_dirty_hash_slots;

    PERFORM pg_notify('worker_status',
        json_build_object('type', 'is_deriving_reports', 'status', false)::text);
END;
$procedure$
;

COMMENT ON PROCEDURE worker.statistical_unit_facet_reduce(jsonb, jsonb) IS
'Brings public.statistical_unit_facet in line with public.statistical_unit_facet_staging. After a dirty derive it recomputes only the combinations in worker.statistical_unit_facet_changed, which the children recorded with their removed part, and deletes the ones without support. After a full derive, or when called outside the pipeline, it merges the whole cache. It can only be as right as the cache: a counting defect leaves wrong rows that no later dirty cycle revisits, so a migration that fixes one schedules a full rebuild with worker.enqueue_derive_statistical_unit_all().';

COMMENT ON PROCEDURE worker.statistical_history_facet_reduce(jsonb, jsonb) IS
'Brings public.statistical_history_facet in line with public.statistical_history_facet_partitions. After a dirty derive it recomputes only the combinations in worker.statistical_history_facet_changed, which the children recorded with their removed part, and deletes the ones without support. After a full derive, or when called outside the pipeline, it merges the whole cache. It can only be as right as the cache: a counting defect leaves wrong rows that no later dirty cycle revisits, so a migration that fixes one schedules a full rebuild with worker.enqueue_derive_statistical_unit_all().';

-- Start the scoped reduces from a known state: one full rebuild of every
-- report cache, so no row from before this migration depends on a change
-- that was never recorded.
SELECT worker.enqueue_derive_statistical_unit_all();

END;
