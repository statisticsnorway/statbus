\echo public.statistical_history
CREATE MATERIALIZED VIEW public.statistical_history AS
SELECT * FROM public.statistical_history_def
ORDER BY year, month;

\echo statistical_history_month_key
CREATE UNIQUE INDEX "statistical_history_month_key"
    ON public.statistical_history
    ( resolution
    , year
    , month
    , unit_type
    ) WHERE resolution = 'year-month'::public.history_resolution;
\echo statistical_history_year_key
CREATE UNIQUE INDEX "statistical_history_year_key"
    ON public.statistical_history
    ( resolution
    , year
    , unit_type
    ) WHERE resolution = 'year'::public.history_resolution;

\echo idx_history_resolution
CREATE INDEX idx_history_resolution ON public.statistical_history (resolution);
\echo idx_statistical_history_year
CREATE INDEX idx_statistical_history_year ON public.statistical_history (year);
\echo idx_statistical_history_month
CREATE INDEX idx_statistical_history_month ON public.statistical_history (month);
\echo idx_statistical_history_births
CREATE INDEX idx_statistical_history_births ON public.statistical_history (births);
\echo idx_statistical_history_deaths
CREATE INDEX idx_statistical_history_deaths ON public.statistical_history (deaths);
\echo idx_statistical_history_count
CREATE INDEX idx_statistical_history_count ON public.statistical_history (count);
\echo idx_statistical_history_stats
CREATE INDEX idx_statistical_history_stats_summary ON public.statistical_history USING GIN (stats_summary jsonb_path_ops);