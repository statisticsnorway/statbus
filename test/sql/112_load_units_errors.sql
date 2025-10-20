BEGIN;

\i test/setup.sql

\echo "Setting up Statbus using the web provided examples"

-- A Super User configures statbus.
CALL test.set_user_from_email('test.admin@statbus.org');

\i samples/demo/getting-started.sql

SAVEPOINT before_loading_units;

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "Same external ident for legal unit and establishment"

-- Create Import Job for Legal Units (Block 1)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_source_dates'), -- Corrected slug
    'import_31_lu_era_b1',
    'Import LU Era B1 (31_load_units_errors.sql)',
    'Import job for test/data/31_legal_units.csv (Block 1).',
    'Test data load (31_load_units_errors.sql)';
\echo "User uploads legal units (via import job: import_31_lu_era_b1)"
INSERT INTO public.import_31_lu_era_b1_upload(valid_from, valid_to, tax_ident,stat_ident,name,birth_date,physical_region_code,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code) VALUES
('2024-01-01','infinity','2212760144','1000','NILE PEARL WATER','01.10.2016','225613','UG','4752','4','6100',2,9000000,'nlr'),
('2024-01-01','infinity','2812760140','1001','EQUATOR GLOBE SOLUTIONS','01.10.2016','225602','UG','5610','1','6100',2,2400000,'nlr');

-- Create Import Job for Formal Establishments (Block 1 - Errors)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_for_lu_source_dates'), -- Corrected slug
    'import_31_esflu_era_b1',
    'Import Formal ES Era B1 Errors (31_load_units_errors.sql)',
    'Import job for test/data/31_formal_establishments_errors.csv (Block 1).',
    'Test data load (31_load_units_errors.sql)';
\echo "User uploads formal establishments with same stat_ident as legal units (via import job: import_31_esflu_era_b1)"
INSERT INTO public.import_31_esflu_era_b1_upload(valid_from, valid_to, tax_ident,stat_ident,name,physical_region_code,physical_country_iso_2,primary_activity_category_code,employees,turnover,legal_unit_tax_ident,data_source_code) VALUES
('2024-01-01','infinity','92212760144','1000','NILE PEARL WATER','225613','UG','4752',0,0,'2212760144','nlr'),
('2024-01-01','infinity','92812760140','1001','EQUATOR GLOBE SOLUTIONS','225602','UG','5610',0,0,'2812760140','nlr');

\echo Run worker processing for import jobs - Block 1
CALL worker.process_tasks(p_queue => 'import');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\echo "Checking import job statuses for Block 1"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error,
       (SELECT COUNT(*) FROM public.import_31_lu_era_b1_data dr WHERE dr.state = 'error') AS lu_error_rows,
       (SELECT COUNT(*) FROM public.import_31_esflu_era_b1_data dr WHERE dr.state = 'error') AS es_error_rows
FROM public.import_job
WHERE slug IN ('import_31_lu_era_b1', 'import_31_esflu_era_b1') ORDER BY slug;

\echo "Error rows in import_31_esflu_era_b1_data (if any):"
SELECT row_id, state, errors, tax_ident_raw, stat_ident_raw, name_raw, merge_status
FROM public.import_31_esflu_era_b1_data
WHERE (errors IS NOT NULL AND errors IS DISTINCT FROM '{}'::JSONB) OR state = 'error'
ORDER BY row_id;

\echo Run worker processing for analytics tasks - Block 1 (errors primarily tested on import queue)
CALL worker.process_tasks(p_queue => 'analytics');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

ROLLBACK TO before_loading_units;

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "Same external ident for formal establishment and informal establishment"

-- Create Import Job for Legal Units (Block 2)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_source_dates'), -- Corrected slug
    'import_31_lu_era_b2',
    'Import LU Era B2 (31_load_units_errors.sql)',
    'Import job for test/data/31_legal_units.csv (Block 2).',
    'Test data load (31_load_units_errors.sql)';
