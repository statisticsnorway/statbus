

\ir ./reset.sql

CREATE OR REPLACE PROCEDURE public.custom_setup_ug()
LANGUAGE plpgsql
AS $BODY$
BEGIN

    RAISE NOTICE 'Runs Uganda Kampala at %', now();
	CALL public.custom_setup_reset();


    INSERT INTO external_ident_type (code, name, priority)
    VALUES
        ('coin_ident', 'CoinId', 3);


 UPDATE external_ident_type
    SET archived = FALSE
    WHERE id <= 2;


    INSERT INTO stat_definition (code, type, frequency, name, priority)
    VALUES
        ('female', 'int', 'yearly', 'Female', 3),
        ('male', 'int', 'yearly', 'Male', 4);

    RAISE NOTICE 'Done Uganda at %', now();

END;
$BODY$;

CALL public.custom_setup_ug();