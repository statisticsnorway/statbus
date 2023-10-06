BEGIN;

DROP TABLE public.history CASCADE;

DROP TABLE public.activity_category_role CASCADE;
DROP TABLE public.activity_category CASCADE;
DROP TABLE public.activity_legal_unit CASCADE;
DROP TABLE public.activity CASCADE;

DROP TABLE public.enterprise_group_role CASCADE;
DROP TABLE public.enterprise_group CASCADE;
DROP TABLE public.enterprise_unit CASCADE;
DROP TABLE public.enterprise_group_type CASCADE;

DROP TABLE public.address CASCADE;
DROP TABLE public.analysis_log CASCADE;
DROP TABLE public.analysis_queue CASCADE;

DROP TABLE public.country_for_unit CASCADE;
DROP TABLE public.country CASCADE;

DROP TABLE public.custom_analysis_check CASCADE;

DROP TABLE public.data_source_classification CASCADE;
DROP TABLE public.data_source_queue CASCADE;
DROP TABLE public.data_source CASCADE;

DROP TABLE public.data_uploading_log CASCADE;
DROP TABLE public.dictionary_version CASCADE;

DROP TABLE public.foreign_participation CASCADE;

DROP TABLE public.legal_form CASCADE;
DROP TABLE public.legal_unit CASCADE;
DROP TABLE public.local_unit CASCADE;

DROP TABLE public.person_for_unit CASCADE;
DROP TABLE public.person_type CASCADE;
DROP TABLE public.person CASCADE;

DROP TABLE public.postal_index CASCADE;
DROP TABLE public.registration_reason CASCADE;
DROP TABLE public.reorg_type CASCADE;
DROP TABLE public.report_tree CASCADE;
DROP TABLE public.sample_frame CASCADE;
DROP TABLE public.sector_code CASCADE;
DROP TABLE public.unit_size CASCADE;
DROP TABLE public.unit_status CASCADE;

DROP TABLE public.region_role CASCADE;
DROP TABLE public.region CASCADE;

DROP TRIGGER on_auth_user_created ON auth.users;

DROP TABLE public."statbus_user" CASCADE;
DROP TABLE public."statbus_role" CASCADE;

DROP FUNCTION public.create_new_statbus_user();
DROP FUNCTION auth.has_statbus_role (user_uuid UUID, role_type public.statbus_role_type);
DROP FUNCTION auth.has_one_of_statbus_roles (user_uuid UUID, role_types public.statbus_role_type[]);
DROP FUNCTION auth.has_activity_category_access (user_uuid UUID, activity_category_id integer);
DROP FUNCTION auth.has_region_access (user_uuid UUID, region_id integer);

DROP TYPE public.statbus_role_type;

END;