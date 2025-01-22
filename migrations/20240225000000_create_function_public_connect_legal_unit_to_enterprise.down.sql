BEGIN;

\echo public.connect_legal_unit_to_enterprise
DROP FUNCTION public.connect_legal_unit_to_enterprise(
    legal_unit_id integer,
    enterprise_id integer,
    valid_from date,
    valid_to date
    );

END;
