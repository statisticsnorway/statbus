BEGIN;

CREATE PROCEDURE admin.generate_statistical_unit_jsonb_indices()
LANGUAGE plpgsql AS $generate_statistical_unit_jsonb_indices$
DECLARE
    ident_type public.external_ident_type;
    stat_definition public.stat_definition;
BEGIN
    -- Loop over each external_ident_type to create indices
    FOR ident_type IN SELECT * FROM public.external_ident_type_active LOOP
        EXECUTE format($$
CREATE INDEX IF NOT EXISTS su_ei_%1$s_idx ON public.statistical_unit ((external_idents->>%1$L))
$$, ident_type.code);
        RAISE NOTICE 'Created index su_ei_% for external_ident_type', ident_type.code;
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

CREATE PROCEDURE admin.cleanup_statistical_unit_jsonb_indices()
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
          AND indexname ILIKE 'su_ei_%_idx'
            OR indexname ILIKE 'su_s_%_idx'
            OR indexname ILIKE 'su_ss_%_sum_idx'
            OR indexname ILIKE 'su_ss_%_count_idx'
        ORDER BY indexname
    LOOP
        EXECUTE format('DROP INDEX IF EXISTS %I', r.indexname);
        RAISE NOTICE 'Dropped index %', r.indexname;
    END LOOP;
END;
$cleanup_statistical_unit_jsonb_indices$;

CALL lifecycle_callbacks.add(
    'statistical_unit_jsonb_indices',
    ARRAY['public.external_ident_type','public.stat_definition']::regclass[],
    'admin.generate_statistical_unit_jsonb_indices',
    'admin.cleanup_statistical_unit_jsonb_indices'
    );

CALL admin.generate_statistical_unit_jsonb_indices();

END;
