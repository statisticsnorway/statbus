BEGIN;

-- Reverse Migration C: Region versioning + change triggers

-- Drop region change-tracking triggers
DROP TRIGGER IF EXISTS b_region_ensure_collect ON public.region;
DROP TRIGGER IF EXISTS a_region_log_delete ON public.region;
DROP TRIGGER IF EXISTS a_region_log_update ON public.region;
DROP TRIGGER IF EXISTS a_region_log_insert ON public.region;
DROP FUNCTION IF EXISTS worker.log_region_change();

-- Drop activity_category_standard.lasts_to
ALTER TABLE public.activity_category_standard DROP COLUMN IF EXISTS lasts_to;

-- Drop settings dual FK constraints and columns
ALTER TABLE public.settings DROP CONSTRAINT IF EXISTS settings_activity_category_standard_enabled_fk;
ALTER TABLE public.settings DROP CONSTRAINT IF EXISTS settings_region_version_enabled_fk;
DROP INDEX IF EXISTS activity_category_standard_id_enabled_key;
DROP INDEX IF EXISTS region_version_id_enabled_key;
ALTER TABLE public.settings DROP COLUMN IF EXISTS required_to_be_enabled;
ALTER TABLE public.settings DROP COLUMN IF EXISTS region_version_id;

-- Drop location dual FK and version column
ALTER TABLE public.location DROP CONSTRAINT IF EXISTS location_region_dual_fk;
ALTER TABLE public.location DROP COLUMN IF EXISTS region_version_id;

-- Restore region: drop version-scoped indexes, restore global UNIQUE on path
DROP INDEX IF EXISTS region_id_version_id_key;
DROP INDEX IF EXISTS region_version_path_key;
ALTER TABLE public.region ADD CONSTRAINT region_path_key UNIQUE (path);
ALTER TABLE public.region DROP COLUMN IF EXISTS version_id;

-- Drop region_version table (must be after all FKs removed)
DROP INDEX IF EXISTS region_version_enabled_lasts_to_key;
DROP TABLE IF EXISTS public.region_version;

END;
