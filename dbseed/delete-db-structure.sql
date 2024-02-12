BEGIN;

-- Inspect with:
--   SELECT table_name, column_names, key_name FROM sql_saga.unique_keys;
--   SELECT table_name, column_names, key_name FROM sql_saga.foreign_keys;

-- Drop era handling

SELECT sql_saga.drop_foreign_key('public.location', 'location_establishment_id_valid');
SELECT sql_saga.drop_foreign_key('public.location', 'location_legal_unit_id_valid');
SELECT sql_saga.drop_unique_key('public.location', 'location_id_valid');
SELECT sql_saga.drop_unique_key('public.location', 'location_location_type_establishment_id_valid');
SELECT sql_saga.drop_unique_key('public.location', 'location_location_type_legal_unit_id_valid');
SELECT sql_saga.drop_era('public.location');

SELECT sql_saga.drop_foreign_key('public.stat_for_unit', 'stat_for_unit_establishment_id_valid');
SELECT sql_saga.drop_unique_key('public.stat_for_unit', 'stat_for_unit_stat_definition_id_establishment_id_valid');
SELECT sql_saga.drop_unique_key('public.stat_for_unit', 'stat_for_unit_id_valid');
SELECT sql_saga.drop_era('public.stat_for_unit');

SELECT sql_saga.drop_foreign_key('public.activity', 'activity_establishment_id_valid');
SELECT sql_saga.drop_foreign_key('public.activity', 'activity_legal_unit_id_valid');
SELECT sql_saga.drop_unique_key('public.activity', 'activity_activity_type_activity_category__legal_unit_id_valid');
SELECT sql_saga.drop_unique_key('public.activity', 'activity_activity_type_activity_catego_establishment_i_valid');
SELECT sql_saga.drop_unique_key('public.activity', 'activity_id_valid');
SELECT sql_saga.drop_era('public.activity');

SELECT sql_saga.drop_unique_key('public.establishment', 'establishment_external_ident_external_ident_type_valid');
SELECT sql_saga.drop_unique_key('public.establishment', 'establishment_tax_reg_ident_valid');
SELECT sql_saga.drop_unique_key('public.establishment', 'establishment_stat_ident_valid');
SELECT sql_saga.drop_unique_key('public.establishment', 'establishment_id_valid');
SELECT sql_saga.drop_era('public.establishment');

SELECT sql_saga.drop_unique_key('public.legal_unit', 'legal_unit_external_ident_external_ident_type_valid');
SELECT sql_saga.drop_unique_key('public.legal_unit', 'legal_unit_tax_reg_ident_valid');
SELECT sql_saga.drop_unique_key('public.legal_unit', 'legal_unit_stat_ident_valid');
SELECT sql_saga.drop_unique_key('public.legal_unit', 'legal_unit_id_valid');
SELECT sql_saga.drop_era('public.legal_unit');

SELECT sql_saga.drop_unique_key('public.enterprise_group', 'enterprise_group_external_ident_external_ident_type_valid');
SELECT sql_saga.drop_unique_key('public.enterprise_group', 'enterprise_group_stat_ident_valid');
SELECT sql_saga.drop_unique_key('public.enterprise_group', 'enterprise_group_id_valid');
SELECT sql_saga.drop_era('public.enterprise_group');

DROP FUNCTION public.websearch_to_wildcard_tsquery(text_query text);
DROP FUNCTION public.statistical_unit_refresh_now();
DROP FUNCTION public.statistical_unit_refreshed_at();
DROP FUNCTION public.statistical_unit_facet_drilldown(public.statistical_unit_type,ltree,ltree,date);
DROP MATERIALIZED VIEW public.statistical_unit_facet;
DROP MATERIALIZED VIEW public.region_used;
DROP MATERIALIZED VIEW public.activity_category_used;
DROP MATERIALIZED VIEW public.statistical_unit;
DROP TYPE public.statistical_unit_type;

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
DROP FUNCTION admin.upsert_legal_unit_brreg_view();
DROP FUNCTION admin.delete_stale_legal_unit_brreg_view();

--DROP VIEW public.establishment_current;
DROP VIEW public.establishment_brreg_view;
DROP FUNCTION admin.upsert_establishment_brreg_view();
DROP FUNCTION admin.delete_stale_establishment_brreg_view();

