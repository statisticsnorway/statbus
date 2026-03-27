

\ir ./reset.sql

CREATE OR REPLACE PROCEDURE public.custom_setup_no()
LANGUAGE plpgsql
AS $BODY$
BEGIN

    RAISE NOTICE 'Runs norway at %', now();
	--CALL public.custom_setup_reset();

--only tax ident org number in norway
 UPDATE external_ident_type
    SET enabled = FALSE
    WHERE id != 1;
	
	UPDATE external_ident_type
    SET name = 'Org.Number'
    WHERE id = 1;



END;
$BODY$;

CALL public.custom_setup_no();
