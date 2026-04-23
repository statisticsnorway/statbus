-- Add DB-level COMMENT ON for tables/views that lack them.
--
-- These entities existed in the schema for a long time without a COMMENT —
-- discovered via test 015_generate_data_model_doc which enumerates
-- information_schema.tables + information_schema.views and checks each
-- against a documented-entity list in the test fixture. Adding COMMENTs here
-- surfaces the entity's purpose via `\d+` / pg_dump / standard introspection
-- tools, independent of the fixture.
--
-- Note: public.upgrade, public.system_info, public.upgrade_retention_caps
-- already have COMMENT ON set in their original creation migrations.

BEGIN;

COMMENT ON VIEW public.import_source_column_type IS
    'For a given import definition and source column, returns the target '
    'PostgreSQL type that values in that column will be cast to during '
    'import. Joins import_source_column → import_mapping → import_data_column. '
    'Columns without an active mapping default to TEXT.';

COMMENT ON TABLE public.region_version IS
    'Catalog of region-code generations (e.g. Norway 2020 vs 2024 reform). '
    'Region codes change over time; versioning lets multiple generations '
    'coexist so uploading a new set of regions does not break existing FK '
    'constraints or path uniqueness. lasts_to = NULL marks the current version.';

COMMENT ON TABLE public.statistical_unit_facet_pre_dirty_dims IS
    'Scoped-merge-reduce pre-snapshot for statistical_unit_facet. UNLOGGED + '
    'ephemeral. Holds the dim-combinations that existed in dirty partitions '
    'BEFORE worker children rewrite staging, so the reduce step can scope '
    'aggregate/MERGE/DELETE to the affected combinations only and detect '
    'combinations that disappeared.';

COMMENT ON TABLE public.statistical_history_facet_pre_dirty_dims IS
    'Scoped-merge-reduce pre-snapshot for statistical_history_facet. UNLOGGED + '
    'ephemeral. Same pattern as statistical_unit_facet_pre_dirty_dims, keyed '
    'by (resolution, year, month) plus all 11 history facet dim columns.';

COMMIT;
