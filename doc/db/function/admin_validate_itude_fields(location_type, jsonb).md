```sql
CREATE OR REPLACE FUNCTION admin.validate_itude_fields(location_type location_type, new_jsonb jsonb)
 RETURNS TABLE(latitude numeric, longitude numeric, altitude numeric)
 LANGUAGE plpgsql
AS $function$
DECLARE
    validated_itude_fields RECORD;
    invalid_codes jsonb := '{}'::jsonb;
BEGIN
    SELECT NULL::numeric(9,6) AS latitude,
           NULL::numeric(9,6) AS longitude,
           NULL::numeric(6,1) AS altitude
    INTO validated_itude_fields;

    SELECT numeric_value            , updated_fields_with_error
    INTO   validated_itude_fields.latitude, invalid_codes
    FROM   admin.type_numeric_field(new_jsonb, location_type || '_latitude', 9, 6, invalid_codes);

    SELECT numeric_value             , updated_fields_with_error
    INTO   validated_itude_fields.longitude, invalid_codes
    FROM   admin.type_numeric_field(new_jsonb, location_type || '_longitude', 9, 6, invalid_codes);

    SELECT numeric_value            , updated_fields_with_error
    INTO   validated_itude_fields.altitude, invalid_codes
    FROM   admin.type_numeric_field(new_jsonb, location_type || '_altitude', 6, 1, invalid_codes);

    IF invalid_codes <> '{}'::jsonb THEN
        RAISE EXCEPTION 'Invalid data: %', jsonb_pretty(
            jsonb_build_object(
                'row', new_jsonb,
                'errors', invalid_codes
            )
        );
    END IF;

    RETURN QUERY
    SELECT validated_itude_fields.latitude,
           validated_itude_fields.longitude,
           validated_itude_fields.altitude;
END;
$function$
```
