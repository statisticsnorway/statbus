-- Down Migration 20260324203631: fix_notify_progress_collect_changes_state
-- Restore all three functions to their pre-migration state.
BEGIN;

CREATE OR REPLACE FUNCTION worker.notify_task_progress()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_payload JSONB;
    v_phases JSONB := '[]'::jsonb;
    v_units_phase JSONB;
    v_reports_phase JSONB;
    v_units_active BOOLEAN;
    v_units_step TEXT;
    v_units_total BIGINT;
    v_units_completed BIGINT;
    v_affected_est INT;
    v_affected_lu INT;
    v_affected_en INT;
    v_affected_pg INT;
    v_reports_active BOOLEAN;
    v_reports_step TEXT;
    v_reports_total BIGINT;
    v_reports_completed BIGINT;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM worker.tasks
        WHERE command IN ('collect_changes', 'derive_units_phase', 'derive_statistical_unit', 'statistical_unit_refresh_batch', 'statistical_unit_flush_staging')
          AND state IN ('pending', 'processing', 'waiting')
    ) INTO v_units_active;

    IF v_units_active THEN
        SELECT t.command INTO v_units_step
        FROM worker.tasks AS t
        WHERE t.command IN ('collect_changes', 'derive_units_phase', 'derive_statistical_unit', 'statistical_unit_refresh_batch', 'statistical_unit_flush_staging')
          AND (t.state IN ('processing', 'waiting') OR (t.command = 'collect_changes' AND t.state = 'pending'))
        ORDER BY t.id DESC LIMIT 1;

        SELECT count(*) INTO v_units_total
        FROM worker.tasks AS t
        WHERE t.command = 'statistical_unit_refresh_batch'
          AND EXISTS (
              SELECT 1 FROM worker.tasks AS p
              WHERE p.id = t.parent_id
                AND p.command = 'derive_statistical_unit'
                AND p.state IN ('processing', 'waiting')
          );

        SELECT count(*) INTO v_units_completed
        FROM worker.tasks AS t
        WHERE t.state IN ('completed', 'failed')
          AND t.command = 'statistical_unit_refresh_batch'
          AND EXISTS (
              SELECT 1 FROM worker.tasks AS p
              WHERE p.id = t.parent_id
                AND p.command = 'derive_statistical_unit'
                AND p.state IN ('processing', 'waiting')
          );

        SELECT (t.info->>'effective_establishment_count')::int,
               (t.info->>'effective_legal_unit_count')::int,
               (t.info->>'effective_enterprise_count')::int,
               (t.info->>'effective_power_group_count')::int
        INTO v_affected_est, v_affected_lu, v_affected_en, v_affected_pg
        FROM worker.tasks AS t
        WHERE t.command = 'derive_statistical_unit'
          AND t.state IN ('processing', 'waiting')
        ORDER BY t.id DESC LIMIT 1;

        v_units_phase := jsonb_build_object(
            'phase', 'is_deriving_statistical_units',
            'step', v_units_step,
            'total', COALESCE(v_units_total, 0),
            'completed', COALESCE(v_units_completed, 0),
            'effective_establishment_count', v_affected_est,
            'effective_legal_unit_count', v_affected_lu,
            'effective_enterprise_count', v_affected_en,
            'effective_power_group_count', v_affected_pg
        );
        v_phases := v_phases || jsonb_build_array(v_units_phase);
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM worker.tasks
        WHERE command IN ('derive_reports_phase', 'derive_reports', 'derive_statistical_history', 'derive_statistical_history_period',
                         'statistical_history_reduce', 'derive_statistical_unit_facet',
                         'derive_statistical_unit_facet_partition', 'statistical_unit_facet_reduce',
                         'derive_statistical_history_facet', 'derive_statistical_history_facet_period',
                         'statistical_history_facet_reduce')
          AND state IN ('pending', 'processing', 'waiting')
    ) INTO v_reports_active;

    IF v_reports_active THEN
        SELECT t.command INTO v_reports_step
        FROM worker.tasks AS t
        WHERE t.command IN ('derive_reports_phase', 'derive_reports', 'derive_statistical_history',
                           'statistical_history_reduce', 'derive_statistical_unit_facet',
                           'statistical_unit_facet_reduce', 'derive_statistical_history_facet',
                           'statistical_history_facet_reduce')
          AND t.state IN ('processing', 'waiting')
        ORDER BY t.id DESC LIMIT 1;

        SELECT count(*) INTO v_reports_total
        FROM worker.tasks AS t
        WHERE EXISTS (
              SELECT 1 FROM worker.tasks AS p
              WHERE p.id = t.parent_id
                AND p.state IN ('processing', 'waiting')
                AND p.command IN ('derive_statistical_history', 'derive_statistical_unit_facet',
                                'derive_statistical_history_facet')
          );

        SELECT count(*) INTO v_reports_completed
        FROM worker.tasks AS t
        WHERE t.state IN ('completed', 'failed')
          AND EXISTS (
              SELECT 1 FROM worker.tasks AS p
              WHERE p.id = t.parent_id
                AND p.state IN ('processing', 'waiting')
                AND p.command IN ('derive_statistical_history', 'derive_statistical_unit_facet',
                                'derive_statistical_history_facet')
          );

        IF v_affected_est IS NULL THEN
            SELECT (t.info->>'effective_establishment_count')::int,
                   (t.info->>'effective_legal_unit_count')::int,
                   (t.info->>'effective_enterprise_count')::int,
                   (t.info->>'effective_power_group_count')::int
            INTO v_affected_est, v_affected_lu, v_affected_en, v_affected_pg
            FROM worker.tasks AS t
            WHERE t.command = 'derive_statistical_unit'
              AND t.state IN ('completed', 'waiting')
            ORDER BY t.id DESC LIMIT 1;
        END IF;

        v_reports_phase := jsonb_build_object(
            'phase', 'is_deriving_reports',
            'step', v_reports_step,
            'total', COALESCE(v_reports_total, 0),
            'completed', COALESCE(v_reports_completed, 0),
            'effective_establishment_count', v_affected_est,
            'effective_legal_unit_count', v_affected_lu,
            'effective_enterprise_count', v_affected_en,
            'effective_power_group_count', v_affected_pg
        );
        v_phases := v_phases || jsonb_build_array(v_reports_phase);
    END IF;

    IF jsonb_array_length(v_phases) > 0 THEN
        v_payload := jsonb_build_object('type', 'pipeline_progress', 'phases', v_phases);
        PERFORM pg_notify('worker_status', v_payload::text);
    END IF;

    IF NOT v_units_active THEN
        PERFORM pg_notify('worker_status',
            json_build_object('type', 'is_deriving_statistical_units', 'status', false)::text);
    END IF;
    IF NOT v_reports_active THEN
        PERFORM pg_notify('worker_status',
            json_build_object('type', 'is_deriving_reports', 'status', false)::text);
    END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.is_deriving_statistical_units()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
    SELECT jsonb_build_object(
        'active', EXISTS (
            SELECT 1 FROM worker.tasks
            WHERE command IN ('collect_changes', 'derive_units_phase', 'derive_statistical_unit', 'statistical_unit_refresh_batch', 'statistical_unit_flush_staging')
              AND state IN ('pending', 'processing', 'waiting')
        ),
        'step', (
            SELECT t.command FROM worker.tasks AS t
            WHERE t.command IN ('collect_changes', 'derive_units_phase', 'derive_statistical_unit', 'statistical_unit_refresh_batch', 'statistical_unit_flush_staging')
              AND (t.state IN ('processing', 'waiting') OR (t.command = 'collect_changes' AND t.state = 'pending'))
            ORDER BY t.id DESC LIMIT 1
        ),
        'total', COALESCE((
            SELECT count(*) FROM worker.tasks AS t
            WHERE t.command = 'statistical_unit_refresh_batch'
              AND EXISTS (
                  SELECT 1 FROM worker.tasks AS p
                  WHERE p.id = t.parent_id
                    AND p.command = 'derive_statistical_unit'
                    AND p.state IN ('processing', 'waiting')
              )
        ), 0),
        'completed', COALESCE((
            SELECT count(*) FROM worker.tasks AS t
            WHERE t.state IN ('completed', 'failed')
              AND t.command = 'statistical_unit_refresh_batch'
              AND EXISTS (
                  SELECT 1 FROM worker.tasks AS p
                  WHERE p.id = t.parent_id
                    AND p.command = 'derive_statistical_unit'
                    AND p.state IN ('processing', 'waiting')
              )
        ), 0),
        'effective_establishment_count', (
            SELECT (t.info->>'effective_establishment_count')::int
            FROM worker.tasks AS t
            WHERE t.command = 'derive_statistical_unit'
              AND t.state IN ('processing', 'waiting')
            ORDER BY t.id DESC LIMIT 1
        ),
        'effective_legal_unit_count', (
            SELECT (t.info->>'effective_legal_unit_count')::int
            FROM worker.tasks AS t
            WHERE t.command = 'derive_statistical_unit'
              AND t.state IN ('processing', 'waiting')
            ORDER BY t.id DESC LIMIT 1
        ),
        'effective_enterprise_count', (
            SELECT (t.info->>'effective_enterprise_count')::int
            FROM worker.tasks AS t
            WHERE t.command = 'derive_statistical_unit'
              AND t.state IN ('processing', 'waiting')
            ORDER BY t.id DESC LIMIT 1
        ),
        'effective_power_group_count', (
            SELECT (t.info->>'effective_power_group_count')::int
            FROM worker.tasks AS t
            WHERE t.command = 'derive_statistical_unit'
              AND t.state IN ('processing', 'waiting')
            ORDER BY t.id DESC LIMIT 1
        )
    );