\echo "User uploads legal units (via import job: import_31_lu_era_b2)"
INSERT INTO public.import_31_lu_era_b2_upload(valid_from, valid_to, tax_ident,stat_ident,name,birth_date,physical_region_code,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code) VALUES
('2024-01-01','infinity','2212760144','1000','NILE PEARL WATER','01.10.2016','225613','UG','4752','4','6100',2,9000000,'nlr'),
('2024-01-01','infinity','2812760140','1001','EQUATOR GLOBE SOLUTIONS','01.10.2016','225602','UG','5610','1','6100',2,2400000,'nlr');

-- Create Import Job for Formal Establishments (Block 2)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_for_lu_source_dates'), -- Corrected slug
    'import_31_esflu_era_b2',
    'Import Formal ES Era B2 (31_load_units_errors.sql)',
    'Import job for test/data/31_formal_establishments.csv (Block 2).',
    'Test data load (31_load_units_errors.sql)';
\echo "User uploads formal establishments (via import job: import_31_esflu_era_b2)"
INSERT INTO public.import_31_esflu_era_b2_upload(valid_from, valid_to, tax_ident,stat_ident,name,physical_region_code,physical_country_iso_2,primary_activity_category_code,employees,turnover,legal_unit_tax_ident,data_source_code) VALUES
('2024-01-01','infinity','92212760144','2000','NILE PEARL WATER','225613','UG','4752',0,0,'2212760144','nlr'),
('2024-01-01','infinity','92812760140','2001','EQUATOR GLOBE SOLUTIONS','225602','UG','5610',0,0,'2812760140','nlr');

-- Create Import Job for Informal Establishments (Block 2 - Errors)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_without_lu_source_dates'), -- Corrected slug
    'import_31_eswlu_era_b2_errors',
    'Import Informal ES Era B2 Errors (31_load_units_errors.sql)',
    'Import job for test/data/31_informal_establishments_errors.csv (Block 2).',
    'Test data load (31_load_units_errors.sql)';
\echo "User uploads informal establishments with same stat_idents as formal establishments (via import job: import_31_eswlu_era_b2_errors)"
INSERT INTO public.import_31_eswlu_era_b2_errors_upload(valid_from, valid_to, tax_ident,stat_ident,name,physical_region_code,physical_country_iso_2,primary_activity_category_code,employees,turnover,data_source_code) VALUES
('2024-01-01','infinity','82212760144','2000','THE NILE PEARL WATER','225613','UG','4752',1,1200,'nlr'),
('2024-01-01','infinity','82812760140','2001','THE  EQUATOR GLOBE SOLUTIONS','225602','UG','5610',2,4400,'nlr');

\echo Run worker processing for import jobs - Block 2
CALL worker.process_tasks(p_queue => 'import');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "Checking import job statuses for Block 2"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error,
       (SELECT COUNT(*) FROM public.import_31_lu_era_b2_data dr WHERE dr.state = 'error') AS lu_error_rows,
       (SELECT COUNT(*) FROM public.import_31_esflu_era_b2_data dr WHERE dr.state = 'error') AS es_formal_error_rows,
       (SELECT COUNT(*) FROM public.import_31_eswlu_era_b2_errors_data dr WHERE dr.state = 'error') AS es_informal_error_rows
FROM public.import_job
WHERE slug IN ('import_31_lu_era_b2', 'import_31_esflu_era_b2', 'import_31_eswlu_era_b2_errors') ORDER BY slug;

\echo "Error rows in import_31_eswlu_era_b2_errors_data (if any):"
SELECT row_id, state, errors, tax_ident_raw, stat_ident_raw, name_raw, merge_status
FROM public.import_31_eswlu_era_b2_errors_data
WHERE (errors IS NOT NULL AND errors IS DISTINCT FROM '{}'::JSONB) OR state = 'error'
ORDER BY row_id;

\echo Run worker processing for analytics tasks - Block 2 (errors primarily tested on import queue)
CALL worker.process_tasks(p_queue => 'analytics');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

ROLLBACK TO before_loading_units;

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;


\echo "User uploads legal units with invalid latitude"
-- Create Import Job for Legal Units (Block 3 - Coordinate Errors)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_source_dates'), -- Corrected slug
    'import_31_lu_era_b3_coord_errors',
    'Import LU Era B3 Various Coord Errors (31_load_units_errors.sql)',
    'Import job with various physical coordinate errors for Legal Units (Block 3).',
    'Test data load (31_load_units_errors.sql)';
