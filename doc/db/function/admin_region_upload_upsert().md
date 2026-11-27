```sql
CREATE OR REPLACE FUNCTION admin.region_upload_upsert()
 RETURNS trigger
 LANGUAGE plpgsql
 SET enable_seqscan TO 'off'
AS $function$
DECLARE
    new_jsonb JSONB := to_jsonb(NEW);
    maybe_parent_id int := NULL;
    v_version_id int;
    row RECORD;
    new_typed RECORD;
    fields_with_error JSONB := '{}'::jsonb;
    v_existing public.region%ROWTYPE;
    v_name text := NULLIF(btrim(NEW.name), '');
    v_moves_centre boolean;
BEGIN
  -- Get the current region version: prefer settings, fall back to the current enabled version
  SELECT region_version_id INTO v_version_id FROM public.settings;
  IF v_version_id IS NULL THEN
      SELECT id INTO v_version_id
        FROM public.region_version
       WHERE enabled AND lasts_to IS NULL;
  END IF;
  IF v_version_id IS NULL THEN
      RAISE EXCEPTION 'No current region version found (settings.region_version_id is not set and no enabled version with lasts_to IS NULL exists)';
  END IF;

  SELECT NULL::public.ltree AS path
       , NULL::numeric(9, 6) AS latitude
       , NULL::numeric(9, 6) AS longitude
       , NULL::numeric(6, 1) AS altitude
       INTO new_typed;

    SELECT ltree_value    , updated_fields_with_error
    INTO   new_typed.path, fields_with_error
    FROM   admin.type_ltree_field(new_jsonb, 'path', fields_with_error);

    SELECT numeric_value            , updated_fields_with_error
    INTO   new_typed.latitude, fields_with_error
    FROM   admin.type_numeric_field(new_jsonb, 'latitude', 9, 6, fields_with_error);

    SELECT numeric_value             , updated_fields_with_error
    INTO   new_typed.longitude, fields_with_error
    FROM   admin.type_numeric_field(new_jsonb, 'longitude', 9, 6, fields_with_error);

    SELECT numeric_value            , updated_fields_with_error
    INTO   new_typed.altitude, fields_with_error
    FROM   admin.type_numeric_field(new_jsonb, 'altitude', 6, 1, fields_with_error);

    -- Validate path format and find parent (scoped to same version)
    IF public.nlevel(new_typed.path) > 1 THEN
        SELECT id INTO maybe_parent_id
          FROM public.region
         WHERE path OPERATOR(public.=) public.subltree(new_typed.path, 0, public.nlevel(new_typed.path) - 1)
           AND version_id = v_version_id;

        IF NOT FOUND THEN
            fields_with_error := fields_with_error || jsonb_build_object('path',
                format('Could not find parent for path %s', new_typed.path));
            RAISE EXCEPTION 'Invalid data: %', fields_with_error;
        END IF;
        RAISE DEBUG 'maybe_parent_id %', maybe_parent_id;
    END IF;

    -- The stored region, if any: what the file leaves out is kept from it.
    SELECT * INTO v_existing
      FROM public.region
     WHERE version_id = v_version_id
       AND path OPERATOR(public.=) new_typed.path;
    IF v_existing.id IS NULL AND v_name IS NULL THEN
        fields_with_error := fields_with_error || jsonb_build_object('name',
            format('A new region needs a name (path %s is not in the region list yet)', new_typed.path));
    END IF;
    v_moves_centre := new_typed.latitude IS NOT NULL OR new_typed.longitude IS NOT NULL;

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
        INSERT INTO public.region (path, parent_id, name, latitude, longitude, altitude, version_id)
        VALUES (
            new_typed.path,
            maybe_parent_id,
            COALESCE(v_name, v_existing.name),
            CASE WHEN v_moves_centre THEN new_typed.latitude ELSE v_existing.latitude END,
            CASE WHEN v_moves_centre THEN new_typed.longitude ELSE v_existing.longitude END,
            CASE
                WHEN new_typed.altitude IS NOT NULL THEN new_typed.altitude
                WHEN v_moves_centre THEN NULL
                ELSE v_existing.altitude
            END,
            v_version_id
        )
        ON CONFLICT (version_id, path)
        DO UPDATE SET
            parent_id = maybe_parent_id,
            name = EXCLUDED.name,
            latitude = EXCLUDED.latitude,
            longitude = EXCLUDED.longitude,
            altitude = EXCLUDED.altitude
        -- A row as stored writes nothing, so no change is logged for it.
        WHERE (region.parent_id, region.name, region.latitude, region.longitude, region.altitude)
              IS DISTINCT FROM (maybe_parent_id, EXCLUDED.name, EXCLUDED.latitude, EXCLUDED.longitude, EXCLUDED.altitude)
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
$function$
```
