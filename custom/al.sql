
--albania oct 2025

\ir ./reset.sql

CREATE OR REPLACE PROCEDURE public.custom_setup_al()
LANGUAGE plpgsql
AS $BODY$
BEGIN

    RAISE NOTICE 'Runs Tirana at %', now();
	--CALL public.custom_setup_reset();

--select * from external_ident_type
 

--al no need for stat ident
 UPDATE external_ident_type
    SET archived = TRUE
    WHERE id = 2;





    INSERT INTO data_source_custom (code, name)
    VALUES
        ('tax', 'Tax');

--no more default active passive
update status
set active = FALSE
where id =1 or id  = 2;


    INSERT INTO status
        (code, name, assigned_by_default, used_for_counting, priority, active, custom)
    VALUES
        ('1', 'Active', TRUE, TRUE, 3, TRUE, TRUE),    
		('2', 'Closed', FALSE, FALSE, 6, TRUE, TRUE),
        ('3', 'Passive', FALSE, FALSE, 4, TRUE, TRUE),
		('4', 'Never_Active', FALSE, FALSE, 5, TRUE, TRUE);
		


--select * from status


    INSERT INTO stat_definition (code, type, frequency, name, priority)
    VALUES
        ('female', 'int', 'yearly', 'Female', 3),
        ('male', 'int', 'yearly', 'Male', 4),
	 ('selfemp', 'int', 'yearly', 'SelfEmp', 5),
        ('punpag', 'int', 'yearly', 'PunPag', 6);

    RAISE NOTICE 'Done Tirana Albania at %', now();

END;
$BODY$;

CALL public.custom_setup_al();
