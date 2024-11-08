```sql
CREATE OR REPLACE FUNCTION admin.legal_unit_era_upsert()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
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
$function$
```
