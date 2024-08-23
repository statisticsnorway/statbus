BEGIN;

-- Inspect with:
--   SELECT table_name, column_names, key_name FROM sql_saga.unique_keys;
--   SELECT table_name, column_names, key_name FROM sql_saga.foreign_keys;

-- Drop era handling

\echo public.location
SELECT sql_saga.drop_foreign_key('public.location', 'location_establishment_id_valid');
SELECT sql_saga.drop_foreign_key('public.location', 'location_legal_unit_id_valid');
SELECT sql_saga.drop_unique_key('public.location', 'location_id_valid');
SELECT sql_saga.drop_unique_key('public.location', 'location_type_establishment_id_valid');
SELECT sql_saga.drop_unique_key('public.location', 'location_type_legal_unit_id_valid');
SELECT sql_saga.drop_era('public.location');

\echo public.stat_for_unit
SELECT sql_saga.drop_foreign_key('public.stat_for_unit', 'stat_for_unit_establishment_id_valid');
SELECT sql_saga.drop_unique_key('public.stat_for_unit', 'stat_for_unit_stat_definition_id_establishment_id_valid');
SELECT sql_saga.drop_unique_key('public.stat_for_unit', 'stat_for_unit_id_valid');
SELECT sql_saga.drop_era('public.stat_for_unit');

\echo public.activity
SELECT sql_saga.drop_foreign_key('public.activity', 'activity_establishment_id_valid');
SELECT sql_saga.drop_foreign_key('public.activity', 'activity_legal_unit_id_valid');
SELECT sql_saga.drop_unique_key('public.activity', 'activity_type_category_id_legal_unit_id_valid');
SELECT key_name FROM sql_saga.unique_keys WHERE table_name = 'public.activity'::regclass;
SELECT sql_saga.drop_unique_key('public.activity', 'activity_type_category_id_establishment_id_valid');
SELECT sql_saga.drop_unique_key('public.activity', 'activity_id_valid');
SELECT sql_saga.drop_era('public.activity');

\echo public.establishment
SELECT sql_saga.drop_foreign_key('public.establishment', 'establishment_legal_unit_id_valid');
SELECT sql_saga.drop_unique_key('public.establishment', 'establishment_id_valid');
SELECT sql_saga.drop_era('public.establishment');

\echo public.legal_unit
SELECT sql_saga.drop_unique_key('public.legal_unit', 'legal_unit_id_valid');
SELECT sql_saga.drop_era('public.legal_unit');

\echo public.enterprise_group
SELECT sql_saga.drop_unique_key('public.enterprise_group', 'enterprise_group_id_valid');
SELECT sql_saga.drop_era('public.enterprise_group');

\echo public.statistical_unit_hierarchy
DROP FUNCTION public.statistical_unit_hierarchy(unit_type public.statistical_unit_type, unit_id INTEGER, valid_on DATE);
\echo public.statistical_unit_enterprise_id
DROP FUNCTION public.statistical_unit_enterprise_id(unit_type public.statistical_unit_type, unit_id INTEGER, valid_on DATE);
\echo public.enterprise_hierarchy
DROP FUNCTION public.enterprise_hierarchy(enterprise_id INTEGER, valid_on DATE);
\echo public.legal_unit_hierarchy
DROP FUNCTION public.legal_unit_hierarchy(parent_enterprise_id INTEGER, valid_on DATE);
\echo public.establishment_hierarchy
DROP FUNCTION public.establishment_hierarchy(parent_legal_unit_id INTEGER,parent_enterprise_id INTEGER,valid_on DATE);
\echo public.sector_hierarchy
DROP FUNCTION public.sector_hierarchy(sector_id INTEGER);
\echo public.legal_form_hierarchy
DROP FUNCTION public.legal_form_hierarchy(legal_form_id INTEGER);
\echo public.activity_hierarchy
DROP FUNCTION public.activity_hierarchy(parent_establishment_id INTEGER,parent_legal_unit_id INTEGER,valid_on DATE);
\echo public.activity_category_hierarchy
DROP FUNCTION public.activity_category_hierarchy(activity_category_id INTEGER);
\echo public.location_hierarchy
DROP FUNCTION public.location_hierarchy(parent_establishment_id INTEGER,parent_legal_unit_id INTEGER,valid_on DATE);
\echo public.stat_for_unit_hierarchy
DROP FUNCTION public.stat_for_unit_hierarchy(parent_establishment_id INTEGER,valid_on DATE);
\echo public.tag_for_unit_hierarchy
DROP FUNCTION public.tag_for_unit_hierarchy(INTEGER,INTEGER,INTEGER,INTEGER);
\echo public.external_idents_hierarchy
DROP FUNCTION public.external_idents_hierarchy(INTEGER,INTEGER,INTEGER,INTEGER);
\echo public.activity_category_standard_hierarchy
DROP FUNCTION public.activity_category_standard_hierarchy(activity_category_standard_id integer);

