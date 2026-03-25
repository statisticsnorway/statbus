```sql
CREATE OR REPLACE PROCEDURE public.timesegments_years_refresh_concurrent()
 LANGUAGE plpgsql
AS $procedure$
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
$procedure$
```
