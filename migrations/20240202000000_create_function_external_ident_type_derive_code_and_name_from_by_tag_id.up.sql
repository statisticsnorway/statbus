BEGIN;

CALL lifecycle_callbacks.add_table('public.external_ident_type');

CREATE OR REPLACE FUNCTION public.external_ident_type_derive_code_and_name_from_by_tag_id()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.by_tag_id IS NOT NULL THEN
        SELECT tag.path, tag.name INTO NEW.code, NEW.name
        FROM public.tag
        WHERE tag.id = NEW.by_tag_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER external_ident_type_derive_code_and_name_from_by_tag_id_insert
BEFORE INSERT ON public.external_ident_type
FOR EACH ROW
WHEN (NEW.by_tag_id IS NOT NULL)
EXECUTE FUNCTION public.external_ident_type_derive_code_and_name_from_by_tag_id();

CREATE TRIGGER external_ident_type_derive_code_and_name_from_by_tag_id_update
BEFORE UPDATE ON public.external_ident_type
FOR EACH ROW
WHEN (NEW.by_tag_id IS NOT NULL AND NEW.by_tag_id IS DISTINCT FROM OLD.by_tag_id)
EXECUTE FUNCTION public.external_ident_type_derive_code_and_name_from_by_tag_id();

END;
