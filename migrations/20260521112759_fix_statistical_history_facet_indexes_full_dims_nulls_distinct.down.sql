-- Rollback: Restore statistical_history_facet indexes to pre-fix state
--
-- Restores the original 10-col (month_key) and 9-col (year_key) partial unique indexes
-- with NULL semantics reverted to NULLS DISTINCT (PostgreSQL default).

BEGIN;

-- Drop the new 12-col and 11-col indexes
DROP INDEX IF EXISTS public.statistical_history_facet_month_key;
DROP INDEX IF EXISTS public.statistical_history_facet_year_key;

-- Honest rollback: post-fix data legitimately holds rows that share the
-- pre-fix 10-col / 9-col dim tuple but differ on unit_size_id / status_id
-- (that's the whole point of the fix). Recreating the narrower partial
-- unique indexes against that data would FAIL with dup-key. Clear the
-- target before recreating the old constraint shape; the next reduce
-- cycle (via worker.statistical_history_facet_reduce) will repopulate
-- under the now-restored bug semantics.
TRUNCATE public.statistical_history_facet;

-- Restore original 10-col partial unique index for year-month resolution
CREATE UNIQUE INDEX statistical_history_facet_month_key
ON public.statistical_history_facet (
    resolution, year, month, unit_type,
    primary_activity_category_path, secondary_activity_category_path,
    sector_path, legal_form_id, physical_region_path,
    physical_country_id
)
WHERE resolution = 'year-month'::history_resolution;

-- Restore original 9-col partial unique index for year resolution
CREATE UNIQUE INDEX statistical_history_facet_year_key
ON public.statistical_history_facet (
    year, month, unit_type,
    primary_activity_category_path, secondary_activity_category_path,
    sector_path, legal_form_id, physical_region_path,
    physical_country_id
)
WHERE resolution = 'year'::history_resolution;

COMMIT;
