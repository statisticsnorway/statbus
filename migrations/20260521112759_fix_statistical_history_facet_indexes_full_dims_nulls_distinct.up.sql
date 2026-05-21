-- Migration: Fix statistical_history_facet indexes to match source GROUP BY
--
-- Issue #53/#61: The reduce function groups by 12 columns (including unit_size_id, status_id)
-- but the target indexes only constrained 10/9 columns, causing duplicate-key collisions.
--
-- Fix: Expand both partial unique indexes to include unit_size_id and status_id,
-- and change NULL semantics from NULLS DISTINCT (default) to NULLS NOT DISTINCT
-- to match the partitions table's UNIQUE constraint.

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

-- Backfill via re-derive to ensure data consistency
-- (resilient to empty UNLOGGED partitions)
SELECT public.statistical_history_facet_derive('-infinity'::date, 'infinity'::date);

-- Clean up any stale dirty hash slot markers from previous reduce cycles
TRUNCATE public.statistical_unit_facet_dirty_hash_slots;

COMMIT;
