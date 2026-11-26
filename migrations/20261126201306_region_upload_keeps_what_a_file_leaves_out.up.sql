-- Migration 20261126201306: region upload keeps what a file leaves out
--
-- A region file adds or changes only what it says (owner 2026-11-26, 5yxn4w). Before, a file of
-- path,name erased every centre it touched (the DO UPDATE set the centre from the file's empty
-- columns), and a file of path plus centre columns was refused for want of a name. Now:
--   * name: needed for a new region; for an existing one an empty or missing name keeps it.
--   * centre: latitude and longitude come as a pair; a row without them keeps the stored centre.
--   * altitude: a given altitude is stored; without one the stored altitude stays, unless the row
--     moves the centre, as the old altitude belonged to the old point.
-- Clearing a centre is an edit on the Regions list or map, not an empty cell.
BEGIN;

CREATE OR REPLACE FUNCTION admin.region_upload_upsert()
 RETURNS trigger
 LANGUAGE plpgsql
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
    v_moves_centre := new_typed.center_latitude IS NOT NULL OR new_typed.center_longitude IS NOT NULL;

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
        INSERT INTO public.region (path, parent_id, name, center_latitude, center_longitude, center_altitude, version_id)
        VALUES (
            new_typed.path,
            maybe_parent_id,
            COALESCE(v_name, v_existing.name),
            CASE WHEN v_moves_centre THEN new_typed.center_latitude ELSE v_existing.center_latitude END,
            CASE WHEN v_moves_centre THEN new_typed.center_longitude ELSE v_existing.center_longitude END,
            CASE
                WHEN new_typed.center_altitude IS NOT NULL THEN new_typed.center_altitude
                WHEN v_moves_centre THEN NULL
                ELSE v_existing.center_altitude
            END,
            v_version_id
        )
        ON CONFLICT (version_id, path)
        DO UPDATE SET
            parent_id = maybe_parent_id,
            name = EXCLUDED.name,
            center_latitude = EXCLUDED.center_latitude,
            center_longitude = EXCLUDED.center_longitude,
            center_altitude = EXCLUDED.center_altitude
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
$function$;

COMMENT ON FUNCTION admin.region_upload_upsert() IS
  'Adds or changes a region from one row of a region file (public.region_upload), connecting its parent by path. A row changes only what it gives: a new region needs a name; an existing one keeps its name when the row has none, keeps its centre when the row has no latitude and longitude, and keeps its altitude unless the row gives one or moves the centre (5yxn4w).';

COMMENT ON VIEW public.region_upload IS
  'Upload of regions by path, with name, and optionally center_latitude, center_longitude and center_altitude. Each row adds or changes one region; columns a row leaves out or empty keep what is stored, so a file of path and centre columns adds centres to the regions already listed (admin.region_upload_upsert).';

END;
