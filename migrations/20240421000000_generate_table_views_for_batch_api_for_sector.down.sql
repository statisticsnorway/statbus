BEGIN;

SELECT admin.drop_table_views_for_batch_api('public.sector');
DROP INDEX IF EXISTS ix_sector_enabled_path;

END;
