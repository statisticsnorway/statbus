-- Migration 20250127204854: create_view_contact_era
BEGIN;

-- View for current information about a contact.
CREATE VIEW public.contact_era
WITH (security_invoker=on) AS
SELECT *
FROM public.contact;

CREATE FUNCTION admin.contact_era_upsert()
RETURNS TRIGGER AS $contact_era_upsert$
DECLARE
  schema_name text := 'public';
  table_name text := 'contact';
  unique_columns jsonb := jsonb_build_array(
    'id',
    jsonb_build_array('establishment_id'),
    jsonb_build_array('legal_unit_id')
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
$contact_era_upsert$ LANGUAGE plpgsql;

CREATE TRIGGER contact_era_upsert
INSTEAD OF INSERT ON public.contact_era
FOR EACH ROW
EXECUTE FUNCTION admin.contact_era_upsert();

END;
