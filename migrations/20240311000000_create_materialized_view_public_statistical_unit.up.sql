BEGIN;

\echo public.statistical_unit
CREATE MATERIALIZED VIEW public.statistical_unit AS
SELECT * FROM public.statistical_unit_def;

\echo statistical_unit_key
CREATE UNIQUE INDEX "statistical_unit_key"
    ON public.statistical_unit
    (valid_from
    ,valid_to
    ,unit_type
    ,unit_id
    );
\echo idx_statistical_unit_unit_type
CREATE INDEX idx_statistical_unit_unit_type ON public.statistical_unit (unit_type);
\echo idx_statistical_unit_establishment_id
CREATE INDEX idx_statistical_unit_establishment_id ON public.statistical_unit (unit_id);
\echo idx_statistical_unit_search
CREATE INDEX idx_statistical_unit_search ON public.statistical_unit USING GIN (search);
\echo idx_statistical_unit_primary_activity_category_id
CREATE INDEX idx_statistical_unit_primary_activity_category_id ON public.statistical_unit (primary_activity_category_id);
\echo idx_statistical_unit_secondary_activity_category_id
CREATE INDEX idx_statistical_unit_secondary_activity_category_id ON public.statistical_unit (secondary_activity_category_id);
\echo idx_statistical_unit_physical_region_id
CREATE INDEX idx_statistical_unit_physical_region_id ON public.statistical_unit (physical_region_id);
\echo idx_statistical_unit_physical_country_id
CREATE INDEX idx_statistical_unit_physical_country_id ON public.statistical_unit (physical_country_id);
\echo idx_statistical_unit_sector_id
CREATE INDEX idx_statistical_unit_sector_id ON public.statistical_unit (sector_id);

\echo idx_statistical_unit_data_source_ids
CREATE INDEX idx_statistical_unit_data_source_ids ON public.statistical_unit USING GIN (data_source_ids);

CREATE INDEX idx_statistical_unit_sector_path ON public.statistical_unit(sector_path);
CREATE INDEX idx_gist_statistical_unit_sector_path ON public.statistical_unit USING GIST (sector_path);

\echo idx_statistical_unit_legal_form_id
CREATE INDEX idx_statistical_unit_legal_form_id ON public.statistical_unit (legal_form_id);
\echo idx_statistical_unit_invalid_codes
CREATE INDEX idx_statistical_unit_invalid_codes ON public.statistical_unit USING gin (invalid_codes);
\echo idx_statistical_unit_invalid_codes_exists
CREATE INDEX idx_statistical_unit_invalid_codes_exists ON public.statistical_unit (invalid_codes) WHERE invalid_codes IS NOT NULL;

\echo idx_statistical_unit_primary_activity_category_path
CREATE INDEX idx_statistical_unit_primary_activity_category_path ON public.statistical_unit(primary_activity_category_path);
\echo idx_gist_statistical_unit_primary_activity_category_path
CREATE INDEX idx_gist_statistical_unit_primary_activity_category_path ON public.statistical_unit USING GIST (primary_activity_category_path);

\echo idx_statistical_unit_secondary_activity_category_path
CREATE INDEX idx_statistical_unit_secondary_activity_category_path ON public.statistical_unit(secondary_activity_category_path);
\echo idx_gist_statistical_unit_secondary_activity_category_path
CREATE INDEX idx_gist_statistical_unit_secondary_activity_category_path ON public.statistical_unit USING GIST (secondary_activity_category_path);

\echo idx_statistical_unit_activity_category_paths
CREATE INDEX idx_statistical_unit_activity_category_paths ON public.statistical_unit(activity_category_paths);
\echo idx_gist_statistical_unit_activity_category_paths
CREATE INDEX idx_gist_statistical_unit_activity_category_paths ON public.statistical_unit USING GIST (activity_category_paths);

\echo idx_statistical_unit_physical_region_path
CREATE INDEX idx_statistical_unit_physical_region_path ON public.statistical_unit(physical_region_path);
\echo idx_gist_statistical_unit_physical_region_path
CREATE INDEX idx_gist_statistical_unit_physical_region_path ON public.statistical_unit USING GIST (physical_region_path);

\echo idx_statistical_unit_external_idents
CREATE INDEX idx_statistical_unit_external_idents ON public.statistical_unit(external_idents);
\echo idx_gist_statistical_unit_external_idents
CREATE INDEX idx_gist_statistical_unit_external_idents ON public.statistical_unit USING GIN (external_idents jsonb_path_ops);

\echo idx_statistical_unit_tag_paths
CREATE INDEX idx_statistical_unit_tag_paths ON public.statistical_unit(tag_paths);
\echo idx_gist_statistical_unit_tag_paths
CREATE INDEX idx_gist_statistical_unit_tag_paths ON public.statistical_unit USING GIST (tag_paths);

END;