DELETE FROM public.custom_view_def;
DROP TRIGGER custom_view_def_before_trigger ON public.custom_view_def;
DROP TRIGGER custom_view_def_after_trigger ON public.custom_view_def;
DROP FUNCTION admin.custom_view_def_before();
DROP FUNCTION admin.custom_view_def_after();
DROP FUNCTION admin.custom_view_def_generate(record public.custom_view_def);
DROP FUNCTION admin.custom_view_def_destroy(record public.custom_view_def);
DROP FUNCTION admin.custom_view_def_generate_names(record public.custom_view_def);
DROP VIEW admin.custom_view_def_expanded;
DROP TYPE admin.custom_view_def_names;

DROP TRIGGER delete_stale_legal_unit_region_activity_category_current_with_delete_trigger ON public.legal_unit_region_activity_category_current_with_delete;
DROP FUNCTION admin.delete_stale_legal_unit_region_activity_category_current_with_delete();
DROP VIEW public.legal_unit_region_activity_category_current_with_delete;

DROP TRIGGER upsert_legal_unit_region_activity_category_current_trigger ON public.legal_unit_region_activity_category_current;
DROP FUNCTION admin.upsert_legal_unit_region_activity_category_current();
DROP VIEW public.legal_unit_region_activity_category_current;

DROP TRIGGER upsert_establishment_region_activity_category_stats_current_trigger ON public.establishment_region_activity_category_stats_current;
DROP FUNCTION admin.upsert_establishment_region_activity_category_stats_current();
DROP VIEW public.establishment_region_activity_category_stats_current;

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

SELECT admin.drop_table_views_for_batch_api('public.sector_code');
SELECT admin.drop_table_views_for_batch_api('public.legal_form');
SELECT admin.drop_table_views_for_batch_api('public.reorg_type');
SELECT admin.drop_table_views_for_batch_api('public.foreign_participation');
SELECT admin.drop_table_views_for_batch_api('public.data_source_classification');
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

DROP FUNCTION public.generate_mermaid_er_diagram();

DROP TABLE IF EXISTS public.settings;

DROP TABLE public.activity;
DROP TABLE public.activity_category_role;
DROP TABLE public.activity_category;
DROP TABLE public.activity_category_standard;

DROP TABLE public.tag_for_unit;
DROP TABLE public.tag;

DROP TABLE public.country_for_unit;
DROP TABLE public.person_for_unit;

DROP TABLE public.analysis_log;
DROP TABLE public.analysis_queue;

DROP TABLE public.stat_for_unit;
DROP TABLE public.stat_definition;
DROP TYPE public.stat_type;
DROP TYPE public.stat_frequency;
DROP FUNCTION admin.check_stat_for_unit_values;

DROP TABLE public.custom_view_def_mapping;
DROP TABLE public.custom_view_def_source_column;
DROP TABLE public.custom_view_def;
DROP TABLE public.custom_view_def_target_column;
DROP TABLE public.custom_view_def_target_table;

DROP TABLE public.establishment;
DROP TABLE public.legal_unit;

DROP TABLE public.enterprise;
DROP TABLE public.enterprise_group_role;
DROP TABLE public.enterprise_group;
DROP TABLE public.enterprise_group_type;

DROP TABLE public.location;

DROP TABLE public.custom_analysis_check;

DROP TABLE public.data_uploading_log;
DROP TABLE public.data_source_classification;
DROP TABLE public.data_source_queue;
DROP TABLE public.data_source;

DROP TABLE public.foreign_participation;

DROP TABLE public.person_type;
DROP TABLE public.person;

DROP TABLE public.legal_form;
DROP TABLE public.country;

DROP TABLE public.postal_index;
DROP TABLE public.reorg_type;
DROP TABLE public.report_tree;
DROP TABLE public.sample_frame;
DROP TABLE public.sector_code;
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

DROP TYPE public.data_source_priority;
DROP TYPE public.allowed_operations;
DROP TYPE public.stat_unit_type;
DROP TYPE public.data_source_upload_type;

DROP TYPE public.statbus_role_type;
DROP TYPE public.data_source_queue_status;
DROP TYPE public.data_uploading_log_status;
DROP TYPE public.activity_type;
DROP TYPE public.person_sex;
DROP TYPE admin.existing_upsert_case;
DROP TYPE public.location_type;

DROP FUNCTION admin.enterprise_group_id_exists(integer);
DROP FUNCTION admin.legal_unit_id_exists(integer);
DROP FUNCTION admin.establishment_id_exists(integer);

DROP FUNCTION admin.apply_rls_and_policies(regclass);
DROP FUNCTION admin.enable_rls_on_public_tables();

DROP FUNCTION admin.grant_type_and_function_access_to_authenticated();

DROP EXTENSION ltree;
DROP SCHEMA admin CASCADE;

END;