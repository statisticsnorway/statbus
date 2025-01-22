BEGIN;

\echo public.set_primary_establishment_for_legal_unit
DROP FUNCTION public.set_primary_establishment_for_legal_unit(
    establishment_id integer,
    valid_from date,
    valid_to date
    );

END;
