BEGIN;

-- Auto-generate slug from name when not provided
CREATE OR REPLACE FUNCTION admin.import_definition_generate_slug()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $import_definition_generate_slug$
BEGIN
  IF NEW.slug IS NULL OR NEW.slug = '' THEN
    NEW.slug := lower(regexp_replace(NEW.name, '[^a-zA-Z0-9]+', '_', 'g'));
    NEW.slug := trim(both '_' from NEW.slug);
  END IF;
  RETURN NEW;
END;
$import_definition_generate_slug$;

CREATE TRIGGER trg_import_definition_generate_slug
  BEFORE INSERT ON public.import_definition
  FOR EACH ROW EXECUTE FUNCTION admin.import_definition_generate_slug();

-- Public wrappers for import schema functions (PostgREST only exposes public schema)
CREATE OR REPLACE FUNCTION public.import_definition_link_steps(
  p_definition_id integer,
  p_step_codes text[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
AS $import_definition_link_steps$
BEGIN
  PERFORM import.link_steps_to_definition(p_definition_id, p_step_codes);
END;
$import_definition_link_steps$;

CREATE OR REPLACE FUNCTION public.import_definition_create_source_and_mappings(
  p_definition_id integer,
  p_source_columns text[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
AS $import_definition_create_source_and_mappings$
BEGIN
  PERFORM import.create_source_and_mappings_for_definition(p_definition_id, p_source_columns);
END;
$import_definition_create_source_and_mappings$;

END;
