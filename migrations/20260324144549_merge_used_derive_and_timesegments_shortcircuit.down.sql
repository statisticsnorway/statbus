-- Down Migration 20260324144549: merge_used_derive_and_timesegments_shortcircuit
--
-- Restore the original DELETE+INSERT pattern for all six _used_derive functions
-- and remove the short-circuit from timesegments_years_refresh_concurrent().
BEGIN;

-- ============================================================
-- 1. activity_category_used_derive() — restore DELETE+INSERT
-- ============================================================
CREATE OR REPLACE FUNCTION public.activity_category_used_derive()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    RAISE DEBUG 'Running activity_category_used_derive()';
    DELETE FROM public.activity_category_used;
    INSERT INTO public.activity_category_used
    SELECT * FROM public.activity_category_used_def;
END;
$function$;

-- ============================================================
-- 2. region_used_derive() — restore DELETE+INSERT
-- ============================================================
CREATE OR REPLACE FUNCTION public.region_used_derive()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    RAISE DEBUG 'Running region_used_derive()';
    DELETE FROM public.region_used;
    INSERT INTO public.region_used
    SELECT * FROM public.region_used_def;
END;
$function$;

-- ============================================================
-- 3. sector_used_derive() — restore DELETE+INSERT
-- ============================================================
CREATE OR REPLACE FUNCTION public.sector_used_derive()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    RAISE DEBUG 'Running sector_used_derive()';
    DELETE FROM public.sector_used;
    INSERT INTO public.sector_used
    SELECT * FROM public.sector_used_def;
END;
$function$;

-- ============================================================
-- 4. data_source_used_derive() — restore DELETE+INSERT
-- ============================================================
CREATE OR REPLACE FUNCTION public.data_source_used_derive()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    RAISE DEBUG 'Running data_source_used_derive()';
    DELETE FROM public.data_source_used;
    INSERT INTO public.data_source_used
    SELECT * FROM public.data_source_used_def;
END;
$function$;

-- ============================================================
-- 5. legal_form_used_derive() — restore DELETE+INSERT
-- ============================================================
CREATE OR REPLACE FUNCTION public.legal_form_used_derive()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE DEBUG 'Running legal_form_used_derive()';
    DELETE FROM public.legal_form_used;
    INSERT INTO public.legal_form_used
    SELECT * FROM public.legal_form_used_def;
END;
$function$;

-- ============================================================
-- 6. country_used_derive() — restore DELETE+INSERT
-- ============================================================
CREATE OR REPLACE FUNCTION public.country_used_derive()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE DEBUG 'Running country_used_derive()';
    DELETE FROM public.country_used;
    INSERT INTO public.country_used
    SELECT * FROM public.country_used_def;
END;
$function$;

-- ============================================================
-- 7. timesegments_years_refresh_concurrent() — restore original
-- ============================================================
CREATE OR REPLACE PROCEDURE public.timesegments_years_refresh_concurrent()
 LANGUAGE plpgsql
AS $procedure$
BEGIN
    -- Insert missing years (idempotent - safe for concurrent calls)
    INSERT INTO public.timesegments_years (year)
    SELECT DISTINCT year FROM public.timesegments_years_def
    ON CONFLICT (year) DO NOTHING;

    -- Delete obsolete years (safe - multiple deletes have same effect)
    DELETE FROM public.timesegments_years t
    WHERE NOT EXISTS (
        SELECT 1 FROM public.timesegments_years_def d WHERE d.year = t.year
    );
END;
$procedure$;

END;
