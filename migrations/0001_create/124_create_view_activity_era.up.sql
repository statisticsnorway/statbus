-- View for current information about a activity.
\echo public.activity_era
CREATE VIEW public.activity_era
WITH (security_invoker=on) AS
SELECT *
FROM public.activity;

\echo admin.activity_era_upsert
CREATE FUNCTION admin.activity_era_upsert()
RETURNS TRIGGER AS $activity_era_upsert$
DECLARE
  schema_name text := 'public';
  table_name text := 'activity';
  unique_columns jsonb := jsonb_build_array(
    'id',
    jsonb_build_array('type', 'establishment_id'),
    jsonb_build_array('type', 'legal_unit_id')
    );
  temporal_columns text[] := ARRAY['valid_from', 'valid_to'];
  ephemeral_columns text[] := ARRAY['updated_at'];
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
$activity_era_upsert$ LANGUAGE plpgsql;

CREATE TRIGGER activity_era_upsert
INSTEAD OF INSERT ON public.activity_era
FOR EACH ROW
EXECUTE FUNCTION admin.activity_era_upsert();