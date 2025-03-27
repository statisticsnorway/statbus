BEGIN;

CREATE VIEW public.stat_for_unit_era
WITH (security_invoker=on) AS
SELECT *
FROM public.stat_for_unit;

CREATE FUNCTION admin.stat_for_unit_era_upsert()
RETURNS TRIGGER AS $stat_for_unit_era_upsert$
DECLARE
  schema_name text := 'public';
  table_name text := 'stat_for_unit';
  unique_columns jsonb := jsonb_build_array(
    'id',
    jsonb_build_array('stat_definition_id', 'establishment_id'),
    jsonb_build_array('stat_definition_id', 'legal_unit_id')
    );
  temporal_columns text[] := ARRAY['valid_from', 'valid_to'];
  ephemeral_columns text[] := ARRAY['edit_comment','edit_by_user_id','edit_at']::text[];
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
$stat_for_unit_era_upsert$ LANGUAGE plpgsql;

CREATE TRIGGER stat_for_unit_era_upsert
INSTEAD OF INSERT ON public.stat_for_unit_era
FOR EACH ROW
EXECUTE FUNCTION admin.stat_for_unit_era_upsert();

END;
