BEGIN;

DROP FUNCTION IF EXISTS public.import_definition_create_source_and_mappings(integer, text[]);
DROP FUNCTION IF EXISTS public.import_definition_link_steps(integer, text[]);
DROP TRIGGER IF EXISTS trg_import_definition_generate_slug ON public.import_definition;
DROP FUNCTION IF EXISTS admin.import_definition_generate_slug();

END;
