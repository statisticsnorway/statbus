BEGIN;

-- View for current information about a location.
CREATE VIEW public.location_era
WITH (security_invoker=on) AS
SELECT *
FROM public.location;

CREATE FUNCTION admin.location_era_upsert()
RETURNS TRIGGER AS $location_era_upsert$
DECLARE
  schema_name text := 'public';
  table_name text := 'location';
  unique_columns jsonb := jsonb_build_array(
    'id',
    jsonb_build_array('type', 'establishment_id'),
    jsonb_build_array('type', 'legal_unit_id')
    );
  temporal_columns text[] := ARRAY['valid_from', 'valid_to'];
  ephemeral_columns text[] := ARRAY[]::text[];
BEGIN
  SELECT admin.upsert_generic_valid_time_table
    ( schema_name
    , table_name
    , unique_columns
    , temporal_columns
    , ephemeral_columns
    , NEW
    ) INTO NEW.id;
  RETURN NEW;
END;
$location_era_upsert$ LANGUAGE plpgsql;

CREATE TRIGGER location_era_upsert
INSTEAD OF INSERT ON public.location_era
FOR EACH ROW
EXECUTE FUNCTION admin.location_era_upsert();

END;
