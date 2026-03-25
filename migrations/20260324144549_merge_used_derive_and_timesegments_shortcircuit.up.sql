-- Migration 20260324144549: merge_used_derive_and_timesegments_shortcircuit
--
-- 1. Replace DELETE+INSERT with MERGE for six _used_derive functions
--    to avoid unnecessary churn when data hasn't changed.
-- 2. Add short-circuit to timesegments_years_refresh_concurrent()
--    to skip the expensive generate_series scan when years are stable.
BEGIN;

-- ============================================================
-- 1. activity_category_used_derive() — unique key: path (ltree)
-- ============================================================
CREATE OR REPLACE FUNCTION public.activity_category_used_derive()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $activity_category_used_derive$
BEGIN
    RAISE DEBUG 'Running activity_category_used_derive()';
    MERGE INTO public.activity_category_used AS target
    USING public.activity_category_used_def AS source
    ON target.path = source.path
    WHEN MATCHED AND (
        target.standard_code IS DISTINCT FROM source.standard_code
        OR target.id IS DISTINCT FROM source.id
        OR target.parent_path IS DISTINCT FROM source.parent_path
        OR target.code IS DISTINCT FROM source.code
        OR target.label IS DISTINCT FROM source.label
        OR target.name IS DISTINCT FROM source.name
        OR target.description IS DISTINCT FROM source.description
    ) THEN UPDATE SET
        standard_code = source.standard_code,
        id = source.id,
        parent_path = source.parent_path,
        code = source.code,
        label = source.label,
        name = source.name,
        description = source.description
    WHEN NOT MATCHED BY TARGET THEN INSERT
        (standard_code, id, path, parent_path, code, label, name, description)
        VALUES (source.standard_code, source.id, source.path, source.parent_path,
                source.code, source.label, source.name, source.description)
    WHEN NOT MATCHED BY SOURCE THEN DELETE;
END;
$activity_category_used_derive$;

-- ============================================================
-- 2. region_used_derive() — unique key: path (ltree)
-- ============================================================
CREATE OR REPLACE FUNCTION public.region_used_derive()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $region_used_derive$
BEGIN
    RAISE DEBUG 'Running region_used_derive()';
    MERGE INTO public.region_used AS target
    USING public.region_used_def AS source
    ON target.path = source.path
    WHEN MATCHED AND (
        target.id IS DISTINCT FROM source.id
        OR target.level IS DISTINCT FROM source.level
        OR target.label IS DISTINCT FROM source.label
        OR target.code IS DISTINCT FROM source.code
        OR target.name IS DISTINCT FROM source.name
    ) THEN UPDATE SET
        id = source.id,
        level = source.level,
        label = source.label,
        code = source.code,
        name = source.name
    WHEN NOT MATCHED BY TARGET THEN INSERT
        (id, path, level, label, code, name)
        VALUES (source.id, source.path, source.level, source.label,
                source.code, source.name)
    WHEN NOT MATCHED BY SOURCE THEN DELETE;
END;
$region_used_derive$;

-- ============================================================
-- 3. sector_used_derive() — unique key: path (ltree)
-- ============================================================
CREATE OR REPLACE FUNCTION public.sector_used_derive()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $sector_used_derive$
BEGIN
    RAISE DEBUG 'Running sector_used_derive()';
    MERGE INTO public.sector_used AS target
    USING public.sector_used_def AS source
    ON target.path = source.path
    WHEN MATCHED AND (
        target.id IS DISTINCT FROM source.id
        OR target.label IS DISTINCT FROM source.label
        OR target.code IS DISTINCT FROM source.code
        OR target.name IS DISTINCT FROM source.name
    ) THEN UPDATE SET
        id = source.id,
        label = source.label,
        code = source.code,
        name = source.name
    WHEN NOT MATCHED BY TARGET THEN INSERT
        (id, path, label, code, name)
        VALUES (source.id, source.path, source.label, source.code, source.name)
    WHEN NOT MATCHED BY SOURCE THEN DELETE;
END;
$sector_used_derive$;

-- ============================================================
-- 4. data_source_used_derive() — unique key: code (text)
-- ============================================================
CREATE OR REPLACE FUNCTION public.data_source_used_derive()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $data_source_used_derive$
BEGIN
    RAISE DEBUG 'Running data_source_used_derive()';
    MERGE INTO public.data_source_used AS target
    USING public.data_source_used_def AS source
    ON target.code = source.code
    WHEN MATCHED AND (
        target.id IS DISTINCT FROM source.id
        OR target.name IS DISTINCT FROM source.name
    ) THEN UPDATE SET
        id = source.id,
        name = source.name
    WHEN NOT MATCHED BY TARGET THEN INSERT
        (id, code, name)
        VALUES (source.id, source.code, source.name)
    WHEN NOT MATCHED BY SOURCE THEN DELETE;
