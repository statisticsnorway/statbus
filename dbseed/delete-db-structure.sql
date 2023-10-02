DROP EXTENSION IF EXISTS pg_trgm WITH SCHEMA public;

DROP TABLE public.history;
DROP TABLE public.user_region;
DROP TABLE public.region;

DROP TRIGGER on_auth_user_created;
DROP FUNCTION public.create_new_statbus_user();
DROP TABLE public."user_roles";
DROP TABLE public."user";
DROP TABLE public."role";
DROP TABLE public.activity_category_user;
DROP TABLE public.activity_category;
DROP TABLE public.activity_legal_unit;
DROP TABLE public.activity;

DROP TABLE public.address;
DROP TABLE public.analysis_log;
DROP TABLE public.analysis_queue;

DROP TABLE public.country_for_unit;
DROP TABLE public.country;

DROP TABLE public.custom_analysis_check;

DROP TABLE public.data_source_classification;
DROP TABLE public.data_source_queue;
DROP TABLE public.data_source;

DROP TABLE public.data_uploading_log;
DROP TABLE public.dictionary_version;

DROP TABLE public.enterprise_group_role;
DROP TABLE public.enterprise_group_type;
DROP TABLE public.enterprise_group;
DROP TABLE public.enterprise_unit;

DROP TABLE public.foreign_participation;

DROP TABLE public.legal_form;
DROP TABLE public.legal_unit;
DROP TABLE public.local_unit;
DROP TABLE public.person_for_unit;
DROP TABLE public.person_type;
DROP TABLE public.person;
DROP TABLE public.postal_index;
DROP TABLE public.registration_reason;
DROP TABLE public.reorg_type;
DROP TABLE public.report_tree;
DROP TABLE public.sample_frame;
DROP TABLE public.sector_code;
DROP TABLE public.unit_size;
DROP TABLE public.unit_status;