BEGIN;

-- Part 3: Remove sequence comments

COMMENT ON SEQUENCE public.worker_task_priority_seq IS NULL;
COMMENT ON SEQUENCE public.import_job_priority_seq IS NULL;
COMMENT ON SEQUENCE public.power_group_ident_seq IS NULL;

-- Part 2: Drop classification views

-- Drop generated views (tag and region_version) via batch API dropper.
-- This drops _custom, _system, _enabled, _ordered views plus upsert/prepare functions and constraints.
SELECT admin.drop_table_views_for_batch_api('public.tag');
SELECT admin.drop_table_views_for_batch_api('public.region_version');

-- Drop manual views (enabled depends on ordered, so drop enabled first).
DROP VIEW IF EXISTS public.country_enabled;
DROP VIEW IF EXISTS public.country_ordered;
DROP VIEW IF EXISTS public.activity_category_standard_enabled;
DROP VIEW IF EXISTS public.activity_category_standard_ordered;

-- Part 1: Drop FK indexes

DROP INDEX IF EXISTS public.ix_power_root_edit_by_user_id;
DROP INDEX IF EXISTS public.ix_stat_for_unit_edit_by_user_id;
DROP INDEX IF EXISTS public.ix_location_region_version_id;
DROP INDEX IF EXISTS public.ix_tag_parent_id;
DROP INDEX IF EXISTS public.ix_image_uploaded_by_user_id;
DROP INDEX IF EXISTS public.ix_legal_unit_image_id;
DROP INDEX IF EXISTS public.ix_establishment_image_id;

END;