INSERT INTO public.import_31_lu_era_b3_coord_errors_upload(valid_from, valid_to, tax_ident,stat_ident,name,birth_date,physical_region_code,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code, physical_latitude, physical_longitude, physical_altitude, web_address, email_address, phone_number) VALUES
-- Original: Latitude out of range (cast error)
('2024-01-01','infinity','2212760144','1000','NILE PEARL WATER','01.10.2016','225613','UG','4752','4','6100',2,9000000,'nlr','3333333','32.2984354','1144','nilepearlwater.ug','contact@npw.ug','123456789'),
-- Original: Valid coordinates
('2024-01-01','infinity','2812760140','1001','EQUATOR GLOBE SOLUTIONS','01.10.2016','225602','UG','5610','1','6100',2,2400000,'nlr','1.234567','32.442243','1172','egs.ug','contact@egs.ug','987654321'),
-- New: Longitude out of range
('2024-01-01','infinity','3000000003','3003','Longitude Range Test LU','01.01.2024','225613','UG','0111','1','1100',1,100000,'test','10.0','190.123456','100',NULL,NULL,NULL),
-- New: Altitude negative
('2024-01-01','infinity','3000000004','3004','Altitude Negative Test LU','01.01.2024','225613','UG','0111','1','1100',1,100000,'test','10.0','30.0','-50.5',NULL,NULL,NULL),
-- New: Latitude invalid text
('2024-01-01','infinity','3000000005','3005','Latitude Text Test LU','01.01.2024','225613','UG','0111','1','1100',1,100000,'test','abc','30.0','100',NULL,NULL,NULL),
-- New: Longitude invalid text
('2024-01-01','infinity','3000000006','3006','Longitude Text Test LU','01.01.2024','225613','UG','0111','1','1100',1,100000,'test','10.0','def','100',NULL,NULL,NULL),
-- New: Altitude invalid text
('2024-01-01','infinity','3000000007','3007','Altitude Text Test LU','01.01.2024','225613','UG','0111','1','1100',1,100000,'test','10.0','30.0','ghi',NULL,NULL,NULL);

\echo Run worker processing for import jobs - Block 3
CALL worker.process_tasks(p_queue => 'import');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\echo "Checking import job status for Block 3 (import_31_lu_era_b3_coord_errors)"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error,
       (SELECT COUNT(*) FROM public.import_31_lu_era_b3_coord_errors_data dr WHERE dr.state = 'error') AS error_rows
FROM public.import_job
WHERE slug = 'import_31_lu_era_b3_coord_errors'
ORDER BY slug;

\echo "Error rows in import_31_lu_era_b3_coord_errors_data (if any):"
SELECT row_id, state, errors, tax_ident_raw, name_raw, physical_latitude_raw, merge_status
FROM public.import_31_lu_era_b3_coord_errors_data
WHERE (errors IS NOT NULL AND errors IS DISTINCT FROM '{}'::JSONB) OR state = 'error'
ORDER BY row_id;

ROLLBACK TO before_loading_units;

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "User uploads legal units with postal coordinates (error condition)"
-- Create Import Job for Legal Units (Block 4 - Postal Coordinate Errors)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_source_dates'),
    'import_31_lu_postal_coord_errors',
    'Import LU Era B4 Postal Coord Errors (31_load_units_errors.sql)',
    'Import job with postal coordinate errors for Legal Units (Block 4).',
    'Test data load (31_load_units_errors.sql)';
INSERT INTO public.import_31_lu_postal_coord_errors_upload(
    valid_from, valid_to, tax_ident, stat_ident, name, birth_date, data_source_code,
    postal_address_part1, postal_country_iso_2, postal_latitude, postal_longitude, postal_altitude
) VALUES
('2024-01-01','infinity','4000000001','4001','Postal Coord Test LU 1','01.01.2024','test', 'PO Box 123', 'UG', '1.0', '32.0', '1100'),
('2024-01-01','infinity','4000000002','4002','Postal Coord Test LU 2 (No Coords)','01.01.2024','test', 'PO Box 456', 'UG', NULL, NULL, NULL);

ROLLBACK;
