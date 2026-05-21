-- Migration: Fix statistical_history_facet indexes to match source GROUP BY
--
-- Issue #53/#61: The reduce function groups by 12 columns (including unit_size_id, status_id)
-- but the target indexes only constrained 10/9 columns, causing duplicate-key collisions.
--
-- Fix: Expand both partial unique indexes to include unit_size_id and status_id,
-- and change NULL semantics from NULLS DISTINCT (default) to NULLS NOT DISTINCT
-- to match the partitions table's UNIQUE constraint.
--
-- Backfill strategy: replaced the original synchronous
-- statistical_history_facet_derive('-infinity','infinity') call with an
-- EXISTS-guarded `collect_changes` spawn (fire-and-forget). Rationale:
-- the synchronous derive stalls the migration at production scale —
-- observed 33+ min on dev before the upgrade daemon crashed. The
-- async pattern lets the migration commit promptly and the worker
-- daemon drives an incremental, chunked rebuild post-COMMIT, distributed
-- across the worker pool. Pattern follows migration 20260520204526
-- (full rationale block at lines 297-372 of that file).
--
-- BUNDLED FUNCTION FIX: worker.spawn — ON CONFLICT DO NOTHING
--
-- worker.tasks carries a partial unique index
--   idx_tasks_collect_changes_dedup
--   ON worker.tasks (command) WHERE command='collect_changes' AND state='pending'
-- that allows AT MOST ONE pending collect_changes task. The original
-- worker.spawn body did a plain `INSERT … RETURNING id` with NO
-- conflict handling — if a pending collect_changes row already exists
-- (very common during an upgrade window because the worker daemon is
-- paused), the next spawn raises unique_violation and rolls back the
-- enclosing transaction.
--
-- That is exactly how dev's v2026.05.3 cut failed today: migration
-- 20260520204526 (also using worker.spawn for collect_changes) had its
-- task pending+undrained because the worker daemon was paused. When
-- this migration's spawn fired, unique_violation aborted it, the
-- upgrade-service died, systemd kill-restart-looped 76+ times.
--
-- The fix lives in worker.spawn itself (where the bug is), not in the
-- migration's call site (which is canonical usage). worker.spawn IS the
-- authoritative spawn helper; callers should not have to know about
-- specific dedup indexes on specific commands. Adding ON CONFLICT DO
-- NOTHING to its INSERT makes the helper idempotent under any partial
-- unique index on worker.tasks (today: just the collect_changes dedup;
-- tomorrow: any other dedup-keyed command added without per-caller
-- changes).
--
-- Bundled here because this migration is the first dedicated user that
-- surfaces the bug, and bundling correlated function + schema fixes in
-- the same migration is the canonical Statbus pattern. Body captured
-- verbatim via `\sf worker.spawn` then a single line added:
-- `ON CONFLICT DO NOTHING` between the VALUES clause and the RETURNING
-- clause.
--
-- Call-graph safety (verified): the only command with a dedup partial
-- unique index on worker.tasks is collect_changes. All id-capturing
-- callers (worker.command_collect_changes captures v_phase1_id from
-- spawn('derive_units_phase',...) etc.) spawn NON-dedup-keyed commands;
-- they cannot collision-fire, so they're unaffected. The change is
-- functionally a no-op for them.
--
-- Constraints honoured by the collect_changes call below:
--   • EXISTS guard on base tables → empty seed/test_template fixtures are
--     a no-op; no phantom worker.tasks row pollutes the seed dump.
--   • Spawn happens INSIDE the migration TX → atomic with the index
--     swap; after COMMIT the worker daemon picks up the task via
--     pg_notify and starts the rebuild without further intervention.
--   • NULL-valued id-range keys in the payload → worker synthesises full
--     id sets from base tables (the canonical full-rebuild contract).
--   • worker.spawn is now ON CONFLICT DO NOTHING → if a pending
--     collect_changes already exists, this enqueue is a clean no-op
--     instead of unique_violation-aborting the migration.
--
-- TRUNCATE of statistical_unit_facet_dirty_hash_slots is preserved (not
-- moved to the worker): the migration window is the natural place for
-- one-shot legacy cleanup of dirty markers accumulated through pre-fix
-- reduce-failure retry cycles. The subsequent async rebuild repopulates
-- the queue correctly from base-table units. Keeping the TRUNCATE here
-- (a) avoids coupling cleanup semantics to specific rebuild invocations,
-- (b) stays atomic with the schema swap, and (c) is the shape tcc already
-- validated on small data — only the synchronous derive was problematic.

BEGIN;

