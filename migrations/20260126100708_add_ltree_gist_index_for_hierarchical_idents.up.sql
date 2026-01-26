-- Migration 20260126100708: add_ltree_gist_index_for_hierarchical_idents
BEGIN;

-- Update the procedure to also create GIST indexes for hierarchical identifier types
-- These indexes enable efficient ltree pattern matching queries (using ~ operator with lquery)
CREATE OR REPLACE PROCEDURE admin.generate_statistical_unit_jsonb_indices()
LANGUAGE plpgsql AS $generate_statistical_unit_jsonb_indices$
DECLARE
    ident_type public.external_ident_type;
    stat_definition public.stat_definition;
BEGIN
    -- Loop over each external_ident_type to create indices
    FOR ident_type IN SELECT * FROM public.external_ident_type_active LOOP
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
    FOR stat_definition IN SELECT * FROM public.stat_definition_active LOOP
        EXECUTE format($$
CREATE INDEX IF NOT EXISTS su_s_%1$s_idx ON public.statistical_unit ((stats->>%1$L));
CREATE INDEX IF NOT EXISTS su_ss_%1$s_sum_idx ON public.statistical_unit ((stats_summary->%1$L->>'sum'));
CREATE INDEX IF NOT EXISTS su_ss_%1$s_count_idx ON public.statistical_unit ((stats_summary->%1$L->>'count'));
$$, stat_definition.code);
        RAISE NOTICE 'Created indices for stat_definition %', stat_definition.code;
    END LOOP;
END;
$generate_statistical_unit_jsonb_indices$;

-- Update cleanup procedure to also drop the GIST ltree indexes
CREATE OR REPLACE PROCEDURE admin.cleanup_statistical_unit_jsonb_indices()
LANGUAGE plpgsql AS $cleanup_statistical_unit_jsonb_indices$
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
$cleanup_statistical_unit_jsonb_indices$;

-- Re-run the procedure to create the new GIST indexes for any existing hierarchical types
CALL admin.generate_statistical_unit_jsonb_indices();

END;
