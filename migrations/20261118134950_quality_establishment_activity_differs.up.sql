-- Migration 20261118134950: quality, the first check: a legal unit whose primary establishment has
-- another primary activity (xz3jej)
--
-- Quality is the area of checks that list units to look at, as opposed to reports, which count
-- them. Each check is a table public.quality_<check>, filled after every recalculation by
-- worker.derive_quality in the reports phase, and joined from statistical_unit by a NOT ENFORCED
-- foreign key so PostgREST embeds it as an ordinary one-to-one relationship:
--   /rest/statistical_unit?select=*,quality_establishment_activity_differs!inner()&unit_type=eq.legal_unit
-- The dashboard's Data quality section counts that, and the search lists it as
-- /search?quality=establishment_activity_differs.
BEGIN;

CREATE TABLE public.quality_establishment_activity_differs (
    unit_type public.statistical_unit_type NOT NULL,
    unit_id integer NOT NULL,
    valid_from date NOT NULL,
    valid_until date NOT NULL,
    valid_range daterange NOT NULL GENERATED ALWAYS AS (daterange(valid_from, valid_until)) STORED,
    legal_unit_activity_category_id integer,
    primary_establishment_id integer NOT NULL,
    primary_establishment_activity_category_id integer,
    CONSTRAINT quality_establishment_activity_differs_pkey
        PRIMARY KEY (unit_type, unit_id, valid_range),
    CONSTRAINT quality_establishment_activity_differs_statistical_unit_fkey
        FOREIGN KEY (unit_type, unit_id, PERIOD valid_range)
        REFERENCES public.statistical_unit (unit_type, unit_id, PERIOD valid_range) NOT ENFORCED
);

COMMENT ON TABLE public.quality_establishment_activity_differs IS
  'Quality check (xz3jej): one row per legal_unit row of statistical_unit whose primary activity category differs from that of its primary establishment (timeline_establishment.primary_for_legal_unit) valid at the row''s valid_from, compared by id, a missing activity on one side counting as a difference. Uses the primary as recorded and never picks one. Filled from quality_establishment_activity_differs_def by quality_establishment_activity_differs_derive(), which worker.derive_quality calls after statistical_unit is published. The dashboard''s Data quality card counts it and the search lists it as select=*,quality_establishment_activity_differs!inner().';
COMMENT ON COLUMN public.quality_establishment_activity_differs.valid_range IS
  'The statistical_unit row''s period. With unit_type and unit_id it is both the primary key and the foreign key to statistical_unit, so PostgREST sees a one-to-one relationship and embeds it as a plain join; another primary key makes it one-to-many, aggregated as JSON per row.';
COMMENT ON CONSTRAINT quality_establishment_activity_differs_statistical_unit_fkey ON public.quality_establishment_activity_differs IS
  'NOT ENFORCED: describes the link for PostgREST and readers; nothing checks it, so derive rewrites statistical_unit freely and the table is made right again by the next worker.derive_quality. Until then a row whose statistical_unit period changed drops out of the inner join. A TRUNCATE of statistical_unit must name this table and say CASCADE: TRUNCATE refuses a NOT ENFORCED key otherwise, even with both tables listed (PostgreSQL 18).';
COMMENT ON COLUMN public.quality_establishment_activity_differs.legal_unit_activity_category_id IS
  'The legal unit''s primary activity category (statistical_unit.primary_activity_category_id), NULL when it has none.';
COMMENT ON COLUMN public.quality_establishment_activity_differs.primary_establishment_id IS
  'The establishment recorded as the legal unit''s primary at valid_from.';
COMMENT ON COLUMN public.quality_establishment_activity_differs.primary_establishment_activity_category_id IS
  'The primary establishment''s primary activity category at valid_from, NULL when it has none.';

CREATE VIEW public.quality_establishment_activity_differs_def
WITH (security_invoker = on) AS
SELECT su.unit_type,
       su.unit_id,
       su.valid_from,
       su.valid_until,
       su.primary_activity_category_id AS legal_unit_activity_category_id,
       te.unit_id AS primary_establishment_id,
       te.primary_activity_category_id AS primary_establishment_activity_category_id
