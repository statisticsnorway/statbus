```sql
CREATE OR REPLACE FUNCTION admin.create_statistical_unit_ui_indices()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Standard btree indices
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_unit_type ON public.statistical_unit (unit_type);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_establishment_id ON public.statistical_unit (unit_id);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_primary_activity_category_id ON public.statistical_unit (primary_activity_category_id);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_secondary_activity_category_id ON public.statistical_unit (secondary_activity_category_id);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_physical_region_id ON public.statistical_unit (physical_region_id);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_physical_country_id ON public.statistical_unit (physical_country_id);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_sector_id ON public.statistical_unit (sector_id);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_domestic ON public.statistical_unit (domestic);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_legal_form_id ON public.statistical_unit (legal_form_id);

    -- Path indices (btree + gist for ltree)
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_sector_path ON public.statistical_unit(sector_path);
    CREATE INDEX IF NOT EXISTS idx_gist_statistical_unit_sector_path ON public.statistical_unit USING GIST (sector_path);

    CREATE INDEX IF NOT EXISTS idx_statistical_unit_primary_activity_category_path ON public.statistical_unit(primary_activity_category_path);
    CREATE INDEX IF NOT EXISTS idx_gist_statistical_unit_primary_activity_category_path ON public.statistical_unit USING GIST (primary_activity_category_path);

    CREATE INDEX IF NOT EXISTS idx_statistical_unit_secondary_activity_category_path ON public.statistical_unit(secondary_activity_category_path);
    CREATE INDEX IF NOT EXISTS idx_gist_statistical_unit_secondary_activity_category_path ON public.statistical_unit USING GIST (secondary_activity_category_path);

    CREATE INDEX IF NOT EXISTS idx_statistical_unit_activity_category_paths ON public.statistical_unit(activity_category_paths);
    CREATE INDEX IF NOT EXISTS idx_gist_statistical_unit_activity_category_paths ON public.statistical_unit USING GIST (activity_category_paths);

    CREATE INDEX IF NOT EXISTS idx_statistical_unit_physical_region_path ON public.statistical_unit(physical_region_path);
    CREATE INDEX IF NOT EXISTS idx_gist_statistical_unit_physical_region_path ON public.statistical_unit USING GIST (physical_region_path);

    CREATE INDEX IF NOT EXISTS idx_statistical_unit_tag_paths ON public.statistical_unit(tag_paths);
    CREATE INDEX IF NOT EXISTS idx_gist_statistical_unit_tag_paths ON public.statistical_unit USING GIST (tag_paths);

    -- External idents indices
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_external_idents ON public.statistical_unit(external_idents);
    CREATE INDEX IF NOT EXISTS idx_gist_statistical_unit_external_idents ON public.statistical_unit USING GIN (external_idents jsonb_path_ops);

    -- GIN indices for arrays and jsonb
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_search ON public.statistical_unit USING GIN (search);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_data_source_ids ON public.statistical_unit USING GIN (data_source_ids);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_invalid_codes ON public.statistical_unit USING gin (invalid_codes);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_invalid_codes_exists ON public.statistical_unit (invalid_codes) WHERE invalid_codes IS NOT NULL;

    CREATE INDEX IF NOT EXISTS idx_statistical_unit_related_establishment_ids ON public.statistical_unit USING gin (related_establishment_ids);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_related_legal_unit_ids ON public.statistical_unit USING gin (related_legal_unit_ids);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_related_enterprise_ids ON public.statistical_unit USING gin (related_enterprise_ids);

    -- Dynamic jsonb indices (su_ei_*, su_s_*, su_ss_*)
    -- These are created by admin.generate_statistical_unit_jsonb_indices()
    CALL admin.generate_statistical_unit_jsonb_indices();

    RAISE DEBUG 'Created all statistical_unit UI indices';
END;
$function$
```