\echo public.statistical_history
DROP MATERIALIZED VIEW public.statistical_history;
\echo public.statistical_history_def
DROP VIEW public.statistical_history_def;

\echo public.statistical_history_facet
DROP MATERIALIZED VIEW public.statistical_history_facet;
\echo public.statistical_history_facet_def
DROP VIEW public.statistical_history_facet_def;

\echo public.statistical_history_periods
DROP VIEW public.statistical_history_periods;

\echo public.statistical_history_drilldown
DROP FUNCTION public.statistical_history_drilldown;

\echo public.history_resolution
DROP TYPE public.history_resolution;

\echo public.websearch_to_wildcard_tsquery
DROP FUNCTION public.websearch_to_wildcard_tsquery(text_query text);
\echo public.statistical_unit_refresh_now
DROP FUNCTION public.statistical_unit_refresh_now();
\echo public.statistical_unit_refreshed_at
DROP FUNCTION public.statistical_unit_refreshed_at();
\echo public.statistical_unit_facet_drilldown
DROP FUNCTION public.statistical_unit_facet_drilldown(public.statistical_unit_type,ltree,ltree,ltree,integer,integer,date);
DROP MATERIALIZED VIEW public.statistical_unit_facet;
DROP MATERIALIZED VIEW public.region_used;
DROP MATERIALIZED VIEW public.activity_category_used;
DROP MATERIALIZED VIEW public.sector_used;
DROP MATERIALIZED VIEW public.legal_form_used;
DROP MATERIALIZED VIEW public.country_used;
DROP MATERIALIZED VIEW public.statistical_unit;

DROP VIEW public.statistical_unit_def;

DROP VIEW public.enterprise_external_idents;
DROP FUNCTION public.get_external_idents;
DROP FUNCTION public.get_tag_paths;

DROP VIEW public.timeline_enterprise;
DROP VIEW public.timeline_legal_unit;
DROP VIEW public.timeline_establishment;
DROP VIEW public.timesegments;
DROP VIEW public.timepoints;
DROP VIEW public.jsonb_stats;

DROP TYPE public.statistical_unit_type;

DROP AGGREGATE public.jsonb_stats_to_summary_agg(jsonb);
DROP FUNCTION public.jsonb_stats_to_summary(jsonb,jsonb);
DROP AGGREGATE public.jsonb_stats_summary_merge_agg(jsonb);
DROP FUNCTION public.jsonb_stats_summary_merge(jsonb,jsonb);
DROP FUNCTION public.jsonb_stats_to_summary_round(jsonb);

DROP AGGREGATE public.jsonb_concat_agg(jsonb);

DROP VIEW public.activity_category_isic_v4;
DROP VIEW public.activity_category_nace_v2_1;

DROP TRIGGER activity_category_available_custom_upsert_custom ON public.activity_category_available_custom;
DROP FUNCTION admin.activity_category_available_custom_upsert_custom();
DROP VIEW public.activity_category_available_custom;

DROP TRIGGER activity_category_available_upsert_custom ON public.activity_category_available;
DROP FUNCTION admin.activity_category_available_upsert_custom();
DROP VIEW public.activity_category_available;

DROP VIEW public.region_upload;
DROP FUNCTION admin.region_upload_upsert();

DROP VIEW public.region_7_levels_view;
DROP FUNCTION admin.upsert_region_7_levels();

DROP VIEW public.country_view;
DROP FUNCTION admin.upsert_country();
DROP FUNCTION admin.delete_stale_country();

DROP VIEW public.legal_unit_brreg_view;
DROP FUNCTION admin.legal_unit_brreg_view_upsert();

DROP VIEW public.establishment_brreg_view;
DROP FUNCTION admin.upsert_establishment_brreg_view();

