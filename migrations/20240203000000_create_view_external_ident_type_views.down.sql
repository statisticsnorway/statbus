BEGIN;

\echo Trigger cleanup of external_ident_type generated code.
DROP VIEW public.external_ident_type_active;
DROP VIEW public.external_ident_type_ordered;

END;