FROM public.statistical_unit AS su
JOIN public.timeline_establishment AS te
  ON te.legal_unit_id = su.unit_id
 AND te.primary_for_legal_unit
 AND te.valid_from <= su.valid_from AND su.valid_from < te.valid_until
WHERE su.unit_type = 'legal_unit'
  AND su.primary_activity_category_id IS DISTINCT FROM te.primary_activity_category_id;

COMMENT ON VIEW public.quality_establishment_activity_differs_def IS
  'The rule of the quality check public.quality_establishment_activity_differs, read from statistical_unit and timeline_establishment.';

GRANT SELECT ON public.quality_establishment_activity_differs_def TO authenticated, regular_user, admin_user;

CREATE FUNCTION public.quality_establishment_activity_differs_derive()
RETURNS void
LANGUAGE plpgsql
AS $quality_establishment_activity_differs_derive$
BEGIN
    RAISE DEBUG 'Running quality_establishment_activity_differs_derive()';
    MERGE INTO public.quality_establishment_activity_differs AS target
    USING public.quality_establishment_activity_differs_def AS source
    ON target.unit_type = source.unit_type
   AND target.unit_id = source.unit_id
   AND target.valid_range = daterange(source.valid_from, source.valid_until)
    WHEN MATCHED AND (
        target.legal_unit_activity_category_id IS DISTINCT FROM source.legal_unit_activity_category_id
        OR target.primary_establishment_id IS DISTINCT FROM source.primary_establishment_id
        OR target.primary_establishment_activity_category_id IS DISTINCT FROM source.primary_establishment_activity_category_id
    ) THEN UPDATE SET
        legal_unit_activity_category_id = source.legal_unit_activity_category_id,
        primary_establishment_id = source.primary_establishment_id,
        primary_establishment_activity_category_id = source.primary_establishment_activity_category_id
    WHEN NOT MATCHED BY TARGET THEN INSERT
        (unit_type, unit_id, valid_from, valid_until, legal_unit_activity_category_id,
         primary_establishment_id, primary_establishment_activity_category_id)
        VALUES (source.unit_type, source.unit_id, source.valid_from, source.valid_until,
                source.legal_unit_activity_category_id, source.primary_establishment_id,
                source.primary_establishment_activity_category_id)
    WHEN NOT MATCHED BY SOURCE THEN DELETE;
    ANALYZE public.quality_establishment_activity_differs;
END;
$quality_establishment_activity_differs_derive$;

COMMENT ON FUNCTION public.quality_establishment_activity_differs_derive() IS
  'Makes the quality check public.quality_establishment_activity_differs equal to its _def view (insert, update, delete); called by worker.derive_quality.';

SELECT admin.add_rls_regular_user_can_read('public.quality_establishment_activity_differs'::regclass);

