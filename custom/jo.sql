

Select 'Runs JO'  "StatbusStatus", now() "AT";
--before running this script you may want need to Reset units and classifications form statbus Ctrl+shiftK
--This cusomization Must be completed before loading legal / establishment units.



delete from status where custom = TRUE;
update status set active=TRUE;
--if Jo has owns statuses this comes here..
--



--takes away external ids if any
delete from external_ident_type where code in ('tax_ident','stat_ident');




INSERT INTO external_ident_type (code, name, priority)
VALUES
('national_ident', 'National_Id', 3);


--sets default id s off, Jordan only use and need national_id
update external_ident_type
set archived=TRUE where id <=2;


--if unit size custom to be added here..
delete from unit_size where custom is TRUE;

--sample
INSERT INTO unit_size (code, name, active, custom)
VALUES
(1, 'Tiny', TRUE, TRUE),
(2, 'Small', TRUE, TRUE),
(3, 'Medum', TRUE, TRUE),
(4, 'Grande', TRUE, TRUE);



--cleaning up datasources if any
delete from data_source_custom ;

--adds jordan datasources code must exist in unit csv files to be uploaded later
INSERT INTO data_source_custom (code, name)
VALUES
    ('mit1', 'MIT'),
    ('ccd2', 'CCD'),
    ('ssc3', 'SSC');


--cleaning up variables if any, and created the new ones
--code must be used in unit loads later
delete from stat_definition where id >2;
INSERT INTO stat_definition (code, type,frequency, name, priority)
VALUES
('jor', 'int', 'yearly', 'Jor', 3),
('nonjor', 'int', 'yearly', 'Nonjor', 4),
('female', 'int', 'yearly', 'Female', 5),
('male', 'int', 'yearly', 'Male', 6),
('reg_capital', 'int', 'yearly', 'Reg_Capital', 7),
('cur_capital', 'int', 'yearly', 'Cur_capital', 8);




Select 'Done JO'  "StatbusStatus", now() "AT";
