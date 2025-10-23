

CREATE OR REPLACE PROCEDURE public.custom_setup_jo()
LANGUAGE plpgsql
AS $BODY$
BEGIN

    RAISE NOTICE 'Runs JO at %', now();
	CALL public.custom_setup_reset();

    -- Before running this procedure you may need to
    -- reset units and classifications in Statbus (Ctrl+Shift+K)
    -- This customization must be completed BEFORE loading legal/establishment units.


    UPDATE status
    SET active = TRUE;

    -- If Jordan has custom statuses, they can be inserted here later



    INSERT INTO external_ident_type (code, name, priority)
    VALUES
        ('national_ident', 'National_Id', 3);

    -- Archive default ones not needed
    UPDATE external_ident_type
    SET archived = TRUE
    WHERE id <= 2;


    INSERT INTO data_source_custom (code, name)
    VALUES
        ('mit1', 'MIT'),
        ('ccd2', 'CCD'),
        ('ssc3', 'SSC');

    INSERT INTO stat_definition (code, type, frequency, name, priority)
    VALUES
        ('jor',        'int', 'yearly', 'Jor',          3),
        ('nonjor',     'int', 'yearly', 'Nonjor',       4),
        ('female',     'int', 'yearly', 'Female',       5),
        ('male',       'int', 'yearly', 'Male',         6),
        ('reg_capital','int', 'yearly', 'Reg_Capital',  7),
        ('cur_capital','int', 'yearly', 'Cur_capital',  8);

    RAISE NOTICE 'Done JO at %', now();

END;
$BODY$;
