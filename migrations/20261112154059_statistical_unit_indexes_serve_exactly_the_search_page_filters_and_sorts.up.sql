-- Migration 20261112154059: statistical_unit indexes serve exactly the search page filters and sorts
--
-- statistical_unit is what the search page (app/src/app/search) reads through PostgREST. Every
-- index on it is paid for by every recalculation that rewrites its rows, so each index is there
-- for a query that uses it: a search filter, a search sort, or the derive pipeline's own lookups.
-- An index serves a query only when it is built on exactly the expression and order the query
-- uses; test/sql/359 runs every filter and sort the search sends and shows the index each one
-- reads. When the search gets a new filter or sort, its index comes in the same change.
--
-- This migration (STATBUS-627):
--   * drops the ten indexes no query can use (owner decision 2026-11-12; bench box: a 50 %
--     change took 728 s without them against 776-901 s with them, with identical tables);
--   * adds indexes for the four search filters that had none (legal_form_code, status_code,
--     unit_size_code, last_edit_by_user_id: the search filters on the codes, the old indexes
--     are on the ids);
--   * gives every sortable column one index per sort direction, each ending in the search's
--     tie-break (unit_type, unit_id), so the first page and a page from the end are read from
--     the index without sorting the register;
--   * makes admin.generate_statistical_unit_jsonb_indices build, per statistic, the indexes the
--     statistic filter and sort use (on the jsonb sum, not its text), and drop the text ones;
--   * comments every index with the query it serves.
BEGIN;

-- The ten indexes no query can use.
DROP INDEX public.idx_statistical_unit_activity_category_paths;
DROP INDEX public.idx_gist_statistical_unit_activity_category_paths;
DROP INDEX public.idx_statistical_unit_tag_paths;
DROP INDEX public.idx_statistical_unit_external_idents;
DROP INDEX public.idx_gist_statistical_unit_secondary_activity_category_path;
DROP INDEX public.idx_statistical_unit_related_enterprise_ids;
DROP INDEX public.idx_statistical_unit_related_legal_unit_ids;
DROP INDEX public.idx_statistical_unit_related_establishment_ids;
-- su_s_employees_idx and su_ss_employees_sum_idx are rebuilt per statistic below, together with
-- their siblings for every statistic, by the corrected generator.

-- Single-direction sort indexes, replaced by the two-direction pairs below.
DROP INDEX public.idx_statistical_unit_name;
DROP INDEX public.idx_statistical_unit_physical_region_path;
DROP INDEX public.idx_statistical_unit_sector_path;
DROP INDEX public.idx_statistical_unit_primary_activity_category_path;
DROP INDEX public.idx_statistical_unit_secondary_activity_category_path;

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
$function$;

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
$procedure$;

COMMENT ON PROCEDURE admin.generate_statistical_unit_jsonb_indices() IS
'Builds the statistical_unit indexes that depend on the enabled identifier types and statistics: '
'per identifier type the index its search filter uses (external_idents->>code), and per statistic '
'the two indexes the statistic filter and sort use (stats_summary->code->''sum'', ascending and '
'descending with nulls last, each ending in unit_type, unit_id). Runs as a lifecycle callback when '
'external_ident_type or stat_definition change, so a new statistic is searchable fast at once.';

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
            OR indexname ILIKE 'su_ss_%_sum_asc_idx'
            OR indexname ILIKE 'su_ss_%_sum_desc_idx')
        ORDER BY indexname
    LOOP
        EXECUTE format('DROP INDEX IF EXISTS %I', r.indexname);
        RAISE NOTICE 'Dropped index %', r.indexname;
    END LOOP;
END;
$procedure$;

-- The old per-statistic indexes: on stats->>code and on the text of the sum and count, which
-- no query uses (the search reads the jsonb sum).
DO $drop_text_stat_indexes$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT indexname FROM pg_indexes
         WHERE schemaname = 'public' AND tablename = 'statistical_unit'
           AND (indexname ~ '^su_s_.*_idx$' OR indexname ~ '^su_ss_.*_(sum|count)_idx$')
         ORDER BY indexname
    LOOP
        EXECUTE format('DROP INDEX public.%I', r.indexname);
    END LOOP;
END;
$drop_text_stat_indexes$;

-- Every index states the query it serves.
CREATE FUNCTION admin.comment_statistical_unit_indices()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    r RECORD;
    v_comment text;
