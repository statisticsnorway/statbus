-- Down migration 20260507115831: restore pre_dirty_dims tables, hash_slot column,
-- and the parent procedures' write-only TRUNCATE+INSERT calls.
--
-- This restores the schema state from before the up migration: the snapshot
-- tables exist, the column + index exist, and the derive_*_facet procedures
-- still write into the snapshots (even though no reader exists in the rest of
-- the schema — the post-Phase 3 reduces don't read pre_dirty_dims).

BEGIN;

----------------------------------------------------------------------
-- 1. Restore pre_dirty_dims snapshot tables (UNLOGGED, ephemeral)
----------------------------------------------------------------------

CREATE UNLOGGED TABLE public.statistical_unit_facet_pre_dirty_dims (
    valid_from                     date,
    valid_to                       date,
    valid_until                    date,
    unit_type                      statistical_unit_type,
    physical_region_path           ltree,
    primary_activity_category_path ltree,
    sector_path                    ltree,
    legal_form_id                  integer,
    physical_country_id            integer,
    status_id                      integer
);

CREATE UNLOGGED TABLE public.statistical_history_facet_pre_dirty_dims (
    resolution                       history_resolution,
    year                             integer,
    month                            integer,
    unit_type                        statistical_unit_type,
    primary_activity_category_path   ltree,
    secondary_activity_category_path ltree,
    sector_path                      ltree,
    legal_form_id                    integer,
    physical_region_path             ltree,
    physical_country_id              integer,
    unit_size_id                     integer,
    status_id                        integer
);

COMMENT ON TABLE public.statistical_unit_facet_pre_dirty_dims IS
    'Scoped-merge-reduce pre-snapshot for statistical_unit_facet. UNLOGGED + '
    'ephemeral. Holds the dim-combinations that existed in dirty partitions '
    'BEFORE worker children rewrite staging, so the reduce step can scope '
    'aggregate/MERGE/DELETE to the affected combinations only and detect '
    'combinations that disappeared.';

COMMENT ON TABLE public.statistical_history_facet_pre_dirty_dims IS
    'Scoped-merge-reduce pre-snapshot for statistical_history_facet. UNLOGGED + '
    'ephemeral. Same pattern as statistical_unit_facet_pre_dirty_dims, keyed '
    'by (resolution, year, month) plus all 11 history facet dim columns.';


----------------------------------------------------------------------
-- 2. Restore hash_slot column + orphaned btree index
----------------------------------------------------------------------

ALTER TABLE public.statistical_unit_facet ADD COLUMN hash_slot integer;
CREATE INDEX idx_statistical_unit_facet_hash_slot
    ON public.statistical_unit_facet (hash_slot);


----------------------------------------------------------------------
-- 3. Restore derive_statistical_unit_facet with TRUNCATE+INSERT writes
----------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE worker.derive_statistical_unit_facet(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $derive_statistical_unit_facet$
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

    -- Bail to full rebuild if the staging table is empty (fresh install, post-reset).
    IF NOT EXISTS (SELECT 1 FROM public.statistical_unit_facet_staging LIMIT 1) THEN
        v_dirty_hash_slots := NULL;
    END IF;

    -- Snapshot dirty dims BEFORE children rewrite staging.
    IF v_dirty_hash_slots IS NOT NULL THEN
        TRUNCATE public.statistical_unit_facet_pre_dirty_dims;
        INSERT INTO public.statistical_unit_facet_pre_dirty_dims
        SELECT DISTINCT s.valid_from, s.valid_to, s.valid_until, s.unit_type,
               s.physical_region_path, s.primary_activity_category_path,
               s.sector_path, s.legal_form_id, s.physical_country_id, s.status_id
        FROM public.statistical_unit_facet_staging AS s
        WHERE s.hash_slot = ANY(v_dirty_hash_slots);

        FOR i IN 1..COALESCE(array_length(v_dirty_hash_slots, 1), 0) LOOP
            PERFORM worker.spawn(
                p_command => 'derive_statistical_unit_facet_partition',
                p_payload => jsonb_build_object(
                    'command', 'derive_statistical_unit_facet_partition',
                    'hash_partition', int4range(v_dirty_hash_slots[i], v_dirty_hash_slots[i] + 1)::text
                ),
                p_parent_id => v_task_id
            );
            v_child_count := v_child_count + 1;
        END LOOP;
    ELSE
        TRUNCATE public.statistical_unit_facet_pre_dirty_dims;

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

    p_info := jsonb_build_object('child_count', v_child_count);
END;
$derive_statistical_unit_facet$;


----------------------------------------------------------------------
-- 4. Restore derive_statistical_history_facet with TRUNCATE+INSERT writes
----------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_facet(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $derive_statistical_history_facet$
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

    IF NOT EXISTS (SELECT 1 FROM public.statistical_history_facet_partitions LIMIT 1) THEN
        v_dirty_hash_slots := NULL;
    END IF;

    -- Snapshot dirty dims BEFORE children rewrite partitions.
    IF v_dirty_hash_slots IS NOT NULL THEN
        TRUNCATE public.statistical_history_facet_pre_dirty_dims;
        INSERT INTO public.statistical_history_facet_pre_dirty_dims
        SELECT DISTINCT s.resolution, s.year, s.month, s.unit_type,
               s.primary_activity_category_path, s.secondary_activity_category_path,
               s.sector_path, s.legal_form_id, s.physical_region_path,
               s.physical_country_id, s.unit_size_id, s.status_id
        FROM public.statistical_history_facet_partitions AS s
        WHERE s.hash_slot = ANY(v_dirty_hash_slots);
    ELSE
        TRUNCATE public.statistical_history_facet_pre_dirty_dims;
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
            FOR i IN 1..COALESCE(array_length(v_dirty_hash_slots, 1), 0) LOOP
                PERFORM worker.spawn(
                    p_command => 'derive_statistical_history_facet_period',
                    p_payload => jsonb_build_object(
                        'command', 'derive_statistical_history_facet_period',
                        'resolution', v_period.resolution::text,
                        'year', v_period.year,
                        'month', v_period.month,
                        'hash_partition', int4range(v_dirty_hash_slots[i], v_dirty_hash_slots[i] + 1)::text
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

    p_info := jsonb_build_object('child_count', v_child_count);
END;
$derive_statistical_history_facet$;

END;