-- ───────────────────────────────────────────────────────────────────────
-- Function fix: worker.spawn — add ON CONFLICT DO NOTHING to the INSERT
-- so the helper is idempotent against partial unique indexes (today:
-- idx_tasks_collect_changes_dedup; tomorrow: any future dedup-keyed
-- command). Body captured verbatim via `\sf worker.spawn`; the only
-- diff vs the prior shape is the single `ON CONFLICT DO NOTHING` line
-- inserted between the VALUES clause and the RETURNING clause.
--
-- See header for full rationale and call-graph safety analysis.
-- ───────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION worker.spawn(p_command text, p_payload jsonb DEFAULT '{}'::jsonb, p_parent_id bigint DEFAULT NULL::bigint, p_priority bigint DEFAULT NULL::bigint, p_child_mode worker.child_mode DEFAULT NULL::worker.child_mode)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_task_id BIGINT;
    v_priority BIGINT;
    v_depth INT;
BEGIN
    IF p_priority IS NOT NULL THEN
        v_priority := p_priority;
    ELSE
        v_priority := nextval('public.worker_task_priority_seq');
    END IF;

    -- Add command to payload if not present
    IF p_payload IS NULL OR p_payload = '{}'::jsonb THEN
        p_payload := jsonb_build_object('command', p_command);
    ELSIF p_payload->>'command' IS NULL THEN
        p_payload := p_payload || jsonb_build_object('command', p_command);
    END IF;

    -- Calculate depth from parent
    IF p_parent_id IS NOT NULL THEN
        SELECT depth + 1 INTO v_depth FROM worker.tasks WHERE id = p_parent_id;
        IF v_depth IS NULL THEN
            RAISE EXCEPTION 'Parent task % not found', p_parent_id;
        END IF;

        -- Set parent's child_mode if not already set (defaults to 'concurrent')
        UPDATE worker.tasks
        SET child_mode = COALESCE(p_child_mode, 'concurrent')
        WHERE id = p_parent_id AND child_mode IS NULL;

        -- Fail fast if caller requests a mode that conflicts with what's already set
        IF p_child_mode IS NOT NULL THEN
            DECLARE
                v_existing_child_mode worker.child_mode;
            BEGIN
                SELECT child_mode INTO v_existing_child_mode
                FROM worker.tasks WHERE id = p_parent_id;
                IF v_existing_child_mode != p_child_mode THEN
                    RAISE EXCEPTION 'Parent task % already has child_mode=%, cannot set to %',
                        p_parent_id, v_existing_child_mode, p_child_mode;
                END IF;
            END;
        END IF;
    ELSE
        v_depth := 0;
    END IF;

    INSERT INTO worker.tasks (command, payload, parent_id, priority, depth)
    VALUES (p_command, p_payload, p_parent_id, v_priority, v_depth)
    ON CONFLICT DO NOTHING
    RETURNING id INTO v_task_id;

    PERFORM pg_notify('worker_tasks', (
        SELECT queue FROM worker.command_registry WHERE command = p_command
    ));

    RETURN v_task_id;
END;
$function$;

-- Drop the old 10-col and 9-col partial unique indexes
DROP INDEX IF EXISTS public.statistical_history_facet_month_key;
DROP INDEX IF EXISTS public.statistical_history_facet_year_key;

-- Create new 12-col partial unique index for year-month resolution
CREATE UNIQUE INDEX statistical_history_facet_month_key
ON public.statistical_history_facet (
    resolution, year, month, unit_type,
    primary_activity_category_path, secondary_activity_category_path,
    sector_path, legal_form_id, physical_region_path,
    physical_country_id, unit_size_id, status_id
)
NULLS NOT DISTINCT
WHERE resolution = 'year-month'::history_resolution;

-- Create new 11-col partial unique index for year resolution
CREATE UNIQUE INDEX statistical_history_facet_year_key
ON public.statistical_history_facet (
    year, month, unit_type,
    primary_activity_category_path, secondary_activity_category_path,
    sector_path, legal_form_id, physical_region_path,
    physical_country_id, unit_size_id, status_id
)
NULLS NOT DISTINCT
WHERE resolution = 'year'::history_resolution;

-- Clean up stale dirty hash slot markers from pre-fix reduce-failure
-- retry cycles (see header for rationale).
TRUNCATE public.statistical_unit_facet_dirty_hash_slots;

-- Spawn the canonical direct-mode full-rebuild via the worker pipeline.
-- EXISTS guard makes this a no-op on fresh/seed/test_template installs
-- (the guarded SELECTs all return zero rows on an empty fixture, so the
-- spawn is skipped and worker.tasks stays empty).
DO $facet_indexes_backfill_rebuild$
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
END
$facet_indexes_backfill_rebuild$;

COMMIT;
