BEGIN;

\i test/setup.sql

\echo "Establish a baseline"
\sv public.import_legal_unit_era
\sv public.import_establishment_era

\echo "Modify stat_definition"

\echo "Delete unused stat variable".
DELETE FROM public.stat_definition WHERE code = 'employees';

\echo "Make turnover the first variable"
UPDATE public.stat_definition SET priority = 1 wHERE code = 'turnover';

\echo "Add new custom variables"
INSERT INTO public.stat_definition(code, type, frequency, name, description, priority) VALUES
  ('men_employees','int','yearly','Number of men employed','The number of men receiving an official salary with government reporting.',2),
  ('women_employees','int','yearly','Number of women employed','The number of women receiving an official salary with government reporting.',3),
  ('children_employees','int','yearly','Number of children employed','The number of children receiving an official salary with government reporting.',4);

\echo "Stop using the children_employees, it can no longer be imported, but will be in statistics."
UPDATE public.stat_definition SET archived = true wHERE code = 'children_employees';

\echo "Track children by gender"
INSERT INTO public.stat_definition(code, type, frequency, name, description, priority) VALUES
  ('boy_employees','int','yearly','Number of boys employed','The number of boys receiving an official salary with government reporting.',5),
  ('girl_employees','int','yearly','Number of girls employed','The number of girls receiving an official salary with government reporting.',6);

\echo "Modify external_ident_type"

\echo "Delete unused stat identifier".
DELETE FROM public.external_ident_type WHERE code = 'stat_ident';

\echo "Make tax_ident the first identifier"
UPDATE public.external_ident_type SET priority = 1 wHERE code = 'tax_ident';

\echo "Add new custom identifiers"
INSERT INTO public.external_ident_type(code, name, priority, description) VALUES
	('pin', 'Personal Identification Number', 2, 'Stable identifier provided by the governemnt and used by all individials who have a business just for themselves.'),
	('mobile', 'Mobile Number', 3, 'Mandated reporting by all phone companies.');

\echo "Stop using the mobile, peoples number changed to often, it can no longer be imported, but will be in statistics."
UPDATE public.external_ident_type SET archived = true wHERE code = 'mobile';

\echo "Check new generated code"
\sv public.import_legal_unit_era
\sv public.import_establishment_era

ROLLBACK;