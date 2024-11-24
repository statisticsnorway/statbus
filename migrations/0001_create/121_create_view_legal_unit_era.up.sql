BEGIN;

-- View for current information about a legal unit.
\echo public.legal_unit_era
CREATE VIEW public.legal_unit_era
WITH (security_invoker=on) AS
SELECT *
FROM public.legal_unit
  ;

\echo admin.legal_unit_era_upsert
CREATE FUNCTION admin.legal_unit_era_upsert()
RETURNS TRIGGER AS $legal_unit_era_upsert$
DECLARE
  schema_name text := 'public';
  table_name text := 'legal_unit';
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
$legal_unit_era_upsert$ LANGUAGE plpgsql;

CREATE TRIGGER legal_unit_era_upsert
INSTEAD OF INSERT ON public.legal_unit_era
FOR EACH ROW
EXECUTE FUNCTION admin.legal_unit_era_upsert();

END;
