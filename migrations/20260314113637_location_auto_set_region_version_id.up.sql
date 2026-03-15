BEGIN;

CREATE OR REPLACE FUNCTION public.location_set_region_version_id()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY INVOKER
AS $location_set_region_version_id$
BEGIN
  NEW.region_version_id := (
    SELECT r.version_id FROM public.region AS r WHERE r.id = NEW.region_id
  );
  RETURN NEW;
END;
$location_set_region_version_id$;

CREATE TRIGGER location_set_region_version_id_trigger
  BEFORE INSERT OR UPDATE OF region_id ON public.location
  FOR EACH ROW
  WHEN (NEW.region_id IS NOT NULL AND NEW.region_version_id IS NULL)
  EXECUTE FUNCTION public.location_set_region_version_id();

END;
