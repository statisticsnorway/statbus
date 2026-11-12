-- Down 20261112154059: statistical_unit indexes as before STATBUS-627.
BEGIN;

DROP FUNCTION admin.comment_statistical_unit_indices();

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
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_name ON public.statistical_unit (name);

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

    CREATE INDEX IF NOT EXISTS idx_statistical_unit_related_establishment_ids ON public.statistical_unit USING gin (related_establishment_ids);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_related_legal_unit_ids ON public.statistical_unit USING gin (related_legal_unit_ids);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_related_enterprise_ids ON public.statistical_unit USING gin (related_enterprise_ids);

    -- Dynamic jsonb indices (su_ei_*, su_s_*, su_ss_*)
    -- These are created by admin.generate_statistical_unit_jsonb_indices()
    CALL admin.generate_statistical_unit_jsonb_indices();

    RAISE DEBUG 'Created all statistical_unit UI indices';
END;
$function$
;

CREATE OR REPLACE PROCEDURE admin.generate_statistical_unit_jsonb_indices()
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    ident_type public.external_ident_type;
    stat_definition public.stat_definition;
BEGIN
    -- Loop over each external_ident_type to create indices
    FOR ident_type IN SELECT * FROM public.external_ident_type_enabled LOOP
        -- Create btree index for exact match and prefix searches (all types)
        EXECUTE format($$
CREATE INDEX IF NOT EXISTS su_ei_%1$s_idx ON public.statistical_unit ((external_idents->>%1$L))
$$, ident_type.code);
        RAISE NOTICE 'Created btree index su_ei_%_idx for external_ident_type', ident_type.code;

        -- For hierarchical types, also create a GIST index on the ltree cast
        -- This enables efficient pattern matching with lquery (e.g., '*.CENTRAL.*')
        IF ident_type.shape = 'hierarchical' THEN
            EXECUTE format($$
CREATE INDEX IF NOT EXISTS su_ei_%1$s_ltree_gist_idx ON public.statistical_unit USING GIST (((external_idents->>%1$L)::ltree))
$$, ident_type.code);
            RAISE NOTICE 'Created GIST ltree index su_ei_%_ltree_gist_idx for hierarchical external_ident_type', ident_type.code;
        END IF;
    END LOOP;

    -- Loop over each stat_definition to create indices
    FOR stat_definition IN SELECT * FROM public.stat_definition_enabled LOOP
        EXECUTE format($$
CREATE INDEX IF NOT EXISTS su_s_%1$s_idx ON public.statistical_unit ((stats->>%1$L));
CREATE INDEX IF NOT EXISTS su_ss_%1$s_sum_idx ON public.statistical_unit ((stats_summary->%1$L->>'sum'));
CREATE INDEX IF NOT EXISTS su_ss_%1$s_count_idx ON public.statistical_unit ((stats_summary->%1$L->>'count'));
$$, stat_definition.code);
        RAISE NOTICE 'Created indices for stat_definition %', stat_definition.code;
    END LOOP;
END;
$procedure$
;

CREATE OR REPLACE PROCEDURE admin.cleanup_statistical_unit_jsonb_indices()
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    r RECORD;
BEGIN
    -- Use a query to find and drop all indices matching the patterns
    FOR r IN
        SELECT indexname
        FROM pg_indexes
        WHERE schemaname = 'public'
          AND tablename = 'statistical_unit'
          AND (indexname ILIKE 'su_ei_%_idx'
            OR indexname ILIKE 'su_ei_%_ltree_gist_idx'
            OR indexname ILIKE 'su_s_%_idx'
            OR indexname ILIKE 'su_ss_%_sum_idx'
            OR indexname ILIKE 'su_ss_%_count_idx')
        ORDER BY indexname
    LOOP
        EXECUTE format('DROP INDEX IF EXISTS %I', r.indexname);
        RAISE NOTICE 'Dropped index %', r.indexname;
    END LOOP;
END;
$procedure$
;

COMMENT ON FUNCTION admin.create_statistical_unit_ui_indices() IS
'Recreate all statistical_unit UI indices after bulk operations.
Includes static indices and dynamic jsonb indices.';
COMMENT ON PROCEDURE admin.generate_statistical_unit_jsonb_indices() IS NULL;
COMMENT ON TABLE public.statistical_unit IS NULL;

-- The indexes this migration added.
DO $drop_new$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT indexname FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'statistical_unit'
               AND (indexname ~ '^su_sort_' OR indexname ~ '^su_ss_.*_sum_(asc|desc)_idx$'
                    OR indexname IN ('idx_statistical_unit_status_code', 'idx_statistical_unit_unit_size_code', 'idx_statistical_unit_last_edit_by_user_id'))
    LOOP EXECUTE format('DROP INDEX public.%I', r.indexname); END LOOP;
END;
$drop_new$;

-- Every index and comment as it was: the generator rebuilds the per-statistic text indexes.
SELECT admin.create_statistical_unit_ui_indices();
DO $uncomment$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT c.relname FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid WHERE i.indrelid = 'public.statistical_unit'::regclass
               AND c.relname NOT IN ('idx_statistical_unit_hash_slot', 'statistical_unit_unit_idx')
    LOOP EXECUTE format('COMMENT ON INDEX public.%I IS NULL', r.relname); END LOOP;
END;
$uncomment$;

END;
