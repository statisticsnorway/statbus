SET datestyle TO 'ISO, DMY';

BEGIN;

\i test/setup.sql

-- y0wqg9: when a legal unit has no primary establishment yet, the import makes primary the
-- establishment that exists first (public.unit_existence_from: the birth_date, or valid_from without
-- one), whatever the rows' order in the file. jo's legal unit 89 got establishment 86 (born
-- 2024-11-01) as primary over establishment 89 (born 2023-11-01) because 86's row came first.
-- A primary already stored stays: changing it is Set as primary or the workflow 2gpcs7.

CALL test.set_user_from_email('test.admin@statbus.org');

\o /dev/null
\set ECHO none
\i samples/norway/getting-started.sql
\o
\set ECHO all

-- Two legal units, each with two establishments valid from the same day; in the file the
-- later-born establishment comes first.
INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review)
SELECT id, 'import_y0wqg9_lu', 'Test 421 legal units', 'Test 421 (y0wqg9)', false
FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
INSERT INTO public.import_y0wqg9_lu_upload (valid_from, valid_to, tax_ident, name, birth_date) VALUES
    ('2023-01-01', 'infinity', '421000001', 'LU first file row later born', '2000-01-01'),
    ('2023-01-01', 'infinity', '421000002', 'LU first file row no birth', '2000-01-01');

INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review)
SELECT id, 'import_y0wqg9_es', 'Test 421 establishments', 'Test 421 (y0wqg9)', false
FROM public.import_definition WHERE slug = 'establishment_for_lu_source_dates';
INSERT INTO public.import_y0wqg9_es_upload (valid_from, valid_to, tax_ident, legal_unit_tax_ident, name, birth_date) VALUES
    ('2023-01-01', 'infinity', '421100001', '421000001', 'ES born June',  '2023-06-01'),
    ('2023-01-01', 'infinity', '421100002', '421000001', 'ES born March', '2023-03-01'),
    ('2023-01-01', 'infinity', '421100003', '421000002', 'ES born April', '2023-04-01'),
    ('2023-01-01', 'infinity', '421100004', '421000002', 'ES no birth',   NULL);

\o /dev/null
CALL worker.process_tasks(p_queue => 'import');
\o

\echo "421.1 each legal unit's primary establishment is the one that exists first, not the first row"
\echo "      (421000001: March before June; 421000002: no birth date exists from valid_from, before April)"
SELECT lu.name AS legal_unit, es.name AS establishment, es.birth_date, es.primary_for_legal_unit
  FROM public.establishment AS es
  JOIN public.legal_unit AS lu ON lu.id = es.legal_unit_id
 WHERE lu.name LIKE 'LU first file row%'
 ORDER BY lu.name, es.name;

-- A later import brings an establishment born before the stored primary: the primary stays.
INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review)
SELECT id, 'import_y0wqg9_es2', 'Test 421 establishments, second job', 'Test 421 (y0wqg9)', false
FROM public.import_definition WHERE slug = 'establishment_for_lu_source_dates';
INSERT INTO public.import_y0wqg9_es2_upload (valid_from, valid_to, tax_ident, legal_unit_tax_ident, name, birth_date) VALUES
    ('2023-01-01', 'infinity', '421100005', '421000001', 'ES born January, later job', '2023-01-15');

\o /dev/null
CALL worker.process_tasks(p_queue => 'import');
\o

\echo "421.2 a later import does not move a stored primary, even for an earlier-born establishment"
SELECT es.name AS establishment, es.birth_date, es.primary_for_legal_unit
  FROM public.establishment AS es
  JOIN public.legal_unit AS lu ON lu.id = es.legal_unit_id
 WHERE lu.name = 'LU first file row later born'
 ORDER BY es.name;

\echo "421.3 each imported legal unit is primary of its own new enterprise, whatever its file row"
\echo "      (import.process_enterprise_link_for_legal_unit: an import never ranks legal units for an enterprise)"
SELECT lu.name AS legal_unit, lu.primary_for_enterprise,
       (SELECT count(*) FROM public.legal_unit AS o WHERE o.enterprise_id = lu.enterprise_id) AS legal_units_in_enterprise
  FROM public.legal_unit AS lu
 WHERE lu.name LIKE 'LU first file row%'
 ORDER BY lu.name;

ROLLBACK;