DROP TRIGGER import_legal_unit_current_upsert_trigger ON public.import_legal_unit_current;
DROP FUNCTION admin.import_legal_unit_current_upsert();
DROP VIEW public.import_legal_unit_current;

DROP TRIGGER import_legal_unit_era_upsert_trigger ON public.import_legal_unit_era;
DROP FUNCTION admin.import_legal_unit_era_upsert();
DROP VIEW public.import_legal_unit_era;

DROP TRIGGER import_establishment_current_without_legal_unit_upsert_trigger ON public.import_establishment_current_without_legal_unit;
DROP FUNCTION admin.import_establishment_current_without_legal_unit_upsert();
DROP VIEW public.import_establishment_current_without_legal_unit;

DROP TRIGGER import_establishment_era_without_legal_unit_upsert_trigger ON public.import_establishment_era_without_legal_unit;
DROP FUNCTION admin.import_establishment_era_without_legal_unit_upsert();
DROP VIEW public.import_establishment_era_without_legal_unit;

DROP TRIGGER import_establishment_current_for_legal_unit_upsert_trigger ON public.import_establishment_current_for_legal_unit;
DROP FUNCTION admin.import_establishment_current_for_legal_unit_upsert();
DROP VIEW public.import_establishment_current_for_legal_unit;

DROP TRIGGER import_establishment_era_for_legal_unit_upsert_trigger ON public.import_establishment_era_for_legal_unit;
DROP FUNCTION admin.import_establishment_era_for_legal_unit_upsert();
DROP VIEW public.import_establishment_era_for_legal_unit;

CALL admin.cleanup_import_establishment_current();
--DROP TRIGGER import_establishment_current_upsert_trigger ON public.import_establishment_current;
--DROP FUNCTION admin.import_establishment_current_upsert();
--DROP VIEW public.import_establishment_current;

DROP TRIGGER import_establishment_era_upsert_trigger ON public.import_establishment_era;
DROP FUNCTION admin.import_establishment_era_upsert();
DROP VIEW public.import_establishment_era;

DROP TRIGGER legal_unit_era_upsert ON public.legal_unit_era;
DROP FUNCTION admin.legal_unit_era_upsert();
DROP VIEW public.legal_unit_era;

DROP TRIGGER establishment_era_upsert ON public.establishment_era;
DROP FUNCTION admin.establishment_era_upsert();
DROP VIEW public.establishment_era;

DROP TRIGGER location_era_upsert ON public.location_era;
DROP FUNCTION admin.location_era_upsert();
DROP VIEW public.location_era;

DROP TRIGGER activity_era_upsert ON public.activity_era;
DROP FUNCTION admin.activity_era_upsert();
DROP VIEW public.activity_era;

DROP TRIGGER stat_for_unit_era_upsert ON public.stat_for_unit_era;
DROP FUNCTION admin.stat_for_unit_era_upsert();
DROP VIEW public.stat_for_unit_era;

DROP FUNCTION admin.upsert_generic_valid_time_table(text,text,jsonb,text[],text[],record);

DROP VIEW public.sector_available;
DROP VIEW public.sector_custom_only;
DROP FUNCTION admin.sector_custom_only_prepare();
DROP FUNCTION admin.sector_custom_only_upsert();

DROP VIEW public.legal_form_available;
DROP VIEW public.legal_form_custom_only;
DROP FUNCTION admin.legal_form_custom_only_prepare();
DROP FUNCTION admin.legal_form_custom_only_upsert();


DROP FUNCTION admin.import_lookup_tag;
DROP FUNCTION admin.import_lookup_country;
DROP FUNCTION admin.import_lookup_region;
DROP FUNCTION admin.import_lookup_activity_category;
DROP FUNCTION admin.import_lookup_sector;
DROP FUNCTION admin.import_lookup_legal_form;
DROP FUNCTION admin.type_date_field;
DROP FUNCTION admin.process_external_idents;
DROP FUNCTION admin.process_enterprise_connection;
DROP PROCEDURE admin.validate_stats_for_unit(new_jsonb JSONB);
DROP FUNCTION admin.process_linked_legal_unit_external_idents(jsonb);
DROP PROCEDURE admin.process_stats_for_unit(jsonb,text,integer,date,date);
DROP PROCEDURE admin.generate_import_establishment_era();
DROP PROCEDURE admin.cleanup_import_establishment_era();

DELETE FROM public.external_ident_type;
DELETE FROM public.stat_definition;

