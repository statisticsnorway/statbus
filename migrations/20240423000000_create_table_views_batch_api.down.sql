BEGIN;

-- Remove the copied data first
DELETE FROM public.legal_reorg_type_system WHERE true; -- every row: the down migration removes the copied data

-- Then drop the views
SELECT admin.drop_table_views_for_batch_api('public.legal_reorg_type');

END;
