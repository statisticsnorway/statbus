BEGIN;

-- Remove the copied data first
DELETE FROM public.reorg_type_system;

-- Then drop the views
SELECT admin.drop_table_views_for_batch_api('public.reorg_type');

END;