-- The quality step of the reports phase: runs every quality check after statistical_unit is
-- published. A new check adds its _derive() call and its name here.
CREATE PROCEDURE worker.derive_quality(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'worker', 'pg_temp'
AS $derive_quality$
BEGIN
    PERFORM public.quality_establishment_activity_differs_derive();

    p_info := jsonb_build_object('checks', jsonb_build_array(
        'quality_establishment_activity_differs'
    ));
END;
$derive_quality$;

COMMENT ON PROCEDURE worker.derive_quality(jsonb, jsonb) IS
  'The reports phase''s quality step: runs every quality check (public.quality_<check>_derive()) after statistical_unit is published. SECURITY DEFINER like the other derive steps, because it writes RLS-protected tables for whichever role enqueued the recalculation.';

INSERT INTO worker.command_registry (command, handler_procedure, description, queue) VALUES
    ('derive_quality', 'worker.derive_quality',
     'Run every quality check (public.quality_*) on the published statistical_unit', 'analytics');

-- The progress bar's rows per phase are exactly the steps worker.command_collect_changes spawns,
-- in spawn order (test 371): derive_quality comes after the facet reduce. Weight 1: the one check
-- takes about 5 s of a full Norway recalculation (local 2026-11-18), weights are seconds / 10.
UPDATE worker.pipeline_step_weight SET seq = 8 WHERE step = 'statistical_history_facet_delta_reduce';
INSERT INTO worker.pipeline_step_weight (phase, step, weight, seq) VALUES
    ('is_deriving_reports', 'derive_quality', 1, 7);

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
    v_all_units BOOLEAN;
BEGIN
    -- Lock the pending-flag singleton before the drain snapshot. Publishers
    -- (worker.publish_base_change_wakeup) update the same row, so a change
    -- committed after this snapshot sets the flag only after the clear below,
    -- and the flag stays TRUE for the next collector.
    PERFORM 1 FROM worker.base_change_log_has_pending FOR UPDATE;

    v_direct_mode :=
        p_payload ? 'establishment_id_ranges'
        OR p_payload ? 'legal_unit_id_ranges'
        OR p_payload ? 'enterprise_id_ranges'
        OR p_payload ? 'power_group_id_ranges';

    -- STATBUS-538: "everything" is one convention, carried through unchanged
    -- so every step decides from its own arguments: NULL for all four
    -- *_id_ranges means all units (worker.derive_statistical_unit's full
    -- branch), and valid_from = -infinity, valid_until = infinity means all
    -- time (the report derives then rebuild their whole per-slot cache).
    -- worker.enqueue_derive_statistical_unit_all() schedules exactly this.
    v_all_units := v_direct_mode
        AND NULLIF(p_payload->>'establishment_id_ranges', '') IS NULL
        AND NULLIF(p_payload->>'legal_unit_id_ranges', '') IS NULL
        AND NULLIF(p_payload->>'enterprise_id_ranges', '') IS NULL
        AND NULLIF(p_payload->>'power_group_id_ranges', '') IS NULL;

    IF v_all_units THEN
        -- All units: ids stay NULL, time defaults to all time. The full
        -- derive covers every logged change, so the log is drained too.
        v_est_ids := NULL;
        v_lu_ids := NULL;
        v_ent_ids := NULL;
        v_pg_ids := NULL;
        v_valid_range := COALESCE(
            NULLIF(p_payload->>'valid_ranges', '')::datemultirange,
            '{[-infinity,infinity)}'::datemultirange
        );
        DELETE FROM worker.base_change_log WHERE true; -- every row: a full-range derive supersedes all logged changes
        UPDATE worker.base_change_log_has_pending SET has_pending = FALSE WHERE has_pending;
    ELSIF v_direct_mode THEN
        -- Caller supplied explicit ranges. A NULL / JSON-null value for a
        -- given key means "all ids of that kind" — synthesise from base
        -- tables, because worker.derive_statistical_unit reads a NULL kind
        -- next to explicit kinds as none.
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
        UPDATE worker.base_change_log_has_pending SET has_pending = FALSE WHERE has_pending;
    ELSE
        -- Drain-log mode: unchanged from 20260319124229.
        FOR v_row IN DELETE FROM worker.base_change_log WHERE true RETURNING * LOOP -- every row: the drain takes all logged changes
            v_est_ids := v_est_ids + v_row.establishment_ids;
            v_lu_ids := v_lu_ids + v_row.legal_unit_ids;
            v_ent_ids := v_ent_ids + v_row.enterprise_ids;
            v_pg_ids := v_pg_ids + v_row.power_group_ids;
            v_valid_range := v_valid_range + v_row.valid_ranges;
        END LOOP;

        UPDATE worker.base_change_log_has_pending SET has_pending = FALSE WHERE has_pending;
    END IF;

    IF v_all_units
       OR v_est_ids != '{}'::int4multirange
       OR v_lu_ids != '{}'::int4multirange
       OR v_ent_ids != '{}'::int4multirange
       OR v_pg_ids != '{}'::int4multirange THEN

        -- Get own task_id for spawning children
        SELECT id INTO v_task_id
        FROM worker.tasks
        WHERE state = 'processing' AND worker_pid = pg_backend_pid()
        ORDER BY id DESC LIMIT 1;

        IF v_all_units THEN
            p_info := jsonb_build_object(
                'affected_establishment_count', (SELECT count(*) FROM public.establishment),
                'affected_legal_unit_count', (SELECT count(*) FROM public.legal_unit),
                'affected_enterprise_count', (SELECT count(*) FROM public.enterprise),
                'affected_power_group_count', (SELECT count(*) FROM public.power_group)
            );
        ELSE
            p_info := jsonb_build_object(
                'affected_establishment_count', (SELECT COALESCE(sum(upper(r) - lower(r)), 0) FROM unnest(v_est_ids) AS r),
                'affected_legal_unit_count', (SELECT COALESCE(sum(upper(r) - lower(r)), 0) FROM unnest(v_lu_ids) AS r),
                'affected_enterprise_count', (SELECT COALESCE(sum(upper(r) - lower(r)), 0) FROM unnest(v_ent_ids) AS r),
                'affected_power_group_count', (SELECT COALESCE(sum(upper(r) - lower(r)), 0) FROM unnest(v_pg_ids) AS r)
            );
        END IF;

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
            'valid_until', v_valid_until
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
            p_command => 'derive_statistical_history_facet_delta',
            p_payload => v_payload,
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

        -- Quality checks read the published statistical_unit; worker.derive_quality runs them all.
        PERFORM worker.spawn(
            p_command => 'derive_quality',
            p_payload => v_payload,
            p_parent_id => v_phase2_id,
            p_child_mode => 'serial'
        );

        PERFORM worker.spawn(
            p_command => 'statistical_history_facet_delta_reduce',
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

CREATE OR REPLACE FUNCTION admin.apply_rls_to_all_tables()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- To list all tables in public schema, run in psql:
    -- SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;
    --
    -- ########### add_rls_regular_user_can_read ###########
    PERFORM admin.add_rls_regular_user_can_read('public.activity_category'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.region'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.sector'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.legal_form'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.activity_category_standard'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.settings'::regclass);
    -- We don't need to apply the standard RLS function to activity_category_access
    -- as it has custom policies that only allow admin_user to modify it
    -- PERFORM admin.add_rls_regular_user_can_read('public.activity_category_access'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.country'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.data_source'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.tag'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.unit_size'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.power_group_type'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.legal_reorg_type'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.legal_rel_type'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.foreign_participation'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.status'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.external_ident_type'::regclass);

    PERFORM admin.add_rls_regular_user_can_read('public.person_role'::regclass);
    -- We don't need to apply the standard RLS function to region_access
    -- as it has custom policies that only allow admin_user to modify it
    -- PERFORM admin.add_rls_regular_user_can_read('public.region_access'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.stat_definition'::regclass);
    -- Is updated by the statbus worker, using authorized functions.
    PERFORM admin.add_rls_regular_user_can_read('public.timepoints'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.timesegments'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.timesegments_years'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.timeline_establishment'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.timeline_legal_unit'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.timeline_enterprise'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.statistical_unit'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.activity_category_used'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.region_used'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.sector_used'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.data_source_used'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.legal_form_used'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.country_used'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.statistical_unit_facet'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.statistical_history_facet_delta'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.statistical_history_period'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.quality_establishment_activity_differs'::regclass);
    --
    -- ########### add_rls_regular_user_can_edit ###########
    PERFORM admin.add_rls_regular_user_can_edit('public.image'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.establishment'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.legal_unit'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.enterprise'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.power_group'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.power_root'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.external_ident'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.activity'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.contact'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.unit_notes'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.tag_for_unit'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.stat_for_unit'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.person_for_unit'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.person'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.location'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.legal_relationship'::regclass);
    --
END;
$function$
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

        -- statistical_unit is emptied together with quality_establishment_activity_differs, which
        -- references it by a NOT ENFORCED foreign key: TRUNCATE refuses such a key without CASCADE,
        -- even with both tables listed. CASCADE is kept to this statement so that a new enforced
        -- key to any table in the list below still stops reset instead of emptying its table.
        TRUNCATE public.statistical_unit, public.quality_establishment_activity_differs CASCADE;

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
            public.statistical_unit_facet,
            public.statistical_unit_facet_staging,
            public.statistical_unit_facet_dirty_hash_slots,
            public.statistical_history_facet_delta,
            public.statistical_history_facet_delta_staging,
            public.statistical_history_period;

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

CREATE OR REPLACE PROCEDURE public.statistical_unit_refresh(IN p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange, IN p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange, IN p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange, IN p_power_group_id_ranges int4multirange DEFAULT NULL::int4multirange)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_batch_size INT := 262144;
    v_min_id int; v_max_id int; v_start_id int; v_end_id int;
    v_batch_num INT; v_total_units INT;
    v_batch_start_time timestamptz; v_batch_duration_ms numeric; v_batch_speed numeric; v_current_batch_size int;
    v_is_partial_refresh BOOLEAN;
    v_col_list TEXT;
BEGIN
    v_is_partial_refresh := (p_establishment_id_ranges IS NOT NULL
                            OR p_legal_unit_id_ranges IS NOT NULL
                            OR p_enterprise_id_ranges IS NOT NULL
                            OR p_power_group_id_ranges IS NOT NULL);

    -- Column list used for all INSERT statements (excludes GENERATED valid_range)
    v_col_list := 'unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
        primary_activity_category_id, primary_activity_category_path, primary_activity_category_code,
        secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code,
        activity_category_paths, sector_id, sector_path, sector_code, sector_name,
        data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name,
        physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace,
        physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2,
        physical_latitude, physical_longitude, physical_altitude, domestic,
        postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace,
        postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2,
        postal_latitude, postal_longitude, postal_altitude,
        web_address, email_address, phone_number, landline, mobile_number, fax_number,
        unit_size_id, unit_size_code, status_id, status_code, used_for_counting,
        last_edit_comment, last_edit_by_user_id, last_edit_at, has_legal_unit,
        related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
        related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
        related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
        stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths';

    IF NOT v_is_partial_refresh THEN
        ANALYZE public.timeline_establishment, public.timeline_legal_unit, public.timeline_enterprise, public.timeline_power_group;
        CREATE TEMP TABLE statistical_unit_new (LIKE public.statistical_unit) ON COMMIT DROP;
        ALTER TABLE statistical_unit_new DROP COLUMN IF EXISTS valid_range;

        -- Establishments
        v_batch_num := 0;
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = 'establishment';
        RAISE DEBUG 'Refreshing statistical units for % establishments...', v_total_units;
        IF v_min_id IS NOT NULL THEN FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_num := v_batch_num + 1; v_start_id := i; v_end_id := i + v_batch_size - 1;
            EXECUTE format('INSERT INTO statistical_unit_new (%s) SELECT %s FROM public.statistical_unit_def WHERE unit_type = %L AND unit_id BETWEEN %s AND %s', v_col_list, v_col_list, 'establishment', v_start_id, v_end_id);
        END LOOP; END IF;

        -- Legal Units
        v_batch_num := 0;
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = 'legal_unit';
        RAISE DEBUG 'Refreshing statistical units for % legal units...', v_total_units;
        IF v_min_id IS NOT NULL THEN FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_num := v_batch_num + 1; v_start_id := i; v_end_id := i + v_batch_size - 1;
            EXECUTE format('INSERT INTO statistical_unit_new (%s) SELECT %s FROM public.statistical_unit_def WHERE unit_type = %L AND unit_id BETWEEN %s AND %s', v_col_list, v_col_list, 'legal_unit', v_start_id, v_end_id);
        END LOOP; END IF;

        -- Enterprises
        v_batch_num := 0;
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = 'enterprise';
        RAISE DEBUG 'Refreshing statistical units for % enterprises...', v_total_units;
        IF v_min_id IS NOT NULL THEN FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_num := v_batch_num + 1; v_start_id := i; v_end_id := i + v_batch_size - 1;
            EXECUTE format('INSERT INTO statistical_unit_new (%s) SELECT %s FROM public.statistical_unit_def WHERE unit_type = %L AND unit_id BETWEEN %s AND %s', v_col_list, v_col_list, 'enterprise', v_start_id, v_end_id);
        END LOOP; END IF;

        -- Power Groups
        v_batch_num := 0;
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = 'power_group';
        RAISE DEBUG 'Refreshing statistical units for % power groups...', v_total_units;
        IF v_min_id IS NOT NULL THEN FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_num := v_batch_num + 1; v_start_id := i; v_end_id := i + v_batch_size - 1;
            EXECUTE format('INSERT INTO statistical_unit_new (%s) SELECT %s FROM public.statistical_unit_def WHERE unit_type = %L AND unit_id BETWEEN %s AND %s', v_col_list, v_col_list, 'power_group', v_start_id, v_end_id);
        END LOOP; END IF;

        -- quality_establishment_activity_differs points at the rows replaced here and is refilled by
        -- the next worker.derive_quality. It references statistical_unit by a NOT ENFORCED foreign
        -- key, which TRUNCATE refuses without CASCADE even with both tables listed.
        TRUNCATE public.statistical_unit, public.quality_establishment_activity_differs CASCADE;
        EXECUTE format('INSERT INTO public.statistical_unit (%s) SELECT %s FROM statistical_unit_new', v_col_list, v_col_list);
        ANALYZE public.statistical_unit;
    ELSE
        -- Partial refresh: Write to staging table
        IF p_establishment_id_ranges IS NOT NULL THEN
            DELETE FROM public.statistical_unit_staging WHERE unit_type = 'establishment' AND unit_id = ANY(public.int4multirange_to_array(p_establishment_id_ranges));
            EXECUTE format('INSERT INTO public.statistical_unit_staging (%s) SELECT %s FROM import.get_statistical_unit_data_partial(%L, %L::int4multirange)', v_col_list, v_col_list, 'establishment', p_establishment_id_ranges::text);
        END IF;
        IF p_legal_unit_id_ranges IS NOT NULL THEN
            DELETE FROM public.statistical_unit_staging WHERE unit_type = 'legal_unit' AND unit_id = ANY(public.int4multirange_to_array(p_legal_unit_id_ranges));
            EXECUTE format('INSERT INTO public.statistical_unit_staging (%s) SELECT %s FROM import.get_statistical_unit_data_partial(%L, %L::int4multirange)', v_col_list, v_col_list, 'legal_unit', p_legal_unit_id_ranges::text);
        END IF;
        IF p_enterprise_id_ranges IS NOT NULL THEN
            DELETE FROM public.statistical_unit_staging WHERE unit_type = 'enterprise' AND unit_id = ANY(public.int4multirange_to_array(p_enterprise_id_ranges));
            EXECUTE format('INSERT INTO public.statistical_unit_staging (%s) SELECT %s FROM import.get_statistical_unit_data_partial(%L, %L::int4multirange)', v_col_list, v_col_list, 'enterprise', p_enterprise_id_ranges::text);
        END IF;
        IF p_power_group_id_ranges IS NOT NULL THEN
            DELETE FROM public.statistical_unit_staging WHERE unit_type = 'power_group' AND unit_id = ANY(public.int4multirange_to_array(p_power_group_id_ranges));
            EXECUTE format('INSERT INTO public.statistical_unit_staging (%s) SELECT %s FROM import.get_statistical_unit_data_partial(%L, %L::int4multirange)', v_col_list, v_col_list, 'power_group', p_power_group_id_ranges::text);
        END IF;
    END IF;
END;
$procedure$
;

-- Fill the quality check from the statistical_unit already derived on this database.
SELECT public.quality_establishment_activity_differs_derive();

NOTIFY pgrst, 'reload schema';

END;
