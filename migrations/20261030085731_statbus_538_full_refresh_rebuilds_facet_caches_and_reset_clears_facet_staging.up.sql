-- Migration 20261030085731: STATBUS-538 a full refresh rebuilds the report
-- caches; reset() clears statistical_unit_facet_staging.
--
-- statistical_unit_facet_staging, statistical_history (per-slot rows) and
-- statistical_history_facet_partitions are per-hash_slot caches reduced into
-- the report tables. Incremental derives recompute only dirty slots. Two
-- paths left slots whose units no longer exist in the caches, so the reduce
-- kept counting them (demo 2026-10-30: 179 enterprises in a region with 91):
--   * reset() truncated the units but not statistical_unit_facet_staging.
--   * collect_changes with all *_id_ranges NULL (all units, all time) only
--     dirtied the slots of existing units; each derive went full only when
--     its cache was empty, which callers forced with TRUNCATE.
-- Now collect_changes passes full_refresh to the report derives, which then
-- drop and rebuild their whole cache. reset() also clears facet staging.
-- Finally a full refresh is scheduled to repair caches on existing installs.
BEGIN;

CREATE OR REPLACE PROCEDURE worker.command_collect_changes(IN p_payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_row RECORD;
    v_est_ids int4multirange := '{}'::int4multirange;
    v_lu_ids int4multirange := '{}'::int4multirange;
    v_ent_ids int4multirange := '{}'::int4multirange;
    v_pg_ids int4multirange := '{}'::int4multirange;
    v_valid_range datemultirange := '{}'::datemultirange;
    v_valid_from DATE;
    v_valid_until DATE;
    v_task_id BIGINT;
    v_phase1_id BIGINT;
    v_phase2_id BIGINT;
    v_payload JSONB;
    v_direct_mode BOOLEAN;
    v_full_refresh BOOLEAN;
BEGIN
    v_direct_mode :=
        p_payload ? 'establishment_id_ranges'
        OR p_payload ? 'legal_unit_id_ranges'
        OR p_payload ? 'enterprise_id_ranges'
        OR p_payload ? 'power_group_id_ranges';

    -- STATBUS-538: a full refresh is the direct-mode payload naming every
    -- unit kind with NULL (all ids) and no valid_ranges (all time). It is
    -- passed on as payload.full_refresh so each report derive rebuilds its
    -- whole per-slot cache, including slots whose units no longer exist.
    v_full_refresh := v_direct_mode
        AND NULLIF(p_payload->>'establishment_id_ranges', '') IS NULL
        AND NULLIF(p_payload->>'legal_unit_id_ranges', '') IS NULL
        AND NULLIF(p_payload->>'enterprise_id_ranges', '') IS NULL
        AND NULLIF(p_payload->>'power_group_id_ranges', '') IS NULL
        AND NULLIF(p_payload->>'valid_ranges', '') IS NULL;

    IF v_direct_mode THEN
        -- Caller supplied explicit ranges. A NULL / JSON-null value for a
        -- given key means "all ids of that kind" — synthesise from base
        -- tables. The established NULL-means-everything convention
        -- (cf. worker.derive_statistical_unit.v_is_full_refresh).
        v_est_ids := COALESCE(
            NULLIF(p_payload->>'establishment_id_ranges', '')::int4multirange,
            COALESCE(
                (SELECT range_agg(int4range(id, id, '[]'))::int4multirange FROM public.establishment),
                '{}'::int4multirange
            )
        );
        v_lu_ids := COALESCE(
            NULLIF(p_payload->>'legal_unit_id_ranges', '')::int4multirange,
            COALESCE(
                (SELECT range_agg(int4range(id, id, '[]'))::int4multirange FROM public.legal_unit),
                '{}'::int4multirange
            )
        );
        v_ent_ids := COALESCE(
            NULLIF(p_payload->>'enterprise_id_ranges', '')::int4multirange,
            COALESCE(
                (SELECT range_agg(int4range(id, id, '[]'))::int4multirange FROM public.enterprise),
                '{}'::int4multirange
            )
        );
        v_pg_ids := COALESCE(
            NULLIF(p_payload->>'power_group_id_ranges', '')::int4multirange,
            COALESCE(
                (SELECT range_agg(int4range(id, id, '[]'))::int4multirange FROM public.power_group),
                '{}'::int4multirange
            )
        );
        v_valid_range := COALESCE(
            NULLIF(p_payload->>'valid_ranges', '')::datemultirange,
            '{}'::datemultirange
        );
        UPDATE worker.base_change_log_has_pending SET has_pending = FALSE;
    ELSE
        -- Drain-log mode: unchanged from 20260319124229.
        FOR v_row IN DELETE FROM worker.base_change_log RETURNING * LOOP
            v_est_ids := v_est_ids + v_row.establishment_ids;
            v_lu_ids := v_lu_ids + v_row.legal_unit_ids;
            v_ent_ids := v_ent_ids + v_row.enterprise_ids;
            v_pg_ids := v_pg_ids + v_row.power_group_ids;
            v_valid_range := v_valid_range + v_row.valid_ranges;
        END LOOP;

        UPDATE worker.base_change_log_has_pending SET has_pending = FALSE;
    END IF;

    IF v_est_ids != '{}'::int4multirange
       OR v_lu_ids != '{}'::int4multirange
       OR v_ent_ids != '{}'::int4multirange
       OR v_pg_ids != '{}'::int4multirange THEN

        -- Get own task_id for spawning children
        SELECT id INTO v_task_id
        FROM worker.tasks
        WHERE state = 'processing' AND worker_pid = pg_backend_pid()
        ORDER BY id DESC LIMIT 1;

        p_info := jsonb_build_object(
            'affected_establishment_count', (SELECT COALESCE(sum(upper(r) - lower(r)), 0) FROM unnest(v_est_ids) AS r),
            'affected_legal_unit_count', (SELECT COALESCE(sum(upper(r) - lower(r)), 0) FROM unnest(v_lu_ids) AS r),
            'affected_enterprise_count', (SELECT COALESCE(sum(upper(r) - lower(r)), 0) FROM unnest(v_ent_ids) AS r),
            'affected_power_group_count', (SELECT COALESCE(sum(upper(r) - lower(r)), 0) FROM unnest(v_pg_ids) AS r)
        );

        IF v_valid_range = '{}'::datemultirange THEN
            SELECT COALESCE(range_agg(vr)::datemultirange, '{}'::datemultirange)
            INTO v_valid_range
            FROM (
                SELECT valid_range AS vr FROM public.establishment AS est WHERE v_est_ids @> est.id
                UNION ALL
                SELECT valid_range AS vr FROM public.legal_unit AS lu WHERE v_lu_ids @> lu.id
            ) AS units;
        END IF;

        v_valid_from := lower(v_valid_range);
        v_valid_until := upper(v_valid_range);

        v_payload := jsonb_build_object(
            'valid_from', v_valid_from,
            'valid_until', v_valid_until,
            'full_refresh', v_full_refresh
        );

        v_phase1_id := worker.spawn(
            p_command => 'derive_units_phase',
            p_payload => v_payload,
            p_parent_id => v_task_id,
            p_child_mode => 'serial'
        );

        PERFORM worker.spawn(
            p_command => 'derive_statistical_unit',
            p_payload => jsonb_build_object(
                'establishment_id_ranges', v_est_ids::text,
                'legal_unit_id_ranges', v_lu_ids::text,
                'enterprise_id_ranges', v_ent_ids::text,
                'power_group_id_ranges', v_pg_ids::text,
                'valid_from', v_valid_from,
                'valid_until', v_valid_until
            ),
            p_parent_id => v_phase1_id,
            p_child_mode => 'serial'
        );

        PERFORM worker.spawn(
            p_command => 'statistical_unit_flush_staging',
            p_payload => v_payload,
            p_parent_id => v_phase1_id,
            p_child_mode => 'serial'
        );

        -- BLOCK D: derive_used_tables runs AFTER statistical_unit_flush_staging
        -- has published activity/region/sector/… paths to public.statistical_unit.
        -- Previously these were invoked inline from worker.derive_statistical_unit,
        -- which ran before the flush — the views filtering on *_path IS NOT NULL
        -- returned 0 rows and *_used stayed empty on first-import cycles.
        PERFORM worker.spawn(
            p_command => 'derive_used_tables',
            p_payload => v_payload,
            p_parent_id => v_phase1_id,
            p_child_mode => 'serial'
        );

        v_phase2_id := worker.spawn(
            p_command => 'derive_reports_phase',
            p_payload => v_payload,
            p_parent_id => v_task_id,
            p_child_mode => 'serial'
        );

        PERFORM worker.spawn(
            p_command => 'derive_statistical_history',
            p_payload => v_payload,
            p_parent_id => v_phase2_id,
            p_child_mode => 'serial'
        );

        PERFORM worker.spawn(
            p_command => 'statistical_history_reduce',
            p_payload => v_payload,
            p_parent_id => v_phase2_id,
            p_child_mode => 'serial'
        );

        PERFORM worker.spawn(
            p_command => 'derive_statistical_unit_facet',
            p_payload => v_payload,
            p_parent_id => v_phase2_id,
            p_child_mode => 'serial'
        );

        PERFORM worker.spawn(
            p_command => 'statistical_unit_facet_reduce',
            p_payload => v_payload,
            p_parent_id => v_phase2_id,
            p_child_mode => 'serial'
        );

        PERFORM worker.spawn(
            p_command => 'derive_statistical_history_facet',
            p_payload => v_payload,
            p_parent_id => v_phase2_id,
            p_child_mode => 'serial'
        );

        PERFORM worker.spawn(
            p_command => 'statistical_history_facet_reduce',
            p_payload => v_payload,
            p_parent_id => v_phase2_id,
            p_child_mode => 'serial'
        );
    ELSE
        p_info := jsonb_build_object(
            'affected_establishment_count', 0,
            'affected_legal_unit_count', 0,
            'affected_enterprise_count', 0,
            'affected_power_group_count', 0
        );
        PERFORM pg_notify('worker_status',
            json_build_object('type', 'is_deriving_statistical_units', 'status', false)::text);
    END IF;
END;
$procedure$
;

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

    -- Full rebuild when collect_changes requested a full refresh
    -- (STATBUS-538), or when the staging cache is empty (fresh install,
    -- unclean shutdown of the UNLOGGED table). A full refresh drops the whole
    -- cache first: slots whose units no longer exist are never dirty and
    -- would otherwise keep counting in the reduce.
    IF COALESCE((payload->>'full_refresh')::boolean, false) THEN
        DELETE FROM public.statistical_unit_facet_staging;
        v_dirty_hash_slots := NULL;
    ELSIF NOT EXISTS (SELECT 1 FROM public.statistical_unit_facet_staging LIMIT 1) THEN
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
$procedure$
;

CREATE OR REPLACE PROCEDURE worker.derive_statistical_history(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
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

    -- Full rebuild when collect_changes requested a full refresh
    -- (STATBUS-538), or when no per-slot rows exist yet (fresh install).
    -- A full refresh drops every per-slot row first, so slots and periods
    -- without units do not survive into the reduce.
    IF COALESCE((payload->>'full_refresh')::boolean, false) THEN
        DELETE FROM public.statistical_history WHERE hash_partition IS NOT NULL;
        v_dirty_hash_slots := NULL;
    ELSIF NOT EXISTS (SELECT 1 FROM public.statistical_history WHERE hash_partition IS NOT NULL LIMIT 1) THEN
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
            -- Dirty branch: one singleton range per dirty slot.
            FOR i IN 1..COALESCE(array_length(v_dirty_hash_slots, 1), 0) LOOP
                PERFORM worker.spawn(
                    p_command => 'derive_statistical_history_period',
                    p_payload => jsonb_build_object(
                        'command', 'derive_statistical_history_period',
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
            -- Full-rebuild branch: data-driven DISTINCT ranges, derived from
            -- the actual set of slots occupied in statistical_unit.
            FOR v_hash_partition IN
                SELECT DISTINCT int4range(
                    (su.hash_slot / v_hash_partition_size) * v_hash_partition_size,
                    LEAST((su.hash_slot / v_hash_partition_size) * v_hash_partition_size + v_hash_partition_size, 16384)
                )
                FROM public.statistical_unit AS su
                ORDER BY 1
            LOOP
                PERFORM worker.spawn(
                    p_command => 'derive_statistical_history_period',
                    p_payload => jsonb_build_object(
                        'command', 'derive_statistical_history_period',
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

    -- Full rebuild when collect_changes requested a full refresh
    -- (STATBUS-538), or when the per-slot cache is empty (fresh install).
    -- A full refresh drops the whole cache first, so slots and periods
    -- without units do not survive into the reduce.
    IF COALESCE((payload->>'full_refresh')::boolean, false) THEN
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
$procedure$
;

CREATE OR REPLACE FUNCTION public.reset(confirmed boolean, scope reset_scope)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    result JSONB := '{}'::JSONB;
    changed JSONB;
    _activity_count bigint;
    _location_count bigint;
    _contact_count bigint;
    _person_for_unit_count bigint;
    _person_count bigint;
    _tag_for_unit_count bigint;
    _stat_for_unit_count bigint;
    _external_ident_count bigint;
    _legal_relationship_count bigint;
    _power_root_count bigint;
    _establishment_count bigint;
    _legal_unit_count bigint;
    _enterprise_count bigint;
    _power_group_count bigint;
    _image_count bigint;
    _unit_notes_count bigint;
BEGIN
    IF NOT confirmed THEN
        RAISE EXCEPTION 'Action not confirmed.';
    END IF;

    -- ================================================================
    -- Scope: 'units' (and all broader scopes)
    -- ================================================================

    CASE WHEN scope IN ('units', 'data', 'getting-started', 'all') THEN
        SELECT COUNT(*) FROM public.activity INTO _activity_count;
        SELECT COUNT(*) FROM public.location INTO _location_count;
        SELECT COUNT(*) FROM public.contact INTO _contact_count;
        SELECT COUNT(*) FROM public.person_for_unit INTO _person_for_unit_count;
        SELECT COUNT(*) FROM public.person INTO _person_count;
        SELECT COUNT(*) FROM public.tag_for_unit INTO _tag_for_unit_count;
        SELECT COUNT(*) FROM public.stat_for_unit INTO _stat_for_unit_count;
        SELECT COUNT(*) FROM public.external_ident INTO _external_ident_count;
        SELECT COUNT(*) FROM public.legal_relationship INTO _legal_relationship_count;
        SELECT COUNT(*) FROM public.power_root INTO _power_root_count;
        SELECT COUNT(*) FROM public.establishment INTO _establishment_count;
        SELECT COUNT(*) FROM public.legal_unit INTO _legal_unit_count;
        SELECT COUNT(*) FROM public.enterprise INTO _enterprise_count;
        SELECT COUNT(*) FROM public.power_group INTO _power_group_count;
        SELECT COUNT(*) FROM public.image INTO _image_count;
        SELECT COUNT(*) FROM public.unit_notes INTO _unit_notes_count;

        TRUNCATE
            public.activity,
            public.location,
            public.contact,
            public.stat_for_unit,
            public.external_ident,
            public.person_for_unit,
            public.person,
            public.tag_for_unit,
            public.unit_notes,
            public.legal_relationship,
            public.power_root,
            public.establishment,
            public.legal_unit,
            public.enterprise,
            public.power_group,
            public.image,
            public.timeline_establishment,
            public.timeline_legal_unit,
            public.timeline_enterprise,
            public.timeline_power_group,
            public.timepoints,
            public.timesegments,
            public.timesegments_years,
            public.statistical_unit,
            public.statistical_unit_facet,
            public.statistical_unit_facet_staging,
            public.statistical_unit_facet_dirty_hash_slots,
            public.statistical_history,
            public.statistical_history_facet,
            public.statistical_history_facet_partitions;

        result := result
            || jsonb_build_object('activity', jsonb_build_object('deleted_count', _activity_count))
            || jsonb_build_object('location', jsonb_build_object('deleted_count', _location_count))
            || jsonb_build_object('contact', jsonb_build_object('deleted_count', _contact_count))
            || jsonb_build_object('person_for_unit', jsonb_build_object('deleted_count', _person_for_unit_count))
            || jsonb_build_object('person', jsonb_build_object('deleted_count', _person_count))
            || jsonb_build_object('tag_for_unit', jsonb_build_object('deleted_count', _tag_for_unit_count))
            || jsonb_build_object('stat_for_unit', jsonb_build_object('deleted_count', _stat_for_unit_count))
            || jsonb_build_object('external_ident', jsonb_build_object('deleted_count', _external_ident_count))
            || jsonb_build_object('legal_relationship', jsonb_build_object('deleted_count', _legal_relationship_count))
            || jsonb_build_object('power_root', jsonb_build_object('deleted_count', _power_root_count))
            || jsonb_build_object('establishment', jsonb_build_object('deleted_count', _establishment_count))
            || jsonb_build_object('legal_unit', jsonb_build_object('deleted_count', _legal_unit_count))
            || jsonb_build_object('enterprise', jsonb_build_object('deleted_count', _enterprise_count))
            || jsonb_build_object('power_group', jsonb_build_object('deleted_count', _power_group_count))
            || jsonb_build_object('image', jsonb_build_object('deleted_count', _image_count))
            || jsonb_build_object('unit_notes', jsonb_build_object('deleted_count', _unit_notes_count));
    ELSE END CASE;

    -- ================================================================
    -- Scope: 'data' (adds import cleanup)
    -- ================================================================

    CASE WHEN scope IN ('data', 'getting-started', 'all') THEN
        WITH deleted_import_job AS (
            DELETE FROM public.import_job WHERE id > 0 RETURNING *
        )
        SELECT jsonb_build_object(
            'import_job', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_import_job)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    -- ================================================================
    -- Scope: 'getting-started' (adds config/reference cleanup)
    -- ================================================================

    CASE WHEN scope IN ('getting-started', 'all') THEN
        -- Transient: delete custom definitions before data_source due to RESTRICT FK. See doc/data-model.md
        WITH deleted_import_definition AS (
            DELETE FROM public.import_definition WHERE custom RETURNING *
        )
        SELECT jsonb_build_object(
            'import_definition', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_import_definition)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_region AS (
            DELETE FROM public.region WHERE id > 0 RETURNING *
        )
        SELECT jsonb_build_object(
            'region', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_region)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_settings AS (
            DELETE FROM public.settings WHERE only_one_setting = TRUE RETURNING *
        )
        SELECT jsonb_build_object(
            'settings', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_settings)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_rv AS (
            DELETE FROM public.region_version WHERE custom RETURNING *
        ), changed_rv AS (
            UPDATE public.region_version SET enabled = TRUE
             WHERE NOT custom AND NOT enabled RETURNING *
        )
        SELECT jsonb_build_object('region_version', jsonb_build_object(
            'deleted_count', (SELECT COUNT(*) FROM deleted_rv),
            'changed_count', (SELECT COUNT(*) FROM changed_rv)
        )) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH activity_category_to_delete AS (
            SELECT to_delete.id AS id_to_delete
                 , replacement.id AS replacement_id
            FROM public.activity_category AS to_delete
            LEFT JOIN public.activity_category AS replacement
              ON to_delete.path = replacement.path
             AND to_delete.standard_id = replacement.standard_id
             AND NOT replacement.custom
            WHERE to_delete.custom
              AND to_delete.enabled
            ORDER BY to_delete.path
        ), updated_child AS (
            UPDATE public.activity_category AS child
               SET parent_id = to_delete.replacement_id
              FROM activity_category_to_delete AS to_delete
               WHERE to_delete.replacement_id IS NOT NULL
                 AND NOT child.custom
                 AND parent_id = to_delete.id_to_delete
            RETURNING *
        ), deleted_activity_category AS (
            DELETE FROM public.activity_category
             WHERE id in (SELECT id_to_delete FROM activity_category_to_delete)
            RETURNING *
        )
        SELECT jsonb_build_object(
            'deleted_count', (SELECT COUNT(*) FROM deleted_activity_category),
            'changed_children_count', (SELECT COUNT(*) FROM updated_child)
        ) INTO changed;

        WITH changed_activity_category AS (
            UPDATE public.activity_category
            SET enabled = TRUE
            WHERE NOT custom
              AND NOT enabled
            RETURNING *
        )
        SELECT changed || jsonb_build_object(
            'changed_count', (SELECT COUNT(*) FROM changed_activity_category)
        ) INTO changed;
        SELECT jsonb_build_object('activity_category', changed) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_sector AS (
            DELETE FROM public.sector WHERE custom RETURNING *
        ), changed_sector AS (
            UPDATE public.sector
               SET enabled = TRUE
             WHERE NOT custom
               AND NOT enabled
             RETURNING *
        )
        SELECT jsonb_build_object(
            'sector', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_sector),
                'changed_count', (SELECT COUNT(*) FROM changed_sector)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_legal_form AS (
            DELETE FROM public.legal_form WHERE custom RETURNING *
        ), changed_legal_form AS (
            UPDATE public.legal_form
               SET enabled = TRUE
             WHERE NOT custom
               AND NOT enabled
             RETURNING *
        )
        SELECT jsonb_build_object(
            'legal_form', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_legal_form),
                'changed_count', (SELECT COUNT(*) FROM changed_legal_form)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_unit_size AS (
            DELETE FROM public.unit_size WHERE custom RETURNING *
        ), changed_unit_size AS (
            UPDATE public.unit_size
               SET enabled = TRUE
             WHERE NOT custom
               AND NOT enabled
             RETURNING *
        )
        SELECT jsonb_build_object(
            'unit_size', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_unit_size),
                'changed_count', (SELECT COUNT(*) FROM changed_unit_size)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_data_source AS (
            DELETE FROM public.data_source WHERE custom RETURNING *
        ), changed_data_source AS (
            UPDATE public.data_source
               SET enabled = TRUE
             WHERE NOT custom
               AND NOT enabled
             RETURNING *
        )
        SELECT jsonb_build_object(
            'data_source', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_data_source),
                'changed_count', (SELECT COUNT(*) FROM changed_data_source)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_status AS (
            DELETE FROM public.status WHERE custom RETURNING *
        ), changed_status AS (
            UPDATE public.status
               SET enabled = TRUE
             WHERE NOT custom
               AND NOT enabled
             RETURNING *
        )
        SELECT jsonb_build_object(
            'status', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_status),
                'changed_count', (SELECT COUNT(*) FROM changed_status)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_foreign_participation AS (
            DELETE FROM public.foreign_participation WHERE custom RETURNING *
        ), changed_foreign_participation AS (
            UPDATE public.foreign_participation
               SET enabled = TRUE
             WHERE NOT custom
               AND NOT enabled
             RETURNING *
        )
        SELECT jsonb_build_object(
            'foreign_participation', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_foreign_participation),
                'changed_count', (SELECT COUNT(*) FROM changed_foreign_participation)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_legal_reorg_type AS (
            DELETE FROM public.legal_reorg_type WHERE custom RETURNING *
        ), changed_legal_reorg_type AS (
            UPDATE public.legal_reorg_type
               SET enabled = TRUE
             WHERE NOT custom
               AND NOT enabled
             RETURNING *
        )
        SELECT jsonb_build_object(
            'legal_reorg_type', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_legal_reorg_type),
                'changed_count', (SELECT COUNT(*) FROM changed_legal_reorg_type)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_power_group_type AS (
            DELETE FROM public.power_group_type WHERE custom RETURNING *
        ), changed_power_group_type AS (
            UPDATE public.power_group_type
               SET enabled = TRUE
             WHERE NOT custom
               AND NOT enabled
             RETURNING *
        )
        SELECT jsonb_build_object(
            'power_group_type', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_power_group_type),
                'changed_count', (SELECT COUNT(*) FROM changed_power_group_type)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_legal_rel_type AS (
            DELETE FROM public.legal_rel_type WHERE custom RETURNING *
        ), changed_legal_rel_type AS (
            UPDATE public.legal_rel_type
               SET enabled = TRUE
             WHERE NOT custom
               AND NOT enabled
             RETURNING *
        )
        SELECT jsonb_build_object(
            'legal_rel_type', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_legal_rel_type),
                'changed_count', (SELECT COUNT(*) FROM changed_legal_rel_type)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    -- ================================================================
    -- Scope: 'all' (adds configuration reset)
    -- ================================================================

    CASE WHEN scope IN ('all') THEN
        WITH deleted_tag AS (
            DELETE FROM public.tag WHERE custom RETURNING *
        ), changed_tag AS (
            UPDATE public.tag
               SET enabled = TRUE
             WHERE NOT custom
               AND NOT enabled
             RETURNING *
        )
        SELECT jsonb_build_object(
            'tag', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_tag),
                'changed_count', (SELECT COUNT(*) FROM changed_tag)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('all') THEN
        WITH deleted_stat_definition AS (
            DELETE FROM public.stat_definition WHERE true RETURNING *
        )
        SELECT jsonb_build_object(
            'stat_definition', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_stat_definition WHERE code NOT IN ('employees','turnover'))
            )
        ) INTO changed;
        result := result || changed;

        INSERT INTO public.stat_definition(code, type, frequency, name, description, priority, enabled)
        VALUES
            ('employees', 'int', 'yearly', 'Employees', 'The number of people receiving an official salary with government reporting.', 1, true),
            ('turnover', 'float', 'yearly', 'Turnover', 'The amount (Local Currency)', 2, true);
    ELSE END CASE;

    CASE WHEN scope IN ('all') THEN
        WITH deleted_external_ident_type AS (
            DELETE FROM public.external_ident_type WHERE true RETURNING *
        )
        SELECT jsonb_build_object(
            'external_ident_type', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_external_ident_type WHERE code NOT IN ('stat_ident','tax_ident','person_ident'))
            )
        ) INTO changed;
        result := result || changed;

        -- Fix 2: Include person_ident in baseline entries
        INSERT INTO public.external_ident_type(code, name, priority, description, enabled)
        VALUES
            ('tax_ident', 'Tax Identifier', 1, 'Stable and country unique identifier used for tax reporting.', true),
            ('stat_ident', 'Statistical Identifier', 2, 'Stable identifier generated by Statbus', true),
            ('person_ident', 'Person Identifier', 10, 'Personal identification number (national ID, passport, etc.)', true);
    ELSE END CASE;

    -- activity_category_standard is system seed data (isic_v4, nace_v2.1) and must
    -- never be deleted by reset(). Custom activity_categories are already handled
    -- by the 'getting-started' scope block above.

    RETURN result;
END;
$function$
;

GRANT TRUNCATE ON public.statistical_unit_facet_staging TO admin_user;

-- Repair caches left stale by earlier resets: one full refresh through the
-- worker pipeline (doc/migration-call-tree-prohibition.md).
DO $statbus_538_full_refresh$
BEGIN
    IF EXISTS (
        SELECT 1 FROM public.establishment
        UNION ALL SELECT 1 FROM public.legal_unit
        UNION ALL SELECT 1 FROM public.enterprise
        UNION ALL SELECT 1 FROM public.power_group
        LIMIT 1
    ) THEN
        PERFORM worker.spawn(
            p_command => 'collect_changes',
            p_payload => jsonb_build_object(
                'establishment_id_ranges', NULL,
                'legal_unit_id_ranges',    NULL,
                'enterprise_id_ranges',    NULL,
                'power_group_id_ranges',   NULL,
                'valid_ranges',            NULL
            )
        );
        PERFORM pg_notify('worker_tasks', 'analytics');
    END IF;
END;
$statbus_538_full_refresh$;

END;
