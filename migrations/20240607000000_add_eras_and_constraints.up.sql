BEGIN;

-- Activate era handling
SELECT sql_saga.add_era('public.enterprise_group', 'valid_after', 'valid_to');
SELECT sql_saga.add_unique_key('public.enterprise_group', ARRAY['id']);

SELECT sql_saga.add_era('public.legal_unit', 'valid_after', 'valid_to');
SELECT sql_saga.add_unique_key('public.legal_unit', ARRAY['id']);
-- TODO: Use a scoped sql_saga unique key for enterprise_id below.
-- SELECT sql_saga.add_unique_key('public.legal_unit', ARRAY['enterprise_id'], WHERE 'primary_for_enterprise');

SELECT sql_saga.add_era('public.establishment', 'valid_after', 'valid_to');
SELECT sql_saga.add_unique_key('public.establishment', ARRAY['id']);
-- TODO: Extend sql_saga with support for predicates by using unique indices instead of constraints.
--SELECT sql_saga.add_unique_key('public.establishment', ARRAY['legal_unit_id'], WHERE 'primary_for_legal_unit');
SELECT sql_saga.add_foreign_key('public.establishment', ARRAY['legal_unit_id'], 'valid', 'legal_unit_id_valid');

SELECT sql_saga.add_era('public.activity', 'valid_after', 'valid_to');
SELECT sql_saga.add_unique_key('public.activity', ARRAY['id']);
SELECT sql_saga.add_unique_key('public.activity', ARRAY['type', 'category_id', 'establishment_id']);
SELECT sql_saga.add_unique_key('public.activity', ARRAY['type', 'category_id', 'legal_unit_id']);
SELECT sql_saga.add_foreign_key('public.activity', ARRAY['establishment_id'], 'valid', 'establishment_id_valid');
SELECT sql_saga.add_foreign_key('public.activity', ARRAY['legal_unit_id'], 'valid', 'legal_unit_id_valid');

SELECT sql_saga.add_era('public.stat_for_unit', 'valid_after', 'valid_to');
SELECT sql_saga.add_unique_key('public.stat_for_unit', ARRAY['id']);
SELECT sql_saga.add_unique_key('public.stat_for_unit', ARRAY['stat_definition_id', 'establishment_id']);
SELECT sql_saga.add_foreign_key('public.stat_for_unit', ARRAY['establishment_id'], 'valid', 'establishment_id_valid');
SELECT sql_saga.add_foreign_key('public.stat_for_unit', ARRAY['legal_unit_id'], 'valid', 'legal_unit_id_valid');

SELECT sql_saga.add_era('public.person_for_unit', 'valid_after', 'valid_to');
SELECT sql_saga.add_unique_key('public.person_for_unit', ARRAY['id']);
SELECT sql_saga.add_unique_key('public.person_for_unit', ARRAY['person_id', 'person_role_id', 'establishment_id']);
SELECT sql_saga.add_unique_key('public.person_for_unit', ARRAY['person_id', 'person_role_id', 'legal_unit_id']);
SELECT sql_saga.add_foreign_key('public.person_for_unit', ARRAY['establishment_id'], 'valid', 'establishment_id_valid');
SELECT sql_saga.add_foreign_key('public.person_for_unit', ARRAY['legal_unit_id'], 'valid', 'legal_unit_id_valid');

SELECT sql_saga.add_era('public.location', 'valid_after', 'valid_to');
SELECT sql_saga.add_unique_key('public.location', ARRAY['id']);
SELECT sql_saga.add_unique_key('public.location', ARRAY['type', 'establishment_id']);
SELECT sql_saga.add_unique_key('public.location', ARRAY['type', 'legal_unit_id']);
SELECT sql_saga.add_foreign_key('public.location', ARRAY['establishment_id'], 'valid', 'establishment_id_valid');
SELECT sql_saga.add_foreign_key('public.location', ARRAY['legal_unit_id'], 'valid', 'legal_unit_id_valid');

SELECT sql_saga.add_era('public.contact', 'valid_after', 'valid_to');
SELECT sql_saga.add_unique_key('public.contact', ARRAY['id']);
SELECT sql_saga.add_foreign_key('public.contact', ARRAY['establishment_id'], 'valid', 'establishment_id_valid');
SELECT sql_saga.add_foreign_key('public.contact', ARRAY['legal_unit_id'], 'valid', 'legal_unit_id_valid');

TABLE sql_saga.era;
TABLE sql_saga.unique_keys;
TABLE sql_saga.foreign_keys;

END;
