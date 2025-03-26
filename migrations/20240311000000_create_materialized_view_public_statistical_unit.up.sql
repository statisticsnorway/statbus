BEGIN;

CREATE TABLE public.statistical_unit (LIKE public.statistical_unit_def INCLUDING ALL);

CREATE UNIQUE INDEX "statistical_unit_upsert_pkey"
    ON public.statistical_unit
    (unit_type, unit_id, valid_after);

CREATE UNIQUE INDEX "statistical_unit_from_key"
    ON public.statistical_unit
    (valid_from
    ,valid_to
    ,unit_type
    ,unit_id
    );

CREATE UNIQUE INDEX "statistical_unit_after_key"
    ON public.statistical_unit
    (valid_after
    ,valid_to
    ,unit_type
    ,unit_id
    );

-- Ensure that incorrect data can not be entered, as a safeguard agains errors in processing by worker.
ALTER TABLE public.statistical_unit ADD
    CONSTRAINT "statistical_unit_type_id_daterange_excl"
    EXCLUDE USING gist (
        unit_type WITH =,
        unit_id WITH =,
        daterange(valid_after, valid_to, '(]'::text) WITH &&
    ) DEFERRABLE;


CREATE INDEX idx_statistical_unit_unit_type ON public.statistical_unit (unit_type);
CREATE INDEX idx_statistical_unit_establishment_id ON public.statistical_unit (unit_id);
CREATE INDEX idx_statistical_unit_search ON public.statistical_unit USING GIN (search);
CREATE INDEX idx_statistical_unit_primary_activity_category_id ON public.statistical_unit (primary_activity_category_id);
CREATE INDEX idx_statistical_unit_secondary_activity_category_id ON public.statistical_unit (secondary_activity_category_id);
CREATE INDEX idx_statistical_unit_physical_region_id ON public.statistical_unit (physical_region_id);
CREATE INDEX idx_statistical_unit_physical_country_id ON public.statistical_unit (physical_country_id);
CREATE INDEX idx_statistical_unit_sector_id ON public.statistical_unit (sector_id);

CREATE INDEX idx_statistical_unit_data_source_ids ON public.statistical_unit USING GIN (data_source_ids);

CREATE INDEX idx_statistical_unit_sector_path ON public.statistical_unit(sector_path);
CREATE INDEX idx_gist_statistical_unit_sector_path ON public.statistical_unit USING GIST (sector_path);

CREATE INDEX idx_statistical_unit_legal_form_id ON public.statistical_unit (legal_form_id);
CREATE INDEX idx_statistical_unit_invalid_codes ON public.statistical_unit USING gin (invalid_codes);
CREATE INDEX idx_statistical_unit_invalid_codes_exists ON public.statistical_unit (invalid_codes) WHERE invalid_codes IS NOT NULL;

CREATE INDEX idx_statistical_unit_primary_activity_category_path ON public.statistical_unit(primary_activity_category_path);
CREATE INDEX idx_gist_statistical_unit_primary_activity_category_path ON public.statistical_unit USING GIST (primary_activity_category_path);

CREATE INDEX idx_statistical_unit_secondary_activity_category_path ON public.statistical_unit(secondary_activity_category_path);
CREATE INDEX idx_gist_statistical_unit_secondary_activity_category_path ON public.statistical_unit USING GIST (secondary_activity_category_path);

CREATE INDEX idx_statistical_unit_activity_category_paths ON public.statistical_unit(activity_category_paths);
CREATE INDEX idx_gist_statistical_unit_activity_category_paths ON public.statistical_unit USING GIST (activity_category_paths);

CREATE INDEX idx_statistical_unit_physical_region_path ON public.statistical_unit(physical_region_path);
CREATE INDEX idx_gist_statistical_unit_physical_region_path ON public.statistical_unit USING GIST (physical_region_path);

CREATE INDEX idx_statistical_unit_external_idents ON public.statistical_unit(external_idents);
CREATE INDEX idx_gist_statistical_unit_external_idents ON public.statistical_unit USING GIN (external_idents jsonb_path_ops);

CREATE INDEX idx_statistical_unit_tag_paths ON public.statistical_unit(tag_paths);
CREATE INDEX idx_gist_statistical_unit_tag_paths ON public.statistical_unit USING GIST (tag_paths);

END;