BEGIN
    FOR r IN
        SELECT c.relname AS indexname
          FROM pg_index AS i JOIN pg_class AS c ON c.oid = i.indexrelid
         WHERE i.indrelid = 'public.statistical_unit'::regclass
           -- These two carry their own comments, written where they were made.
           AND c.relname NOT IN ('idx_statistical_unit_hash_slot', 'statistical_unit_unit_idx')
    LOOP
        v_comment := CASE
            WHEN r.indexname = 'statistical_unit_temporal_pk' THEN
                'Temporal primary key (unit_type, unit_id, valid_range): one row per unit and period.'
            WHEN r.indexname IN ('idx_statistical_unit_unit_type', 'idx_statistical_unit_establishment_id') THEN
                'Unit pages and reports look units up by type and id.'
            WHEN r.indexname = 'idx_statistical_unit_last_edit_by_user_id' THEN
                'Search filter: last edited by (last_edit_by_user_id in ...).'
            WHEN r.indexname ~ '^idx_statistical_unit_.*_id$' THEN
                'Derive pipeline and reports join statistical_unit to its classification by id.'
            WHEN r.indexname = 'idx_statistical_unit_domestic' THEN 'Search filter: domestic.'
            WHEN r.indexname = 'idx_statistical_unit_status_code' THEN 'Search filter: status (status_code in ...).'
            WHEN r.indexname = 'idx_statistical_unit_unit_size_code' THEN 'Search filter: unit size (unit_size_code in ...).'
            WHEN r.indexname = 'idx_statistical_unit_search' THEN 'Search filter: free text (search, full-text query).'
            WHEN r.indexname = 'idx_statistical_unit_data_source_ids' THEN 'Search filter: data source (data_source_ids overlaps ...).'
            WHEN r.indexname = 'idx_gist_statistical_unit_external_idents' THEN 'Identifier lookups by containment (external_idents @> ...).'
            WHEN r.indexname ~ '^idx_gist_statistical_unit_' THEN
                format('Search filter: %s under a chosen code (ltree descendant, cd.).',
                       regexp_replace(r.indexname, '^idx_gist_statistical_unit_', ''))
            WHEN r.indexname ~ '^su_sort_.*_asc$' THEN
                format('Search sort: %s ascending, then unit_type, unit_id; read backwards for a page from the end of a descending sort. Also serves equality filters on the column.',
                       regexp_replace(r.indexname, '^su_sort_(.*)_asc$', '\1'))
            WHEN r.indexname ~ '^su_sort_.*_desc$' THEN
                format('Search sort: %s descending with nulls last, then unit_type, unit_id; read backwards for a page from the end of an ascending sort.',
                       regexp_replace(r.indexname, '^su_sort_(.*)_desc$', '\1'))
            WHEN r.indexname ~ '^su_ss_.*_sum_asc_idx$' THEN
                format('Search filter and sort on statistic %s (stats_summary->code->''sum''): ascending, then unit_type, unit_id. Built by admin.generate_statistical_unit_jsonb_indices.',
                       regexp_replace(r.indexname, '^su_ss_(.*)_sum_asc_idx$', '\1'))
            WHEN r.indexname ~ '^su_ss_.*_sum_desc_idx$' THEN
                format('Search sort on statistic %s (stats_summary->code->''sum''): descending with nulls last, then unit_type, unit_id. Built by admin.generate_statistical_unit_jsonb_indices.',
                       regexp_replace(r.indexname, '^su_ss_(.*)_sum_desc_idx$', '\1'))
            WHEN r.indexname ~ '^su_ei_.*_ltree_gist_idx$' THEN
                format('Search filter: hierarchical identifier %s matched by pattern. Built by admin.generate_statistical_unit_jsonb_indices.',
                       regexp_replace(r.indexname, '^su_ei_(.*)_ltree_gist_idx$', '\1'))
            WHEN r.indexname ~ '^su_ei_.*_idx$' THEN
                format('Search filter: identifier %s (external_idents->>code). Built by admin.generate_statistical_unit_jsonb_indices.',
                       regexp_replace(r.indexname, '^su_ei_(.*)_idx$', '\1'))
        END;
        IF v_comment IS NULL THEN
            RAISE EXCEPTION 'statistical_unit index % has no stated purpose: add it to admin.comment_statistical_unit_indices() with the query it serves, or drop it', r.indexname;
        END IF;
        EXECUTE format('COMMENT ON INDEX public.%I IS %L', r.indexname, v_comment);
    END LOOP;
END;
$function$;

COMMENT ON FUNCTION admin.comment_statistical_unit_indices() IS
'Writes on every statistical_unit index the query it serves, and refuses an index with no stated '
'purpose: every index costs every recalculation that rewrites the table, so each one is there for '
'a search filter, a search sort or a pipeline lookup (STATBUS-627).';

COMMENT ON FUNCTION admin.create_statistical_unit_ui_indices() IS
'Recreate all statistical_unit indices after bulk operations: lookups, search filters, search sorts '
'(both directions) and, through admin.generate_statistical_unit_jsonb_indices, the per identifier '
'type and per statistic ones. Each index is commented with the query it serves.';

SELECT admin.create_statistical_unit_ui_indices();

COMMENT ON TABLE public.statistical_unit IS
'One row per unit and period, derived for the search page and reports. Every index on this table '
'serves a named query (its COMMENT says which) and is paid for by every recalculation; a new search '
'filter or sort adds its index in the same change (admin.create_statistical_unit_ui_indices, '
'test/sql/359).';

END;
