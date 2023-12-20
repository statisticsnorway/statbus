BEGIN;

-- Drop era handling
SELECT sql_saga.drop_foreign_key('public.enterprise', 'enterprise_enterprise_group_id_valid');
SELECT sql_saga.drop_unique_key('public.enterprise', 'enterprise_id_valid');
SELECT sql_saga.drop_era('public.enterprise');

SELECT sql_saga.drop_unique_key('public.enterprise_group', 'enterprise_group_id_valid');
SELECT sql_saga.drop_era('public.enterprise_group');

SELECT sql_saga.drop_unique_key('public.legal_unit', 'legal_unit_tax_reg_ident_valid');
SELECT sql_saga.drop_unique_key('public.legal_unit', 'legal_unit_id_valid');
SELECT sql_saga.drop_era('public.legal_unit');

SELECT sql_saga.drop_unique_key('public.establishment', 'establishment_tax_reg_ident_valid');
SELECT sql_saga.drop_unique_key('public.establishment', 'establishment_id_valid');
SELECT sql_saga.drop_era('public.establishment');


DROP VIEW public.statistical_units;
DROP VIEW public.activity_category_isic_v4;
DROP VIEW public.activity_category_nace_v2_1;
DROP VIEW public.activity_category_available;

DROP VIEW public.region_view;
DROP FUNCTION admin.upsert_region();
DROP FUNCTION admin.delete_stale_region();

DROP VIEW public.region_7_levels_view;
DROP FUNCTION admin.upsert_region_7_levels();

DROP VIEW public.country_view;
DROP FUNCTION admin.upsert_country();
DROP FUNCTION admin.delete_stale_country();

DROP VIEW public.legal_unit_current;
DROP VIEW public.legal_unit_custom_view;
DROP FUNCTION admin.upsert_legal_unit_custom_view();
DROP FUNCTION admin.delete_stale_legal_unit_custom_view();

--DROP VIEW public.establishment_current;
DROP VIEW public.establishment_custom_view;
DROP FUNCTION admin.upsert_establishment_custom_view();
DROP FUNCTION admin.delete_stale_establishment_custom_view();

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
DROP FUNCTION public.check_stat_for_unit_values;

DROP TABLE public.establishment;
DROP TABLE public.legal_unit;

DROP TABLE public.enterprise;
DROP TABLE public.enterprise_group_role;
DROP TABLE public.enterprise_group;
DROP TABLE public.enterprise_group_type;

DROP TABLE public.address;

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

DROP FUNCTION public.prevent_id_update();
DROP FUNCTION public.create_new_statbus_user();
DROP FUNCTION auth.has_statbus_role (user_uuid UUID, role_type public.statbus_role_type);
DROP FUNCTION auth.has_one_of_statbus_roles (user_uuid UUID, role_types public.statbus_role_type[]);
DROP FUNCTION auth.has_activity_category_access (user_uuid UUID, activity_category_id integer);
DROP FUNCTION auth.has_region_access (user_uuid UUID, region_id integer);

DROP TYPE public.statbus_role_type;
DROP TYPE public.activity_type;
DROP TYPE public.person_sex;

DROP FUNCTION admin.apply_rls_and_policies(regclass);
DROP FUNCTION admin.enable_rls_on_public_tables();

DROP EXTENSION ltree;
DROP SCHEMA admin;

END;