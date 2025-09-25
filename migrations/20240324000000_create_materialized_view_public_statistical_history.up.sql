BEGIN;

SET client_min_messages TO debug1;

CREATE TABLE public.statistical_history OF public.statistical_history_type;

CREATE UNIQUE INDEX "statistical_history_month_key"
    ON public.statistical_history
    ( resolution
    , year
    , month
    , unit_type
    ) WHERE resolution = 'year-month'::public.history_resolution;
CREATE UNIQUE INDEX "statistical_history_year_key"
    ON public.statistical_history
    ( resolution
    , year
    , unit_type
    ) WHERE resolution = 'year'::public.history_resolution;

CREATE INDEX idx_history_resolution ON public.statistical_history (resolution);
CREATE INDEX idx_statistical_history_year ON public.statistical_history (year);
CREATE INDEX idx_statistical_history_month ON public.statistical_history (month);
CREATE INDEX idx_statistical_history_births ON public.statistical_history (births);
CREATE INDEX idx_statistical_history_deaths ON public.statistical_history (deaths);
CREATE INDEX idx_statistical_history_count ON public.statistical_history (count);
CREATE INDEX idx_statistical_history_stats_summary ON public.statistical_history USING GIN (stats_summary jsonb_path_ops);

-- This procedure orchestrates the batched refresh of the `statistical_history` table.
CREATE FUNCTION public.statistical_history_derive(
  p_valid_from date DEFAULT '-infinity'::date,
  p_valid_until date DEFAULT 'infinity'::date
)
RETURNS void
LANGUAGE plpgsql
AS $statistical_history_derive$
DECLARE
    v_period RECORD;
BEGIN
    RAISE DEBUG 'Running statistical_history_derive(p_valid_from=%, p_valid_until=%)', p_valid_from, p_valid_until;

    -- Get relevant periods and store them in a temporary table
    CREATE TEMPORARY TABLE temp_periods ON COMMIT DROP AS
    SELECT *
    FROM public.get_statistical_history_periods(
        p_resolution := null::public.history_resolution, -- Get both year and year-month
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until
    );

    -- Delete existing records for the affected periods
    DELETE FROM public.statistical_history sh
    USING temp_periods tp
    WHERE sh.year = tp.year
    AND sh.month IS NOT DISTINCT FROM tp.month;

    -- Loop through each period and insert the new data by calling the _def function.
    FOR v_period IN SELECT * FROM temp_periods
    LOOP
        INSERT INTO public.statistical_history
        SELECT * FROM public.statistical_history_def(v_period.resolution, v_period.year, v_period.month);
    END LOOP;

    -- Clean up
    DROP TABLE IF EXISTS temp_periods;
END;
$statistical_history_derive$;

END;
