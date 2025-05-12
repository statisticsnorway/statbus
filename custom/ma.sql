

Select 'Runs MA'  "StatbusStatus", now() "AT";

--takes away external ids if any
delete from external_ident_type where code NOT in ('tax_ident','stat_ident');

INSERT INTO external_ident_type (code, name, priority)
VALUES
('cnss_ident', 'Cnss', 3),
('hcp_ident', 'Hcp', 4),
('ice_ident', 'Ice', 5);

--not using stat_ident - so lest hide this identifier from the statbus app:
update external_ident_type set archived = TRUE where code in ('stat_ident');


delete from data_source_custom ;

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


update data_source
set active = TRUE;



delete from stat_definition where code NOT in ('employees','turnover');
INSERT INTO stat_definition (code, type,frequency, name, priority)
VALUES
('share_capital', 'float', 'yearly', 'Share_capital', 3);

update activity_category_standard
set code_pattern = 'digits'
where code = 'nace_v2.1';



delete from unit_size where id >4 and custom is TRUE;

INSERT INTO unit_size (code, name, active, custom)
VALUES

('t', 'Tiny', TRUE, TRUE),
('p', 'PetitSmall', TRUE, TRUE),
('m', 'Moyen', TRUE, TRUE),
('l', 'Grande', TRUE, TRUE);
--or like this, country to deceide
--(1, 'Tiny', TRUE, TRUE),
--(2, 'PetitSmall', TRUE, TRUE),
--(3, 'Moyen', TRUE, TRUE),
--(4, 'Grande', TRUE, TRUE);



update status
set active = FALSE where custom=FALSE;


delete from status where id >2 and custom=TRUE;
INSERT INTO status (code, name, assigned_by_default, include_unit_in_reports,priority, active, custom)
VALUES
('act', 'Active', TRUE, TRUE,3,TRUE,TRUE),
('inact', 'Inactive', FALSE, TRUE,4,TRUE,TRUE),
('veil', 'En veilleuse', FALSE, TRUE,3,TRUE,TRUE),
('cess', 'Cessation', FALSE, TRUE,4,TRUE,TRUE),
('fus-abs', 'Fusion-Absrption', FALSE, TRUE,5,TRUE,TRUE),
('rad', 'Radiee', FALSE, FALSE,6,TRUE,TRUE);






Select 'Done MA'  "StatbusStatus", now() "AT";
