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
-- Constraints honoured by this pattern:
--   • EXISTS guard on base tables → empty seed/test_template fixtures are
--     a no-op; no phantom worker.tasks row pollutes the seed dump.
--   • Spawn happens INSIDE the migration TX → atomic with the index
--     swap; after COMMIT the worker daemon picks up the task via
--     pg_notify and starts the rebuild without further intervention.
--   • NULL-valued id-range keys in the payload → worker synthesises full
--     id sets from base tables (the canonical full-rebuild contract).
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