END;
$data_source_used_derive$;

-- ============================================================
-- 5. legal_form_used_derive() — unique key: code (text)
-- ============================================================
CREATE OR REPLACE FUNCTION public.legal_form_used_derive()
 RETURNS void
 LANGUAGE plpgsql
AS $legal_form_used_derive$
BEGIN
    RAISE DEBUG 'Running legal_form_used_derive()';
    MERGE INTO public.legal_form_used AS target
    USING public.legal_form_used_def AS source
    ON target.code = source.code
    WHEN MATCHED AND (
        target.id IS DISTINCT FROM source.id
        OR target.name IS DISTINCT FROM source.name
    ) THEN UPDATE SET
        id = source.id,
        name = source.name
    WHEN NOT MATCHED BY TARGET THEN INSERT
        (id, code, name)
        VALUES (source.id, source.code, source.name)
    WHEN NOT MATCHED BY SOURCE THEN DELETE;
END;
$legal_form_used_derive$;

-- ============================================================
-- 6. country_used_derive() — unique key: iso_2 (text)
-- ============================================================
CREATE OR REPLACE FUNCTION public.country_used_derive()
 RETURNS void
 LANGUAGE plpgsql
AS $country_used_derive$
BEGIN
    RAISE DEBUG 'Running country_used_derive()';
    MERGE INTO public.country_used AS target
    USING public.country_used_def AS source
    ON target.iso_2 = source.iso_2
    WHEN MATCHED AND (
        target.id IS DISTINCT FROM source.id
        OR target.name IS DISTINCT FROM source.name
    ) THEN UPDATE SET
        id = source.id,
        name = source.name
    WHEN NOT MATCHED BY TARGET THEN INSERT
        (id, iso_2, name)
        VALUES (source.id, source.iso_2, source.name)
    WHEN NOT MATCHED BY SOURCE THEN DELETE;
END;
$country_used_derive$;

-- ============================================================
-- 7. timesegments_years_refresh_concurrent() — short-circuit
-- ============================================================
-- The expensive part is timesegments_years_def which runs
-- generate_series over every timesegment row (3.1M+).
-- Short-circuit: compute the expected year range from MIN/MAX
-- of valid_from/valid_until (fast index scan on the primary key)
-- and check if timesegments_years already covers it exactly.
CREATE OR REPLACE PROCEDURE public.timesegments_years_refresh_concurrent()
 LANGUAGE plpgsql
AS $timesegments_years_refresh_concurrent$
DECLARE
    v_min_year int;
    v_max_year int;
    v_has_all boolean;
BEGIN
    -- Fast MIN/MAX from timesegments (uses index scan on primary key)
    SELECT MIN(EXTRACT(year FROM t.valid_from))::int,
           MAX(EXTRACT(year FROM LEAST(t.valid_until - interval '1 day', now()::date)))::int
    INTO v_min_year, v_max_year
    FROM public.timesegments AS t
    WHERE t.valid_from IS NOT NULL
      AND t.valid_until IS NOT NULL;

    -- If no timesegments exist, ensure the current year is present
    IF v_min_year IS NULL THEN
        v_min_year := EXTRACT(year FROM now())::int;
        v_max_year := v_min_year;
    END IF;

    -- Check if timesegments_years already has exactly the right years.
    -- generate_series(min, max) produces a tiny set (typically 1-10 years),
    -- and timesegments_years is equally small, so the EXCEPT is instant.
    SELECT NOT EXISTS (
        -- Years that should exist but don't
        SELECT gs.year
        FROM generate_series(v_min_year, v_max_year) AS gs(year)
        EXCEPT
        SELECT ty.year FROM public.timesegments_years AS ty
    ) AND NOT EXISTS (
        -- Years that exist but shouldn't
        SELECT ty.year FROM public.timesegments_years AS ty
        WHERE ty.year < v_min_year OR ty.year > v_max_year
    ) INTO v_has_all;

    IF v_has_all THEN
        RETURN;  -- All years match, skip expensive generate_series scan
    END IF;

    -- Fall through to full refresh using the expensive view
    -- Insert missing years (idempotent - safe for concurrent calls)
    INSERT INTO public.timesegments_years (year)
    SELECT DISTINCT year FROM public.timesegments_years_def
    ON CONFLICT (year) DO NOTHING;

    -- Delete obsolete years (safe - multiple deletes have same effect)
    DELETE FROM public.timesegments_years AS t
    WHERE NOT EXISTS (
        SELECT 1 FROM public.timesegments_years_def AS d WHERE d.year = t.year
    );
END;
$timesegments_years_refresh_concurrent$;

END;
