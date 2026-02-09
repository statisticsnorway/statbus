-- Down Migration 20260209080204: fix_derive_concurrent_race_conditions
BEGIN;

-- Restore original statistical_history_derive without ON CONFLICT DO NOTHING
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

    -- Bulk INSERT using LATERAL join - much faster than FOR LOOP
    INSERT INTO public.statistical_history
    SELECT h.*
    FROM public.get_statistical_history_periods(
        p_resolution := null::public.history_resolution,
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until
    ) tp
    CROSS JOIN LATERAL public.statistical_history_def(tp.resolution, tp.year, tp.month) h;
END;
$statistical_history_derive$;

-- Restore original statistical_unit_facet_derive without ON CONFLICT DO NOTHING
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

    INSERT INTO public.statistical_unit_facet
    SELECT * FROM public.statistical_unit_facet_def AS sufd
    WHERE from_until_overlaps(sufd.valid_from, sufd.valid_until,
                          p_valid_from,
                          p_valid_until);
END;
$statistical_unit_facet_derive$;

-- Drop the unique index added by the up migration
DROP INDEX IF EXISTS public.statistical_unit_facet_key;

END;
