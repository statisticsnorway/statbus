BEGIN;

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

DROP TABLE public.custom_view_def_mapping;
DROP TABLE public.custom_view_def_source_column;
DROP TABLE public.custom_view_def;
DROP TABLE public.custom_view_def_target_column;
DROP TABLE public.custom_view_def_target_table;

END;