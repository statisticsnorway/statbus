```sql
CREATE OR REPLACE FUNCTION admin.create_statistical_unit_ui_indices()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Every index here serves a query on statistical_unit; its COMMENT names the query.
    -- The search page's filters and sorts are listed in app/src/app/search/filters/url-search-params.ts
    -- and app/src/atoms/search.ts; test/sql/359 checks that each one reads an index.

    -- Lookups by the derive pipeline, reports and unit pages.
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_unit_type ON public.statistical_unit (unit_type);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_establishment_id ON public.statistical_unit (unit_id);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_primary_activity_category_id ON public.statistical_unit (primary_activity_category_id);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_secondary_activity_category_id ON public.statistical_unit (secondary_activity_category_id);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_physical_region_id ON public.statistical_unit (physical_region_id);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_physical_country_id ON public.statistical_unit (physical_country_id);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_sector_id ON public.statistical_unit (sector_id);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_legal_form_id ON public.statistical_unit (legal_form_id);

    -- Search filters.
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_domestic ON public.statistical_unit (domestic);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_status_code ON public.statistical_unit (status_code);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_unit_size_code ON public.statistical_unit (unit_size_code);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_last_edit_by_user_id ON public.statistical_unit (last_edit_by_user_id);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_search ON public.statistical_unit USING GIN (search);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_data_source_ids ON public.statistical_unit USING GIN (data_source_ids);
    CREATE INDEX IF NOT EXISTS idx_gist_statistical_unit_external_idents ON public.statistical_unit USING GIN (external_idents jsonb_path_ops);

    -- Path filters (descendant of a chosen code: GiST).
    CREATE INDEX IF NOT EXISTS idx_gist_statistical_unit_physical_region_path ON public.statistical_unit USING GIST (physical_region_path);
    CREATE INDEX IF NOT EXISTS idx_gist_statistical_unit_sector_path ON public.statistical_unit USING GIST (sector_path);
    CREATE INDEX IF NOT EXISTS idx_gist_statistical_unit_primary_activity_category_path ON public.statistical_unit USING GIST (primary_activity_category_path);
    CREATE INDEX IF NOT EXISTS idx_gist_statistical_unit_tag_paths ON public.statistical_unit USING GIST (tag_paths);

    -- Search sorts: one index per direction, ending in the search's tie-break (unit_type, unit_id).
    -- The asc index also serves the column's equality filter (legal_form_code in (...)).
    CREATE INDEX IF NOT EXISTS su_sort_name_asc ON public.statistical_unit (name, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_name_desc ON public.statistical_unit (name DESC NULLS LAST, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_physical_region_path_asc ON public.statistical_unit (physical_region_path, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_physical_region_path_desc ON public.statistical_unit (physical_region_path DESC NULLS LAST, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_sector_path_asc ON public.statistical_unit (sector_path, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_sector_path_desc ON public.statistical_unit (sector_path DESC NULLS LAST, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_legal_form_code_asc ON public.statistical_unit (legal_form_code, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_legal_form_code_desc ON public.statistical_unit (legal_form_code DESC NULLS LAST, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_primary_activity_category_path_asc ON public.statistical_unit (primary_activity_category_path, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_primary_activity_category_path_desc ON public.statistical_unit (primary_activity_category_path DESC NULLS LAST, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_secondary_activity_category_path_asc ON public.statistical_unit (secondary_activity_category_path, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_secondary_activity_category_path_desc ON public.statistical_unit (secondary_activity_category_path DESC NULLS LAST, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_birth_date_asc ON public.statistical_unit (birth_date, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_birth_date_desc ON public.statistical_unit (birth_date DESC NULLS LAST, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_death_date_asc ON public.statistical_unit (death_date, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_death_date_desc ON public.statistical_unit (death_date DESC NULLS LAST, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_last_edit_at_asc ON public.statistical_unit (last_edit_at, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_last_edit_at_desc ON public.statistical_unit (last_edit_at DESC NULLS LAST, unit_type, unit_id);

    -- Per identifier type and per statistic (su_ei_*, su_ss_*): admin.generate_statistical_unit_jsonb_indices().
    CALL admin.generate_statistical_unit_jsonb_indices();

    PERFORM admin.comment_statistical_unit_indices();
    RAISE DEBUG 'Created all statistical_unit UI indices';
END;
$function$
```
