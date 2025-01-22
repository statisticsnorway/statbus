BEGIN;

CREATE MATERIALIZED VIEW public.statistical_history AS
SELECT * FROM public.statistical_history_def
ORDER BY year, month;

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

END;