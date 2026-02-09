-- Migration 20260209080204: fix_derive_concurrent_race_conditions
--
-- Fix race conditions in derive functions when concurrent workers
-- both DELETE+INSERT for the same time range simultaneously.
-- Worker A does DELETE+INSERT, worker B does DELETE(finds nothing)+INSERT → duplicate key.
-- Use ON CONFLICT DO UPDATE so the last writer wins with the freshest source data.
SELECT pg_catalog.set_config('search_path', 'public', false);
BEGIN;

-- Fix 1: statistical_history_derive — ON CONFLICT DO UPDATE
--
-- Two partial unique indexes exist:
--   statistical_history_year_key  (resolution, year, unit_type) WHERE resolution = 'year'
--   statistical_history_month_key (resolution, year, month, unit_type) WHERE resolution = 'year-month'
-- A single INSERT can only target one conflict target, so we split by resolution.
CREATE OR REPLACE FUNCTION public.statistical_history_derive(p_valid_from date DEFAULT '-infinity'::date, p_valid_until date DEFAULT 'infinity'::date)
 RETURNS void
 LANGUAGE plpgsql
AS $statistical_history_derive$
BEGIN
    RAISE DEBUG 'Running statistical_history_derive(p_valid_from=%, p_valid_until=%)', p_valid_from, p_valid_until;

    -- Delete existing records for the affected periods
    DELETE FROM public.statistical_history sh
    USING public.get_statistical_history_periods(
        p_resolution := null::public.history_resolution,
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until
    ) tp
    WHERE sh.year = tp.year
    AND sh.month IS NOT DISTINCT FROM tp.month;

    -- Insert year-resolution rows.
    -- ON CONFLICT DO UPDATE: if a concurrent worker already inserted,
    -- overwrite with the freshest computed data.
    INSERT INTO public.statistical_history
    SELECT h.*
    FROM public.get_statistical_history_periods(
        p_resolution := 'year'::public.history_resolution,
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until
    ) tp
    CROSS JOIN LATERAL public.statistical_history_def(tp.resolution, tp.year, tp.month) h
    ON CONFLICT (resolution, year, unit_type) WHERE resolution = 'year'::public.history_resolution
    DO UPDATE SET
        exists_count = EXCLUDED.exists_count,
        exists_change = EXCLUDED.exists_change,
        exists_added_count = EXCLUDED.exists_added_count,
        exists_removed_count = EXCLUDED.exists_removed_count,
        countable_count = EXCLUDED.countable_count,
        countable_change = EXCLUDED.countable_change,
        countable_added_count = EXCLUDED.countable_added_count,
        countable_removed_count = EXCLUDED.countable_removed_count,
        births = EXCLUDED.births,
        deaths = EXCLUDED.deaths,
        name_change_count = EXCLUDED.name_change_count,
        primary_activity_category_change_count = EXCLUDED.primary_activity_category_change_count,
        secondary_activity_category_change_count = EXCLUDED.secondary_activity_category_change_count,
        sector_change_count = EXCLUDED.sector_change_count,
        legal_form_change_count = EXCLUDED.legal_form_change_count,
        physical_region_change_count = EXCLUDED.physical_region_change_count,
        physical_country_change_count = EXCLUDED.physical_country_change_count,
        physical_address_change_count = EXCLUDED.physical_address_change_count,
        stats_summary = EXCLUDED.stats_summary;

    -- Insert year-month resolution rows.
    INSERT INTO public.statistical_history
    SELECT h.*
    FROM public.get_statistical_history_periods(
        p_resolution := 'year-month'::public.history_resolution,
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until
    ) tp
    CROSS JOIN LATERAL public.statistical_history_def(tp.resolution, tp.year, tp.month) h
    ON CONFLICT (resolution, year, month, unit_type) WHERE resolution = 'year-month'::public.history_resolution
    DO UPDATE SET
        exists_count = EXCLUDED.exists_count,
        exists_change = EXCLUDED.exists_change,
        exists_added_count = EXCLUDED.exists_added_count,
        exists_removed_count = EXCLUDED.exists_removed_count,
        countable_count = EXCLUDED.countable_count,
        countable_change = EXCLUDED.countable_change,
        countable_added_count = EXCLUDED.countable_added_count,
        countable_removed_count = EXCLUDED.countable_removed_count,
        births = EXCLUDED.births,
        deaths = EXCLUDED.deaths,
        name_change_count = EXCLUDED.name_change_count,
        primary_activity_category_change_count = EXCLUDED.primary_activity_category_change_count,
        secondary_activity_category_change_count = EXCLUDED.secondary_activity_category_change_count,
        sector_change_count = EXCLUDED.sector_change_count,
        legal_form_change_count = EXCLUDED.legal_form_change_count,
        physical_region_change_count = EXCLUDED.physical_region_change_count,
        physical_country_change_count = EXCLUDED.physical_country_change_count,
        physical_address_change_count = EXCLUDED.physical_address_change_count,
        stats_summary = EXCLUDED.stats_summary;
