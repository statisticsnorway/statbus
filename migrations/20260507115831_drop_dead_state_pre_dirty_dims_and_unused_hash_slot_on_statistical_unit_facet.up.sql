-- Migration 20260507115831: drop dead state pre_dirty_dims and unused hash_slot
--
-- Removes apparatus that became dead state after rc.42 + Phase 3 (collapse to
-- global MERGE):
--
--   * `statistical_unit_facet_pre_dirty_dims` and `statistical_history_facet_pre_dirty_dims`
--     UNLOGGED snapshot tables. Used to be read by the scoped Path B reduce
--     (migration `20260324232001`). After Phase 3 (`20260429233218`), the
--     reduces collapsed to a single global MERGE with `WHEN NOT MATCHED BY
--     SOURCE THEN DELETE` and stopped reading these tables. The parent
--     `worker.derive_*_facet` procedures still TRUNCATE+INSERT into them —
--     pure write-only dead state, removed here.
--
--   * `statistical_unit_facet.hash_slot` column (and the
--     `idx_statistical_unit_facet_hash_slot` btree index). Originally added
--     in `20260210193343_partition_statistical_unit_facet` (as
--     `partition_seq`) and renamed to `hash_slot` in rc.42
--     (`20260422000000`). The target table is keyed by dim+temporal tuple,
--     not by unit_id, so there is no trigger or upstream writer that
--     populates `hash_slot` on this table. The column is uniformly NULL
--     and the index is empty/orphaned. The reduce / derive functions all
--     have explicit column lists that exclude `hash_slot`. Confirmed no
--     reader in the current schema (grep doc/db).
--
-- Down migration restores the tables, the column + index, and the parent
-- procedures' write-only TRUNCATE+INSERT (still dead, but matches the
-- pre-cleanup state).

BEGIN;

----------------------------------------------------------------------
-- 1. Strip pre_dirty_dims TRUNCATE+INSERT from derive_statistical_unit_facet
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

    IF v_dirty_hash_slots IS NOT NULL THEN
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
-- 2. Strip pre_dirty_dims TRUNCATE+INSERT from derive_statistical_history_facet
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


----------------------------------------------------------------------
-- 3. Drop the dead pre_dirty_dims snapshot tables
----------------------------------------------------------------------

DROP TABLE public.statistical_unit_facet_pre_dirty_dims;
DROP TABLE public.statistical_history_facet_pre_dirty_dims;


----------------------------------------------------------------------
-- 4. Drop the orphaned hash_slot column on statistical_unit_facet
--    (cascades to drop idx_statistical_unit_facet_hash_slot)
----------------------------------------------------------------------

ALTER TABLE public.statistical_unit_facet DROP COLUMN hash_slot;

END;