CALL lifecycle_callbacks.del('import_legal_unit_era');
CALL lifecycle_callbacks.del('import_legal_unit_current');
CALL lifecycle_callbacks.del('import_establishment_era');
CALL lifecycle_callbacks.del('import_establishment_current');
CALL lifecycle_callbacks.del('import_establishment_era_for_legal_unit');

CALL lifecycle_callbacks.del_table('public.external_ident_type');
CALL lifecycle_callbacks.del_table('public.stat_definition');

\echo public.external_ident
DROP TABLE public.external_ident;
\echo Trigger cleanup of external_ident_type generated code.
DROP TABLE public.external_ident_type;
DROP FUNCTION public.external_ident_type_derive_code_and_name_from_by_tag_id();

SELECT admin.drop_table_views_for_batch_api('public.sector');
SELECT admin.drop_table_views_for_batch_api('public.legal_form');
SELECT admin.drop_table_views_for_batch_api('public.reorg_type');
SELECT admin.drop_table_views_for_batch_api('public.foreign_participation');
SELECT admin.drop_table_views_for_batch_api('public.data_source');
SELECT admin.drop_table_views_for_batch_api('public.unit_size');
SELECT admin.drop_table_views_for_batch_api('public.person_type');
SELECT admin.drop_table_views_for_batch_api('public.enterprise_group_type');
SELECT admin.drop_table_views_for_batch_api('public.enterprise_group_role');

DROP FUNCTION admin.generate_view(regclass,admin.view_type_enum);
DROP FUNCTION admin.generate_code_upsert_function(regclass,admin.view_type_enum);
DROP FUNCTION admin.generate_path_upsert_function(regclass,admin.view_type_enum);
DROP FUNCTION admin.generate_delete_function(regclass,admin.view_type_enum);
DROP FUNCTION admin.generate_view_triggers(regclass,regprocedure,regprocedure);
DROP FUNCTION admin.generate_active_code_custom_unique_constraint(regclass);
DROP FUNCTION admin.generate_table_views_for_batch_api(regclass,admin.table_type_enum);
DROP FUNCTION admin.drop_table_views_for_batch_api(regclass);
DROP TYPE admin.view_type_enum;
DROP TYPE admin.table_type_enum;

DROP FUNCTION admin.upsert_activity_category();
DROP FUNCTION admin.delete_stale_activity_category();
DROP FUNCTION admin.prevent_id_update_on_public_tables();

\echo public.generate_mermaid_er_diagram
DROP FUNCTION public.generate_mermaid_er_diagram();

DROP TABLE IF EXISTS public.settings;

DROP TABLE public.activity;
DROP TABLE public.activity_category_role;
DROP TABLE public.activity_category;
DROP TABLE public.activity_category_standard;

DROP TABLE public.tag_for_unit;
DROP TABLE public.person_for_unit;

DROP TABLE public.analysis_log;
DROP TABLE public.analysis_queue;

DROP TABLE public.stat_for_unit;
DROP TABLE public.stat_definition;
DROP TYPE public.stat_type;
DROP TYPE public.stat_frequency;
DROP FUNCTION admin.check_stat_for_unit_values;

DROP TABLE public.establishment;
DROP TABLE public.legal_unit;

DROP TABLE public.enterprise;
DROP TABLE public.enterprise_group_role;
DROP TABLE public.enterprise_group;
DROP TABLE public.enterprise_group_type;

DROP TABLE public.location;

DROP TABLE public.custom_analysis_check;

DROP TABLE public.data_source;

DROP VIEW public.period_active;
DROP TYPE public.period_type;

DROP VIEW public.relative_period_with_time;
DROP TABLE public.relative_period;
DROP TYPE public.relative_period_code;
DROP TYPE public.relative_period_scope;

DROP TABLE public.tag;
DROP TYPE public.tag_type;

DROP TABLE public.foreign_participation;

DROP TABLE public.person_type;
DROP TABLE public.person;

DROP TABLE public.legal_form;
DROP TABLE public.country;

DROP TABLE public.postal_index;
DROP TABLE public.reorg_type;
DROP TABLE public.report_tree;
DROP TABLE public.sample_frame;
DROP TABLE public.sector;
DROP TABLE public.unit_size;

DROP TABLE public.region_role;
DROP TABLE public.region;

DROP TRIGGER on_auth_user_created ON auth.users;

