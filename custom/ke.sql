
--Erik 


\ir ./reset.sql


CREATE OR REPLACE PROCEDURE public.custom_setup_ke()
LANGUAGE plpgsql
AS $BODY$
BEGIN

    RAISE NOTICE 'Runs KE at %', now();
	CALL public.custom_setup_reset();


    INSERT INTO external_ident_type (code, name, priority)
    VALUES
        ('krapin', 'KRAPin', 3),
        ('brs', 'BRS', 4),
        ('nssf', 'NSSF', 5),
		('sbp', 'SBP', 6),
        ('nhif', 'NHIF', 7);
	
--tbc wont need any of the originals in KE
--hiding tax_ident and stat_ident  --this is a problem ??
 UPDATE external_ident_type
    SET archived = TRUE
    WHERE id <= 2;




    INSERT INTO data_source_custom (code, name)
    VALUES
        ('tax', 'Tax'),    
        ('test', 'Test');

    UPDATE data_source
    SET active = TRUE;


    INSERT INTO stat_definition (code, type, frequency, name, priority)
    VALUES
	    ('female', 'int', 'yearly', 'Female', 3),
		('male', 'int', 'yearly', 'Male', 4),
		('production', 'float', 'yearly', 'Production', 5),
		('sales', 'float', 'yearly', 'Sales', 6);



--sets turnover to the end
update stat_definition
set priority = 7
where id = 2

   -- UPDATE activity_category_standard
   -- SET code_pattern = 'digits'
    --WHERE code = 'nace_v2.1';



    INSERT INTO unit_size (code, name, active, custom)
    VALUES
        ('1', 'Micro', TRUE, TRUE),
        ('2', 'Small', TRUE, TRUE),
        ('3', 'Medium', TRUE, TRUE),
        ('4', 'Large', TRUE, TRUE);


--hide the original ones
update unit_size
set active = FALSE
where custom = FALSE;


    UPDATE status
    SET active = FALSE
    WHERE custom = FALSE;

--select * from status



    INSERT INTO status
        (code, name, assigned_by_default, used_for_counting, priority, active, custom)
    VALUES
        ('active', 'Active', TRUE, TRUE, 3, TRUE, TRUE),
        ('closed', 'Closed', FALSE, false, 4, TRUE, TRUE),
        ('dormant', 'Dormant', FALSE, FALSE, 5, TRUE, TRUE);

    RAISE NOTICE 'Done Kenya at %', now();

END;
$BODY$;


CALL public.custom_setup_ke();
