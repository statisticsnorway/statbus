BEGIN;
DROP TRIGGER IF EXISTS location_set_region_version_id_trigger ON public.location;
DROP FUNCTION IF EXISTS public.location_set_region_version_id();
END;
