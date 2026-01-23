BEGIN;

-- Unregister from lifecycle callbacks first
CALL lifecycle_callbacks.del_table('public.external_ident_type');

DROP TABLE IF EXISTS public.external_ident_type;
DROP TYPE IF EXISTS external_ident_shape;

END;