DROP TABLE public.statbus_user;
DROP TABLE public.statbus_role;

DROP FUNCTION admin.prevent_id_update();
DROP FUNCTION admin.create_new_statbus_user();
DROP FUNCTION auth.has_statbus_role (user_uuid UUID, role_type public.statbus_role_type);
DROP FUNCTION auth.has_one_of_statbus_roles (user_uuid UUID, role_types public.statbus_role_type[]);
DROP FUNCTION auth.has_activity_category_access (user_uuid UUID, activity_category_id integer);
DROP FUNCTION auth.has_region_access (user_uuid UUID, region_id integer);

DROP TYPE public.statbus_role_type;
DROP TYPE public.activity_type;
DROP TYPE public.person_sex;
DROP TYPE admin.existing_upsert_case;
DROP TYPE public.location_type;

DROP FUNCTION admin.enterprise_group_id_exists(integer);
DROP FUNCTION admin.legal_unit_id_exists(integer);
DROP FUNCTION admin.establishment_id_exists(integer);

\echo public.set_primary_legal_unit_for_enterprise
DROP FUNCTION public.set_primary_legal_unit_for_enterprise(
    legal_unit_id integer,
    valid_from date,
    valid_to date
    );
\echo public.set_primary_establishment_for_legal_unit
DROP FUNCTION public.set_primary_establishment_for_legal_unit(
    establishment_id integer,
    valid_from date,
    valid_to date
    );
\echo public.connect_legal_unit_to_enterprise
DROP FUNCTION public.connect_legal_unit_to_enterprise(
    legal_unit_id integer,
    enterprise_id integer,
    valid_from date,
    valid_to date
    );

DROP TABLE lifecycle_callbacks.registered_callback;
DROP TABLE lifecycle_callbacks.supported_table;
DROP PROCEDURE lifecycle_callbacks.add_table(regclass);
DROP PROCEDURE lifecycle_callbacks.del_table(regclass);
DROP PROCEDURE lifecycle_callbacks.add(text,regclass[],regproc,regproc);
DROP PROCEDURE lifecycle_callbacks.del(text);
DROP FUNCTION lifecycle_callbacks.run_table_lifecycle_insert();
DROP FUNCTION lifecycle_callbacks.run_table_lifecycle_update();
DROP FUNCTION lifecycle_callbacks.run_table_lifecycle_delete();
DROP PROCEDURE lifecycle_callbacks.generate(regclass);
DROP PROCEDURE lifecycle_callbacks.clean(regclass);
DROP SCHEMA lifecycle_callbacks CASCADE;

DROP PROCEDURE admin.generate_import_legal_unit_current();
DROP PROCEDURE admin.cleanup_import_legal_unit_current();
DROP PROCEDURE admin.generate_import_legal_unit_era();
DROP PROCEDURE admin.cleanup_import_legal_unit_era();

DROP PROCEDURE admin.generate_import_establishment_era();
DROP PROCEDURE admin.cleanup_import_establishment_era();
DROP PROCEDURE admin.generate_import_establishment_current();
DROP PROCEDURE admin.cleanup_import_establishment_current();

DROP PROCEDURE admin.generate_import_establishment_era_for_legal_unit();
DROP PROCEDURE admin.cleanup_import_establishment_era_for_legal_unit();
DROP PROCEDURE admin.generate_import_establishment_current_for_legal_unit();
DROP PROCEDURE admin.cleanup_import_establishment_current_for_legal_unit();

DROP PROCEDURE admin.generate_import_establishment_era_without_legal_unit();
DROP PROCEDURE admin.cleanup_import_establishment_era_without_legal_unit();
DROP PROCEDURE admin.generate_import_establishment_current_without_legal_unit();
DROP PROCEDURE admin.cleanup_import_establishment_current_without_legal_unit();

DROP FUNCTION admin.render_template(text,jsonb);
DROP FUNCTION public.remove_ephemeral_data_from_hierarchy(JSONB);

\echo public.reset_all_data
DROP FUNCTION public.reset_all_data(confirmed boolean);

DROP FUNCTION admin.apply_rls_and_policies(regclass);
DROP FUNCTION admin.enable_rls_on_public_tables();

DROP FUNCTION admin.grant_type_and_function_access_to_authenticated();

DROP EXTENSION ltree;
DROP SCHEMA admin CASCADE;

END;