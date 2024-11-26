BEGIN;

-- View for current information about a legal unit.
\echo public.establishment_era
CREATE VIEW public.establishment_era
WITH (security_invoker=on) AS
SELECT *
FROM public.establishment
  ;

\echo admin.establishment_era_upsert
CREATE FUNCTION admin.establishment_era_upsert()
RETURNS TRIGGER AS $establishment_era_upsert$
DECLARE
  schema_name text := 'public';
  table_name text := 'establishment';
  unique_columns jsonb :=
    jsonb_build_array(
            'id'
        );
  temporal_columns text[] := ARRAY['valid_from', 'valid_to'];
  ephemeral_columns text[] := ARRAY[]::TEXT[];
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
$establishment_era_upsert$ LANGUAGE plpgsql;

CREATE TRIGGER establishment_era_upsert
INSTEAD OF INSERT ON public.establishment_era
FOR EACH ROW
EXECUTE FUNCTION admin.establishment_era_upsert();

END;
