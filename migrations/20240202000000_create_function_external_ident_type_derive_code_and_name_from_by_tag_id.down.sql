BEGIN;

CALL lifecycle_callbacks.del_table('public.external_ident_type');

DROP TRIGGER IF EXISTS external_ident_type_derive_code_and_name_from_by_tag_id_insert ON public.external_ident_type;
DROP TRIGGER IF EXISTS external_ident_type_derive_code_and_name_from_by_tag_id_update ON public.external_ident_type;

DROP FUNCTION public.external_ident_type_derive_code_and_name_from_by_tag_id();

END;
