BEGIN;

-- Inspect with:
--   SELECT table_name, column_names, key_name FROM sql_saga.unique_keys;
--   SELECT table_name, column_names, key_name FROM sql_saga.foreign_keys;

-- Drop era handling

\echo public.location
SELECT sql_saga.drop_foreign_key('public.location', 'location_establishment_id_valid');
SELECT sql_saga.drop_foreign_key('public.location', 'location_legal_unit_id_valid');
SELECT sql_saga.drop_unique_key('public.location', 'location_id_valid');
SELECT sql_saga.drop_unique_key('public.location', 'location_type_establishment_id_valid');
SELECT sql_saga.drop_unique_key('public.location', 'location_type_legal_unit_id_valid');
SELECT sql_saga.drop_era('public.location');

\echo public.stat_for_unit
SELECT sql_saga.drop_foreign_key('public.stat_for_unit', 'stat_for_unit_establishment_id_valid');
SELECT sql_saga.drop_unique_key('public.stat_for_unit', 'stat_for_unit_stat_definition_id_establishment_id_valid');
SELECT sql_saga.drop_unique_key('public.stat_for_unit', 'stat_for_unit_id_valid');
SELECT sql_saga.drop_era('public.stat_for_unit');

\echo public.activity
SELECT sql_saga.drop_foreign_key('public.activity', 'activity_establishment_id_valid');
SELECT sql_saga.drop_foreign_key('public.activity', 'activity_legal_unit_id_valid');
SELECT sql_saga.drop_unique_key('public.activity', 'activity_type_category_id_legal_unit_id_valid');
SELECT key_name FROM sql_saga.unique_keys WHERE table_name = 'public.activity'::regclass;
SELECT sql_saga.drop_unique_key('public.activity', 'activity_type_category_id_establishment_id_valid');
SELECT sql_saga.drop_unique_key('public.activity', 'activity_id_valid');
SELECT sql_saga.drop_era('public.activity');

\echo public.establishment
SELECT sql_saga.drop_foreign_key('public.establishment', 'establishment_legal_unit_id_valid');
SELECT sql_saga.drop_unique_key('public.establishment', 'establishment_id_valid');
SELECT sql_saga.drop_era('public.establishment');

\echo public.legal_unit
SELECT sql_saga.drop_unique_key('public.legal_unit', 'legal_unit_id_valid');
SELECT sql_saga.drop_era('public.legal_unit');

\echo public.enterprise_group
SELECT sql_saga.drop_unique_key('public.enterprise_group', 'enterprise_group_id_valid');
SELECT sql_saga.drop_era('public.enterprise_group');

END;
