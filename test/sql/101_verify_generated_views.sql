
\d+ public.sector_ordered
\d+ public.sector_enabled
\d+ public.legal_form_ordered
\d+ public.legal_form_enabled
\d+ public.legal_reorg_type_ordered
\d+ public.legal_reorg_type_enabled
\d+ public.foreign_participation_ordered
\d+ public.foreign_participation_enabled
\d+ public.data_source_ordered
\d+ public.data_source_enabled
\d+ public.unit_size_ordered
\d+ public.unit_size_enabled
\d+ public.person_role_ordered
\d+ public.person_role_enabled
\d+ public.power_group_type_ordered
\d+ public.power_group_type_enabled
\d+ public.legal_rel_type_ordered
\d+ public.legal_rel_type_enabled


BEGIN;

SELECT admin.drop_table_views_for_batch_api('public.sector');

SELECT admin.drop_table_views_for_batch_api('public.legal_form');

SELECT admin.drop_table_views_for_batch_api('public.legal_reorg_type');

SELECT admin.drop_table_views_for_batch_api('public.foreign_participation');

SELECT admin.drop_table_views_for_batch_api('public.data_source');

SELECT admin.drop_table_views_for_batch_api('public.unit_size');

SELECT admin.drop_table_views_for_batch_api('public.person_role');

SELECT admin.drop_table_views_for_batch_api('public.power_group_type');

SELECT admin.drop_table_views_for_batch_api('public.legal_rel_type');

ROLLBACK;
