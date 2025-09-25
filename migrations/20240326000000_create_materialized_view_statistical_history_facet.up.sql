BEGIN;

CREATE TABLE public.statistical_history_facet OF public.statistical_history_facet_type;

-- This procedure orchestrates the batched refresh of the `statistical_history_facet` table.
CREATE FUNCTION public.statistical_history_facet_derive(
  p_valid_from date DEFAULT '-infinity'::date,
  p_valid_until date DEFAULT 'infinity'::date
)
RETURNS void
LANGUAGE plpgsql
AS $statistical_history_facet_derive$
DECLARE
    v_period RECORD;
BEGIN
    RAISE DEBUG 'Running statistical_history_facet_derive(p_valid_from=%, p_valid_until=%)', p_valid_from, p_valid_until;

    -- Get relevant periods and store them in a temporary table
    CREATE TEMPORARY TABLE temp_periods ON COMMIT DROP AS
    SELECT *
    FROM public.get_statistical_history_periods(
        p_resolution := null::public.history_resolution,
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until
    );

    -- Delete existing records for the affected periods
    DELETE FROM public.statistical_history_facet shf
    USING temp_periods tp
    WHERE shf.year = tp.year
      AND shf.month IS NOT DISTINCT FROM tp.month
      AND shf.resolution = tp.resolution;

    -- Loop through each period and insert the new data by calling the _def function.
    FOR v_period IN SELECT * FROM temp_periods LOOP
        IF COALESCE(current_setting('statbus.statistical_history_facet_derive.log', true), 'f')::boolean THEN
            RAISE NOTICE 'Processing facets for period: resolution=%, year=%, month=%', v_period.resolution, v_period.year, v_period.month;
        END IF;

        INSERT INTO public.statistical_history_facet
        SELECT * FROM public.statistical_history_facet_def(v_period.resolution, v_period.year, v_period.month);
    END LOOP;

    -- Clean up
    IF to_regclass('pg_temp.temp_periods') IS NOT NULL THEN DROP TABLE temp_periods; END IF;
END;
$statistical_history_facet_derive$;

END;
