BEGIN;

-- Fix: exclude hash_slot from derive function outputs.
-- Both functions used SELECT * / SELECT f.* from carrier/staging tables which
-- include hash_slot as an internal partitioning column.  The target consumer
-- tables (statistical_unit_facet, statistical_history_facet) either do not
-- have the column at all (statistical_history_facet — causes INSERT column
-- mismatch) or should not receive it (statistical_unit_facet).

-- ============================================================================
-- 1. public.statistical_history_facet_derive
--    Was: INSERT … SELECT f.*  (statistical_history_facet_partitions has hash_slot,
--         statistical_history_facet does NOT → "INSERT has more expressions than
--         target columns" error on any call)
--    Fix: explicit column list matching statistical_history_facet exactly.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.statistical_history_facet_derive(
    p_valid_from  date DEFAULT '-infinity'::date,
    p_valid_until date DEFAULT 'infinity'::date
)
RETURNS void
LANGUAGE plpgsql
AS $statistical_history_facet_derive$
BEGIN
    RAISE DEBUG 'Running statistical_history_facet_derive(p_valid_from=%, p_valid_until=%)', p_valid_from, p_valid_until;

    -- Delete existing records for the affected periods
    DELETE FROM public.statistical_history_facet shf
    USING public.get_statistical_history_periods(
        p_resolution := null::public.history_resolution,
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until
    ) tp
    WHERE shf.year = tp.year
      AND shf.month IS NOT DISTINCT FROM tp.month
      AND shf.resolution = tp.resolution;

    -- Bulk INSERT using LATERAL join — explicit column list excludes hash_slot.
    INSERT INTO public.statistical_history_facet (
        resolution, year, month, unit_type,
        primary_activity_category_path, secondary_activity_category_path,
        sector_path, legal_form_id, physical_region_path,
        physical_country_id, unit_size_id, status_id,
        exists_count, exists_change, exists_added_count, exists_removed_count,
        countable_count, countable_change, countable_added_count, countable_removed_count,
        births, deaths,
        name_change_count, primary_activity_category_change_count,
        secondary_activity_category_change_count, sector_change_count,
        legal_form_change_count, physical_region_change_count, physical_country_change_count,
        physical_address_change_count, unit_size_change_count, status_change_count,
        stats_summary
    )
    SELECT
        f.resolution, f.year, f.month, f.unit_type,
        f.primary_activity_category_path, f.secondary_activity_category_path,
        f.sector_path, f.legal_form_id, f.physical_region_path,
        f.physical_country_id, f.unit_size_id, f.status_id,
        f.exists_count, f.exists_change, f.exists_added_count, f.exists_removed_count,
        f.countable_count, f.countable_change, f.countable_added_count, f.countable_removed_count,
        f.births, f.deaths,
        f.name_change_count, f.primary_activity_category_change_count,
        f.secondary_activity_category_change_count, f.sector_change_count,
        f.legal_form_change_count, f.physical_region_change_count, f.physical_country_change_count,
        f.physical_address_change_count, f.unit_size_change_count, f.status_change_count,
        f.stats_summary
    FROM public.get_statistical_history_periods(
        p_resolution := null::public.history_resolution,
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until
    ) tp
    CROSS JOIN LATERAL public.statistical_history_facet_def(tp.resolution, tp.year, tp.month) f;
END;
$statistical_history_facet_derive$;

-- ============================================================================
-- 2. public.statistical_unit_facet_derive
--    Was: INSERT INTO statistical_unit_facet SELECT * FROM statistical_unit_facet_def
--         No explicit INSERT column list → position-maps 12 SELECT cols to 13
--         table cols (hash_slot is col 1 in the table), corrupting data.
--    Fix: add explicit INSERT column list matching statistical_unit_facet_def
--         output (valid_from … stats_summary, 12 cols, no hash_slot).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.statistical_unit_facet_derive(
    p_valid_from  date DEFAULT '-infinity'::date,
    p_valid_until date DEFAULT 'infinity'::date
)
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
    -- Explicit INSERT column list excludes hash_slot from the target.
    INSERT INTO public.statistical_unit_facet (
        valid_from, valid_to, valid_until, unit_type,
        physical_region_path, primary_activity_category_path,
        sector_path, legal_form_id, physical_country_id, status_id,
        count, stats_summary
    )
    SELECT
        sufd.valid_from, sufd.valid_to, sufd.valid_until, sufd.unit_type,
        sufd.physical_region_path, sufd.primary_activity_category_path,
        sufd.sector_path, sufd.legal_form_id, sufd.physical_country_id, sufd.status_id,
        sufd.count, sufd.stats_summary
    FROM public.statistical_unit_facet_def AS sufd
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