END;
$statistical_history_derive$;

-- Fix 2: statistical_unit_facet — add unique constraint + ON CONFLICT DO UPDATE
--
-- The table had no unique constraint, so concurrent DELETE+INSERT races
-- silently created duplicate rows (data corruption).

-- First, remove any existing duplicates before adding the constraint
DELETE FROM public.statistical_unit_facet AS a
USING public.statistical_unit_facet AS b
WHERE a.ctid < b.ctid
  AND COALESCE(a.valid_from, '-infinity'::date) = COALESCE(b.valid_from, '-infinity'::date)
  AND COALESCE(a.valid_to, 'infinity'::date) = COALESCE(b.valid_to, 'infinity'::date)
  AND COALESCE(a.valid_until, 'infinity'::date) = COALESCE(b.valid_until, 'infinity'::date)
  AND a.unit_type = b.unit_type
  AND COALESCE(a.physical_region_path, ''::ltree) = COALESCE(b.physical_region_path, ''::ltree)
  AND COALESCE(a.primary_activity_category_path, ''::ltree) = COALESCE(b.primary_activity_category_path, ''::ltree)
  AND COALESCE(a.sector_path, ''::ltree) = COALESCE(b.sector_path, ''::ltree)
  AND COALESCE(a.legal_form_id, -1) = COALESCE(b.legal_form_id, -1)
  AND COALESCE(a.physical_country_id, -1) = COALESCE(b.physical_country_id, -1)
  AND COALESCE(a.status_id, -1) = COALESCE(b.status_id, -1);

-- Add unique index on the GROUP BY columns (matches statistical_unit_facet_def view)
CREATE UNIQUE INDEX statistical_unit_facet_key
ON public.statistical_unit_facet (
    valid_from, valid_to, valid_until, unit_type,
    physical_region_path, primary_activity_category_path,
    sector_path, legal_form_id, physical_country_id, status_id
) NULLS NOT DISTINCT;

CREATE OR REPLACE FUNCTION public.statistical_unit_facet_derive(p_valid_from date DEFAULT '-infinity'::date, p_valid_until date DEFAULT 'infinity'::date)
 RETURNS void
 LANGUAGE plpgsql
AS $statistical_unit_facet_derive$
BEGIN
    RAISE DEBUG 'Running statistical_unit_facet_derive(p_valid_from=%, p_valid_until=%)', p_valid_from, p_valid_until;
    DELETE FROM public.statistical_unit_facet AS suf
    WHERE from_until_overlaps(suf.valid_from, suf.valid_until,
                          p_valid_from,
                          p_valid_until);

    -- ON CONFLICT DO UPDATE: if a concurrent worker already inserted,
    -- overwrite with the freshest computed data (count + stats_summary).
    INSERT INTO public.statistical_unit_facet
    SELECT * FROM public.statistical_unit_facet_def AS sufd
    WHERE from_until_overlaps(sufd.valid_from, sufd.valid_until,
                          p_valid_from,
                          p_valid_until)
    ON CONFLICT (valid_from, valid_to, valid_until, unit_type,
                 physical_region_path, primary_activity_category_path,
                 sector_path, legal_form_id, physical_country_id, status_id)
    DO UPDATE SET
        count = EXCLUDED.count,
        stats_summary = EXCLUDED.stats_summary;
END;
$statistical_unit_facet_derive$;

END;
