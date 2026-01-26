BEGIN;

DROP TRIGGER IF EXISTS external_ident_derive_shape_labels ON public.external_ident;
DROP FUNCTION IF EXISTS public.external_ident_derive_shape_labels();
DROP TABLE IF EXISTS public.external_ident;

END;
