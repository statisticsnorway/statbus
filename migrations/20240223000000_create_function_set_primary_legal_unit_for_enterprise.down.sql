BEGIN;

DROP FUNCTION public.set_primary_legal_unit_for_enterprise(
    legal_unit_id integer,
    valid_from date,
    valid_to date
    );

END;
