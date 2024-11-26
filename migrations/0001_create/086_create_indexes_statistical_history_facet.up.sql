BEGIN;

\echo statistical_history_facet_month_key
CREATE UNIQUE INDEX "statistical_history_facet_month_key"
    ON public.statistical_history_facet
    ( resolution
    , year
    , month
    , unit_type
    , primary_activity_category_path
    , secondary_activity_category_path
    , sector_path
    , legal_form_id
    , physical_region_path
    , physical_country_id
    ) WHERE resolution = 'year-month'::public.history_resolution;
\echo statistical_history_facet_year_key
CREATE UNIQUE INDEX "statistical_history_facet_year_key"
    ON public.statistical_history_facet
    ( year
    , month
    , unit_type
    , primary_activity_category_path
    , secondary_activity_category_path
    , sector_path
    , legal_form_id
    , physical_region_path
    , physical_country_id
    ) WHERE resolution = 'year'::public.history_resolution;

\echo idx_statistical_history_facet_year
CREATE INDEX idx_statistical_history_facet_year ON public.statistical_history_facet (year);
\echo idx_statistical_history_facet_month
CREATE INDEX idx_statistical_history_facet_month ON public.statistical_history_facet (month);
\echo idx_statistical_history_facet_births
CREATE INDEX idx_statistical_history_facet_births ON public.statistical_history_facet (births);
\echo idx_statistical_history_facet_deaths
CREATE INDEX idx_statistical_history_facet_deaths ON public.statistical_history_facet (deaths);

\echo idx_statistical_history_facet_primary_activity_category_path
CREATE INDEX idx_statistical_history_facet_primary_activity_category_path ON public.statistical_history_facet (primary_activity_category_path);
\echo idx_gist_statistical_history_facet_primary_activity_category_path
CREATE INDEX idx_gist_statistical_history_facet_primary_activity_category_path ON public.statistical_history_facet USING GIST (primary_activity_category_path);

\echo idx_statistical_history_facet_secondary_activity_category_path
CREATE INDEX idx_statistical_history_facet_secondary_activity_category_path ON public.statistical_history_facet (secondary_activity_category_path);
\echo idx_gist_statistical_history_facet_secondary_activity_category_path
CREATE INDEX idx_gist_statistical_history_facet_secondary_activity_category_path ON public.statistical_history_facet USING GIST (secondary_activity_category_path);

\echo idx_statistical_history_facet_sector_path
CREATE INDEX idx_statistical_history_facet_sector_path ON public.statistical_history_facet (sector_path);
\echo idx_gist_statistical_history_facet_sector_path
CREATE INDEX idx_gist_statistical_history_facet_sector_path ON public.statistical_history_facet USING GIST (sector_path);

\echo idx_statistical_history_facet_legal_form_id
CREATE INDEX idx_statistical_history_facet_legal_form_id ON public.statistical_history_facet (legal_form_id);

\echo idx_statistical_history_facet_physical_region_path
CREATE INDEX idx_statistical_history_facet_physical_region_path ON public.statistical_history_facet (physical_region_path);
\echo idx_gist_statistical_history_facet_physical_region_path
CREATE INDEX idx_gist_statistical_history_facet_physical_region_path ON public.statistical_history_facet USING GIST (physical_region_path);

\echo idx_statistical_history_facet_physical_country_id
CREATE INDEX idx_statistical_history_facet_physical_country_id ON public.statistical_history_facet (physical_country_id);
\echo idx_statistical_history_facet_count
CREATE INDEX idx_statistical_history_facet_count ON public.statistical_history_facet (count);
\echo idx_statistical_history_facet_stats_summary
CREATE INDEX idx_statistical_history_facet_stats_summary ON public.statistical_history_facet USING GIN (stats_summary jsonb_path_ops);

END;