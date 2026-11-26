-- Migration 20261126215254: region change rederives only what it changes
--
-- Storing a regions file that changed nothing re-derived every unit with a location (owner
-- 2026-11-26, 5yxn4w): the upload rewrote each region even when it was as stored, and the change
-- trigger sent every unit of every updated region to be derived again, whatever had changed. A
-- unit carries only its region's id, path and code (timeline_*_def, statistical_unit); name and
-- centre are read live (region_used holds the name, the maps read the centre). Now:
--   * the upload writes a region only when the row differs from what is stored;
--   * an UPDATE logs the units of the regions whose path changed (code is generated from path),
--     and sets a changed name in region_used directly; INSERT and DELETE log as before.
BEGIN;

CREATE OR REPLACE FUNCTION worker.log_region_change()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_est_ids int4multirange;
    v_lu_ids int4multirange;
    v_valid_ranges datemultirange;
    v_source TEXT;
BEGIN
    -- Build source query based on operation. An UPDATE reaches the units only through a region
    -- whose path changed: units carry the region's path and code (code is generated from path),
    -- not its name or centre. A changed name is set in region_used here.
    CASE TG_OP
        WHEN 'INSERT' THEN v_source := 'SELECT * FROM new_rows';
        WHEN 'DELETE' THEN v_source := 'SELECT * FROM old_rows';
        WHEN 'UPDATE' THEN
            v_source := 'SELECT o.* FROM old_rows AS o JOIN new_rows AS n ON n.id = o.id'
                     || ' WHERE n.path OPERATOR(public.<>) o.path';
            -- A renamed region's name in region_used, in place: only the renamed rows.
            UPDATE public.region_used AS ru
               SET name = n.name
              FROM new_rows AS n
             WHERE ru.id = n.id
               AND ru.name IS DISTINCT FROM n.name;
        ELSE RAISE EXCEPTION 'log_region_change: unsupported operation %', TG_OP;
    END CASE;

    -- Find affected units by joining region → location
    EXECUTE format(
        $SQL$
        SELECT
            COALESCE(range_agg(int4range(l.establishment_id, l.establishment_id, '[]')) FILTER (WHERE l.establishment_id IS NOT NULL), '{}'::int4multirange),
            COALESCE(range_agg(int4range(l.legal_unit_id, l.legal_unit_id, '[]')) FILTER (WHERE l.legal_unit_id IS NOT NULL), '{}'::int4multirange),
            COALESCE(range_agg(l.valid_range) FILTER (WHERE l.valid_range IS NOT NULL), '{}'::datemultirange)
        FROM (%s) AS affected_regions
        JOIN public.location AS l ON l.region_id = affected_regions.id
        $SQL$,
        v_source
    ) INTO v_est_ids, v_lu_ids, v_valid_ranges;

    IF v_est_ids != '{}'::int4multirange
       OR v_lu_ids != '{}'::int4multirange THEN
        INSERT INTO worker.base_change_log (establishment_ids, legal_unit_ids, enterprise_ids, power_group_ids, valid_ranges)
        VALUES (v_est_ids, v_lu_ids, '{}'::int4multirange, '{}'::int4multirange, v_valid_ranges);

        PERFORM worker.publish_base_change_wakeup();
    END IF;

    RETURN NULL;
END;
$function$
;

COMMENT ON FUNCTION worker.log_region_change() IS
  'Logs the units a region statement reaches through their locations (worker.base_change_log), so the worker derives them again. Inserted and deleted regions log their units; an update logs only the regions whose path changed, as units carry the region''s path and code but not its name or centre, and sets a changed name in region_used (5yxn4w).';

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
        -- A row as stored writes nothing, so no change is logged for it.
        WHERE (region.parent_id, region.name, region.center_latitude, region.center_longitude, region.center_altitude)
              IS DISTINCT FROM (maybe_parent_id, EXCLUDED.name, EXCLUDED.center_latitude, EXCLUDED.center_longitude, EXCLUDED.center_altitude)
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
;

COMMENT ON FUNCTION admin.region_upload_upsert() IS
  'Adds or changes a region from one row of a region file (public.region_upload), connecting its parent by path. A row changes only what it gives: a new region needs a name; an existing one keeps its name when the row has none, keeps its centre when the row has no latitude and longitude, and keeps its altitude unless the row gives one or moves the centre. A row that matches what is stored writes nothing (5yxn4w).';

END;
