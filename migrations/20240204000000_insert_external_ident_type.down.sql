BEGIN;

DELETE FROM public.external_ident_type WHERE true; -- every row: the down migration removes the seeded types

END;
