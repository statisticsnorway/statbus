
--------------------------------------------------------------
-- DROP PROCEDURE IF EXISTS public.custom_setup_ma;
--CALL public.custom_setup_ma();
--CALL public.custom_setup_jo();
--CALL public.custom_setup_ug();

--CALL public.custom_setup_reset();
--ERIK oct 17 2025


CREATE OR REPLACE PROCEDURE public.custom_setup_reset()
LANGUAGE plpgsql
AS $BODY$
BEGIN

	--sletter custom
    DELETE FROM external_ident_type
    WHERE code NOT IN ('tax_ident', 'stat_ident');

	--viser de begge de som er default de over
	UPDATE external_ident_type
    SET archived = FALSE
    WHERE id <= 2; --not needed

	DELETE FROM data_source_custom;

  	DELETE FROM stat_definition
  	WHERE code NOT IN ('employees', 'turnover');

  	DELETE FROM unit_size
    WHERE id > 4 AND custom = TRUE;

	DELETE FROM status
    WHERE id > 2 AND custom = TRUE;
	
	
--mangler evt jo ug custom to be deleted..	
delete from  public.import_source_column 
where 1 = 1
and column_name in 
( 'ice_ident', 'hcp_ident', 'cnss_ident', 'share_capital', 'legal_unit_ice_ident', 'legal_unit_cnss_ident', 'legal_unit_hcp_ident') ; -- 32 rader rester av morocco som jeg sletter

	
	


--default
update stat_definition
set archived = FALSE
WHERE code IN ('employees', 'turnover');

--default
update status
set active = TRUE
where custom = FALSE;


--default
update unit_size
set active = TRUE
where custom = FALSE;

	

End;
$BODY$;



CREATE OR REPLACE PROCEDURE public.custom_setup_ma()
LANGUAGE plpgsql
AS $BODY$
BEGIN

    RAISE NOTICE 'Runs MA at %', now();
	CALL public.custom_setup_reset();


    INSERT INTO external_ident_type (code, name, priority)
    VALUES
        ('cnss_ident', 'Cnss', 3),
        ('hcp_ident', 'Hcp', 4),
        ('ice_ident', 'Ice', 5);


 UPDATE external_ident_type
    SET archived = FALSE
    WHERE id <= 2;

		

    -- hide stat_ident
    UPDATE external_ident_type
    SET archived = TRUE
    WHERE code = 'stat_ident';

  
    INSERT INTO data_source_custom (code, name)
    VALUES
        ('Base2014', 'Base2014'),
        ('CNSS2014', 'CNSS2014'),
        ('CNSS2015', 'CNSS2015'),
        ('CNSS2016', 'CNSS2016'),
        ('CNSS2017', 'CNSS2017'),
        ('CNSS2018', 'CNSS2018'),
        ('CNSS2019', 'CNSS2019'),
        ('CNSS2020', 'CNSS2020'),
        ('CNSS2021', 'CNSS2021'),
        ('CNSS2022', 'CNSS2022');

    UPDATE data_source
    SET active = TRUE;

   
    INSERT INTO stat_definition (code, type, frequency, name, priority)
    VALUES
        ('share_capital', 'float', 'yearly', 'Share_capital', 3);

    UPDATE activity_category_standard
    SET code_pattern = 'digits'
    WHERE code = 'nace_v2.1';

   

    INSERT INTO unit_size (code, name, active, custom)
    VALUES
        ('tpe', 'Tiny', TRUE, TRUE),
        ('p', 'Petit', TRUE, TRUE),
        ('m', 'Moyen', TRUE, TRUE),
        ('g', 'Grande', TRUE, TRUE);


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
        ('act', 'Active', TRUE, TRUE, 3, TRUE, TRUE),
        ('inact', 'Inactive', FALSE, false, 4, TRUE, TRUE),
        ('veil', 'En veilleuse', FALSE, false, 3, TRUE, TRUE),
        ('cess', 'Cessation', FALSE, TRUE, 4, TRUE, TRUE),
        ('fus-abs', 'Fusion-Absrption', FALSE, TRUE, 5, TRUE, TRUE),
        ('rad', 'Radiee', FALSE, FALSE, 6, TRUE, TRUE);

    RAISE NOTICE 'Done MA at %', now();

END;
$BODY$;







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




