BEGIN;

CREATE FUNCTION admin.type_numeric_field(new_jsonb jsonb, field_name text, p_precision int, p_scale int, OUT numeric_value numeric, INOUT updated_fields_with_error jsonb)
RETURNS record
LANGUAGE plpgsql AS $type_numeric_field$
DECLARE
    field_str TEXT;
    field_with_error JSONB;
BEGIN
    field_str := new_jsonb ->> field_name;

    -- Default unless specified.
    numeric_value := NULL;
    IF field_str IS NOT NULL AND field_str <> '' THEN
        BEGIN
            EXECUTE format('SELECT %L::numeric(%s,%s)', field_str, p_precision, p_scale) INTO numeric_value;
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Invalid % for row % because of %', field_name, new_jsonb, SQLERRM;
            field_with_error := jsonb_build_object(field_name, field_str);
            updated_fields_with_error := updated_fields_with_error || field_with_error;
        END;
    END IF;
END;
$type_numeric_field$;

CREATE FUNCTION admin.type_ltree_field(new_jsonb jsonb, field_name text, OUT ltree_value public.ltree, INOUT updated_fields_with_error jsonb)
RETURNS record
LANGUAGE plpgsql AS $type_ltree_field$
DECLARE
    field_str TEXT;
    field_with_error JSONB;
BEGIN
    field_str := new_jsonb ->> field_name;

    -- Default unless specified.
    ltree_value := NULL;
    IF field_str IS NOT NULL AND field_str <> '' THEN
        BEGIN
            ltree_value := field_str::ltree;
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Invalid % for row % because of %', field_name, new_jsonb, SQLERRM;
            field_with_error := jsonb_build_object(field_name, field_str);
            updated_fields_with_error := updated_fields_with_error || field_with_error;
        END;
    END IF;
END;
$type_ltree_field$;

-- Create a view for region upload using path and name
CREATE VIEW public.region_upload
WITH (security_invoker=on) AS
SELECT path::TEXT
     , name
     , center_latitude::TEXT
     , center_longitude::TEXT
     , center_altitude::TEXT
FROM public.region
ORDER BY path;
COMMENT ON VIEW public.region_upload IS 'Upload of region by path,name that automatically connects parent_id';

CREATE FUNCTION admin.region_upload_upsert()
RETURNS TRIGGER AS $$
DECLARE
    new_jsonb JSONB := to_jsonb(NEW);
    maybe_parent_id int := NULL;
    row RECORD;
    new_typed RECORD;
    fields_with_error JSONB := '{}'::jsonb;
BEGIN
  SELECT NULL::public.ltree AS path
       , NULL::numeric(9, 6) AS center_latitude
       , NULL::numeric(9, 6) AS center_longitude
       , NULL::numeric(6, 1) AS center_altitude
       INTO new_typed;

    SELECT ltree_value    , updated_fields_with_error
    INTO   new_typed.path, fields_with_error
    FROM   admin.type_ltree_field(new_jsonb, 'path', fields_with_error);

    SELECT numeric_value            , updated_fields_with_error
    INTO   new_typed.center_latitude, fields_with_error
    FROM   admin.type_numeric_field(new_jsonb, 'center_latitude', 9, 6, fields_with_error);

    SELECT numeric_value             , updated_fields_with_error
    INTO   new_typed.center_longitude, fields_with_error
    FROM   admin.type_numeric_field(new_jsonb, 'center_longitude', 9, 6, fields_with_error);

    SELECT numeric_value            , updated_fields_with_error
    INTO   new_typed.center_altitude, fields_with_error
    FROM   admin.type_numeric_field(new_jsonb, 'center_altitude', 6, 1, fields_with_error);

    -- Validate path format and find parent
    IF public.nlevel(new_typed.path) > 1 THEN
        SELECT id INTO maybe_parent_id
          FROM public.region
         WHERE path OPERATOR(public.=) public.subltree(new_typed.path, 0, public.nlevel(new_typed.path) - 1);

        IF NOT FOUND THEN
            fields_with_error := fields_with_error || jsonb_build_object('path',
                format('Could not find parent for path %s', new_typed.path));
            RAISE EXCEPTION 'Invalid data: %', fields_with_error;
        END IF;
        RAISE DEBUG 'maybe_parent_id %', maybe_parent_id;
    END IF;

    -- If we found any validation errors, raise them
    IF fields_with_error <> '{}'::jsonb THEN
        RAISE EXCEPTION 'Invalid data: %', jsonb_pretty(
            jsonb_build_object(
                'row', new_jsonb,
                'errors', fields_with_error
            )
        );
    END IF;

    BEGIN
        INSERT INTO public.region (path, parent_id, name, center_latitude, center_longitude, center_altitude)
        VALUES (new_typed.path, maybe_parent_id, NEW.name, new_typed.center_latitude, new_typed.center_longitude, new_typed.center_altitude)
        ON CONFLICT (path)
        DO UPDATE SET
            parent_id = maybe_parent_id,
            name = CASE
                WHEN EXCLUDED.name IS NOT NULL AND EXCLUDED.name <> ''
                THEN EXCLUDED.name
                ELSE region.name
            END,
            center_latitude = EXCLUDED.center_latitude,
            center_longitude = EXCLUDED.center_longitude,
            center_altitude = EXCLUDED.center_altitude
        WHERE region.id = EXCLUDED.id
        RETURNING * INTO row;
      EXCEPTION WHEN OTHERS THEN
          RAISE EXCEPTION 'Failed to insert/update region: %', jsonb_pretty(
              jsonb_build_object(
                  'row', new_jsonb,
                  'error', SQLERRM
              )
          );
      END;
      RAISE DEBUG 'UPSERTED %', to_json(row);

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create triggers for the view
CREATE TRIGGER region_upload_upsert
INSTEAD OF INSERT ON public.region_upload
FOR EACH ROW
EXECUTE FUNCTION admin.region_upload_upsert();

END;
