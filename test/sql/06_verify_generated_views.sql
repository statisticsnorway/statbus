
\d+ public.sector_ordered
\d+ public.sector_available
\d+ public.legal_form_ordered
\d+ public.legal_form_available
\d+ public.reorg_type_ordered
\d+ public.reorg_type_available
\d+ public.foreign_participation_ordered
\d+ public.foreign_participation_available
\d+ public.data_source_ordered
\d+ public.data_source_available
\d+ public.unit_size_ordered
\d+ public.unit_size_available
\d+ public.person_type_ordered
\d+ public.person_type_available
\d+ public.enterprise_group_type_ordered
\d+ public.enterprise_group_type_available
\d+ public.enterprise_group_role_ordered
\d+ public.enterprise_group_role_available


BEGIN;

SELECT admin.drop_table_views_for_batch_api('public.sector');

SELECT admin.drop_table_views_for_batch_api('public.legal_form');

SELECT admin.drop_table_views_for_batch_api('public.reorg_type');

SELECT admin.drop_table_views_for_batch_api('public.foreign_participation');

SELECT admin.drop_table_views_for_batch_api('public.data_source');

SELECT admin.drop_table_views_for_batch_api('public.unit_size');

SELECT admin.drop_table_views_for_batch_api('public.person_type');

SELECT admin.drop_table_views_for_batch_api('public.enterprise_group_type');

SELECT admin.drop_table_views_for_batch_api('public.enterprise_group_role');

ROLLBACK;