$function$;

CREATE OR REPLACE FUNCTION public.is_deriving_reports()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
    SELECT jsonb_build_object(
        'active', EXISTS (
            SELECT 1 FROM worker.tasks
            WHERE command IN ('derive_reports_phase', 'derive_reports', 'derive_statistical_history', 'derive_statistical_history_period',
                            'statistical_history_reduce', 'derive_statistical_unit_facet',
                            'derive_statistical_unit_facet_partition', 'statistical_unit_facet_reduce',
                            'derive_statistical_history_facet', 'derive_statistical_history_facet_period',
                            'statistical_history_facet_reduce')
              AND state IN ('pending', 'processing', 'waiting')
        ),
        'step', (
            SELECT t.command FROM worker.tasks AS t
            WHERE t.command IN ('derive_reports_phase', 'derive_reports', 'derive_statistical_history',
                               'statistical_history_reduce', 'derive_statistical_unit_facet',
                               'statistical_unit_facet_reduce', 'derive_statistical_history_facet',
                               'statistical_history_facet_reduce')
              AND t.state IN ('processing', 'waiting')
            ORDER BY t.id DESC LIMIT 1
        ),
        'total', COALESCE((
            SELECT count(*) FROM worker.tasks AS t
            WHERE EXISTS (
                  SELECT 1 FROM worker.tasks AS p
                  WHERE p.id = t.parent_id
                    AND p.state IN ('processing', 'waiting')
                    AND p.command IN ('derive_statistical_history', 'derive_statistical_unit_facet',
                                    'derive_statistical_history_facet')
              )
        ), 0),
        'completed', COALESCE((
            SELECT count(*) FROM worker.tasks AS t
            WHERE t.state IN ('completed', 'failed')
              AND EXISTS (
                  SELECT 1 FROM worker.tasks AS p
                  WHERE p.id = t.parent_id
                    AND p.state IN ('processing', 'waiting')
                    AND p.command IN ('derive_statistical_history', 'derive_statistical_unit_facet',
                                    'derive_statistical_history_facet')
              )
        ), 0),
        'effective_establishment_count', (
            SELECT (t.info->>'effective_establishment_count')::int
            FROM worker.tasks AS t
            WHERE t.command = 'derive_statistical_unit'
              AND t.state IN ('completed', 'waiting')
            ORDER BY t.id DESC LIMIT 1
        ),
        'effective_legal_unit_count', (
            SELECT (t.info->>'effective_legal_unit_count')::int
            FROM worker.tasks AS t
            WHERE t.command = 'derive_statistical_unit'
              AND t.state IN ('completed', 'waiting')
            ORDER BY t.id DESC LIMIT 1
        ),
        'effective_enterprise_count', (
            SELECT (t.info->>'effective_enterprise_count')::int
            FROM worker.tasks AS t
            WHERE t.command = 'derive_statistical_unit'
              AND t.state IN ('completed', 'waiting')
            ORDER BY t.id DESC LIMIT 1
        ),
        'effective_power_group_count', (
            SELECT (t.info->>'effective_power_group_count')::int
            FROM worker.tasks AS t
            WHERE t.command = 'derive_statistical_unit'
              AND t.state IN ('completed', 'waiting')
            ORDER BY t.id DESC LIMIT 1
        )
    );
$function$;

END;
