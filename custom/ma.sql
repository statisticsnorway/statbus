

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

CALL public.custom_setup_ma();