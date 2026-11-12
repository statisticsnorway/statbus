```sql
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

    -- Per statistic, the two indexes the search uses: it filters and sorts on the jsonb sum
    -- (stats_summary->code->'sum', see app/src/atoms/search.ts and url-search-params.ts), so the
    -- indexes are on that exact expression; jsonb compares numbers as numbers, where its text
    -- would put 9 above 100. One index per sort direction, each ending in the tie-break.
    FOR stat_definition IN SELECT * FROM public.stat_definition_enabled LOOP
        EXECUTE format($$
CREATE INDEX IF NOT EXISTS su_ss_%1$s_sum_asc_idx ON public.statistical_unit ((stats_summary->%1$L->'sum'), unit_type, unit_id);
CREATE INDEX IF NOT EXISTS su_ss_%1$s_sum_desc_idx ON public.statistical_unit ((stats_summary->%1$L->'sum') DESC NULLS LAST, unit_type, unit_id);
$$, stat_definition.code);
        RAISE NOTICE 'Created indices for stat_definition %', stat_definition.code;
    END LOOP;
    PERFORM admin.comment_statistical_unit_indices();
END;
$procedure$
```
