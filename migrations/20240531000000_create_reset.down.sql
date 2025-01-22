BEGIN;

\echo public.reset
DROP FUNCTION public.reset (confirmed boolean, scope public.reset_scope);
DROP TYPE public.reset_scope;

END;
