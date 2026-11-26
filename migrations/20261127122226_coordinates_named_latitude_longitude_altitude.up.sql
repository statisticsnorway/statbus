-- jbc5bs/kvbebr: coordinates have one plain name, latitude, longitude, altitude,
-- for regions, units and the import. A postal address has no position
-- (public.location's postal_locations_cannot_have_coordinates), so the
-- physical_ prefix names no distinction and the postal_* coordinate columns go.
-- Old file headers (center_* for regions, physical_latitude/longitude/altitude
-- for units) are a hard cut (owner 2026-11-27): no code names them, so a file
-- carrying them is refused or ignored as any unknown column is.
BEGIN;

-- 1. Views naming the columns go first; they are recreated below.
DROP VIEW public.statistical_unit_def;
DROP VIEW public.timeline_power_group_def;
DROP VIEW public.timeline_enterprise_def;
DROP VIEW public.timeline_legal_unit_def;
DROP VIEW public.timeline_establishment_def;
DROP VIEW public.region_upload;

-- 2. Regions: center_* becomes plain.
ALTER TABLE public.region RENAME COLUMN center_latitude TO latitude;
ALTER TABLE public.region RENAME COLUMN center_longitude TO longitude;
ALTER TABLE public.region RENAME COLUMN center_altitude TO altitude;
ALTER TABLE public.region RENAME CONSTRAINT "center coordinates all or nothing" TO "coordinates require both latitude and longitude";
ALTER TABLE public.region RENAME CONSTRAINT center_altitude_must_be_positive TO altitude_must_be_positive;
ALTER TABLE public.region RENAME CONSTRAINT center_latitude_must_be_from_minus_90_to_90_degrees TO latitude_must_be_from_minus_90_to_90_degrees;
ALTER TABLE public.region RENAME CONSTRAINT center_longitude_must_be_from_minus_180_to_180_degrees TO longitude_must_be_from_minus_180_to_180_degrees;
COMMENT ON COLUMN public.region.latitude IS 'Latitude of the point that places the region on a map (decimal degrees, -90 to 90).';
COMMENT ON COLUMN public.region.longitude IS 'Longitude of the point that places the region on a map (decimal degrees, -180 to 180).';
COMMENT ON COLUMN public.region.altitude IS 'Altitude of that point (metres, >= 0); only with latitude and longitude.';

-- 3. Units: physical_* coordinates become plain, postal coordinates go.
DO $rename_unit_coordinates$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY['timeline_establishment', 'timeline_legal_unit', 'timeline_enterprise',
                                   'timeline_power_group', 'statistical_unit', 'statistical_unit_staging'] LOOP
        EXECUTE format($$ALTER TABLE public.%1$I RENAME COLUMN physical_latitude TO latitude$$, v_table);
        EXECUTE format($$ALTER TABLE public.%1$I RENAME COLUMN physical_longitude TO longitude$$, v_table);
        EXECUTE format($$ALTER TABLE public.%1$I RENAME COLUMN physical_altitude TO altitude$$, v_table);
        EXECUTE format($$ALTER TABLE public.%1$I DROP COLUMN IF EXISTS postal_latitude, DROP COLUMN IF EXISTS postal_longitude, DROP COLUMN IF EXISTS postal_altitude$$, v_table);
    END LOOP;
END;
$rename_unit_coordinates$;
COMMENT ON COLUMN public.statistical_unit.latitude IS 'Latitude of the unit''s physical location (decimal degrees). Only physical locations have a position.';
COMMENT ON COLUMN public.statistical_unit.longitude IS 'Longitude of the unit''s physical location (decimal degrees). Only physical locations have a position.';
COMMENT ON COLUMN public.statistical_unit.altitude IS 'Altitude of the unit''s physical location (metres). Only physical locations have a position.';

-- 4. Import: the physical location step takes latitude/longitude/altitude,
-- the postal location step takes no coordinates.
UPDATE public.import_data_column AS dc
   SET column_name = substr(dc.column_name, length('physical_') + 1)
  FROM public.import_step AS s
 WHERE s.id = dc.step_id AND s.code = 'physical_location'
   AND dc.column_name IN ('physical_latitude', 'physical_longitude', 'physical_altitude',
                          'physical_latitude_raw', 'physical_longitude_raw', 'physical_altitude_raw');

DELETE FROM public.import_mapping AS m
 USING public.import_data_column AS dc, public.import_step AS s
 WHERE m.target_data_column_id = dc.id AND s.id = dc.step_id AND s.code = 'postal_location'
   AND dc.column_name IN ('postal_latitude_raw', 'postal_longitude_raw', 'postal_altitude_raw');
DELETE FROM public.import_data_column AS dc
 USING public.import_step AS s
 WHERE s.id = dc.step_id AND s.code = 'postal_location'
   AND dc.column_name IN ('postal_latitude', 'postal_longitude', 'postal_altitude',
                          'postal_latitude_raw', 'postal_longitude_raw', 'postal_altitude_raw');

UPDATE public.import_source_column AS sc
   SET column_name = substr(sc.column_name, length('physical_') + 1)
 WHERE sc.column_name IN ('physical_latitude', 'physical_longitude', 'physical_altitude');
DELETE FROM public.import_mapping AS m
 USING public.import_source_column AS sc
 WHERE m.source_column_id = sc.id
   AND sc.column_name IN ('postal_latitude', 'postal_longitude', 'postal_altitude');
DELETE FROM public.import_source_column AS sc
 WHERE sc.column_name IN ('postal_latitude', 'postal_longitude', 'postal_altitude');

-- Existing jobs: their tables and snapshots follow the same names, so a job
-- made before this migration still reads and processes.
DO $rename_job_coordinates$
DECLARE
    v_job record;
    v_old text;
    v_new text;
BEGIN
    FOR v_job IN SELECT id, upload_table_name, data_table_name FROM public.import_job ORDER BY id LOOP
        FOREACH v_old IN ARRAY ARRAY['physical_latitude', 'physical_longitude', 'physical_altitude'] LOOP
            v_new := substr(v_old, length('physical_') + 1);
            IF EXISTS (SELECT 1 FROM information_schema.columns
                        WHERE table_schema = 'public' AND table_name = v_job.upload_table_name AND column_name = v_old) THEN
                EXECUTE format($$ALTER TABLE public.%1$I RENAME COLUMN %2$I TO %3$I$$, v_job.upload_table_name, v_old, v_new);
            END IF;
            IF EXISTS (SELECT 1 FROM information_schema.columns
                        WHERE table_schema = 'public' AND table_name = v_job.data_table_name AND column_name = v_old) THEN
                EXECUTE format($$ALTER TABLE public.%1$I RENAME COLUMN %2$I TO %3$I$$, v_job.data_table_name, v_old, v_new);
            END IF;
            IF EXISTS (SELECT 1 FROM information_schema.columns
                        WHERE table_schema = 'public' AND table_name = v_job.data_table_name AND column_name = v_old || '_raw') THEN
                EXECUTE format($$ALTER TABLE public.%1$I RENAME COLUMN %2$I TO %3$I$$, v_job.data_table_name, v_old || '_raw', v_new || '_raw');
            END IF;
        END LOOP;
        FOREACH v_old IN ARRAY ARRAY['postal_latitude', 'postal_longitude', 'postal_altitude'] LOOP
            EXECUTE format($$ALTER TABLE IF EXISTS public.%1$I DROP COLUMN IF EXISTS %2$I$$, v_job.upload_table_name, v_old);
            EXECUTE format($$ALTER TABLE IF EXISTS public.%1$I DROP COLUMN IF EXISTS %2$I, DROP COLUMN IF EXISTS %3$I$$, v_job.data_table_name, v_old, v_old || '_raw');
        END LOOP;
    END LOOP;
END;
$rename_job_coordinates$;

UPDATE public.import_job AS j
   SET definition_snapshot = j.definition_snapshot
       || jsonb_build_object(
            'import_data_column_list',
            (SELECT COALESCE(jsonb_agg(CASE WHEN e->>'column_name' ~ '^physical_(latitude|longitude|altitude)(_raw)?$'
                                            THEN jsonb_set(e, '{column_name}', to_jsonb(substr(e->>'column_name', length('physical_') + 1)))
                                            ELSE e END ORDER BY o), '[]'::jsonb)
               FROM jsonb_array_elements(j.definition_snapshot->'import_data_column_list') WITH ORDINALITY AS t(e, o)
              WHERE NOT e->>'column_name' ~ '^postal_(latitude|longitude|altitude)(_raw)?$'),
            'import_source_column_list',
            (SELECT COALESCE(jsonb_agg(CASE WHEN e->>'column_name' ~ '^physical_(latitude|longitude|altitude)$'
                                            THEN jsonb_set(e, '{column_name}', to_jsonb(substr(e->>'column_name', length('physical_') + 1)))
                                            ELSE e END ORDER BY o), '[]'::jsonb)
               FROM jsonb_array_elements(j.definition_snapshot->'import_source_column_list') WITH ORDINALITY AS t(e, o)
              WHERE NOT e->>'column_name' ~ '^postal_(latitude|longitude|altitude)$'),
            'import_mapping_list',
            (SELECT COALESCE(jsonb_agg(
                        CASE WHEN e->'source_column'->>'column_name' ~ '^physical_(latitude|longitude|altitude)$'
                             THEN jsonb_set(e, '{source_column,column_name}', to_jsonb(substr(e->'source_column'->>'column_name', length('physical_') + 1)))
                             ELSE e END ORDER BY o), '[]'::jsonb)
               FROM jsonb_array_elements(j.definition_snapshot->'import_mapping_list') WITH ORDINALITY AS t(e, o)
              WHERE NOT COALESCE(e->'target_data_column'->>'column_name', '') ~ '^postal_(latitude|longitude|altitude)_raw$')
          )
 WHERE j.definition_snapshot::text ~ '(physical|postal)_(latitude|longitude|altitude)';
UPDATE public.import_job AS j
   SET definition_snapshot = jsonb_set(j.definition_snapshot, '{import_mapping_list}',
       (SELECT COALESCE(jsonb_agg(
                   CASE WHEN e->'target_data_column'->>'column_name' ~ '^physical_(latitude|longitude|altitude)_raw$'
                        THEN jsonb_set(e, '{target_data_column,column_name}', to_jsonb(substr(e->'target_data_column'->>'column_name', length('physical_') + 1)))
                        ELSE e END ORDER BY o), '[]'::jsonb)
          FROM jsonb_array_elements(j.definition_snapshot->'import_mapping_list') WITH ORDINALITY AS t(e, o)))
 WHERE j.definition_snapshot::text ~ 'physical_(latitude|longitude|altitude)';

-- 5. Functions and procedures, from their \sf definitions with the columns renamed.
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
;

CREATE OR REPLACE PROCEDURE import.analyse_location(IN p_job_id integer, IN p_batch_seq integer, IN p_step_code text)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_error_count INT := 0;
    v_update_count INT := 0;
    v_sql TEXT;
    v_error_json_expr_sql TEXT; -- For dt.error (fatal) - though this step makes them non-fatal
    v_warnings_json_expr_sql TEXT; -- For dt.warnings (non-fatal)
    v_error_keys_to_clear_arr TEXT[];
    v_warning_keys_to_clear_arr TEXT[];
    v_skipped_update_count INT;
    error_message TEXT;
    v_error_condition_sql TEXT; -- For non-fatal warnings
    v_fatal_error_condition_sql TEXT; -- For fatal errors like missing country
    v_fatal_error_json_expr_sql TEXT; -- For fatal error messages
    v_address_present_condition_sql TEXT; -- To check if any address part is present
    v_default_country_id INT; -- Default country from settings for region validation
    -- Country defaulting expressions: when source is NULL/empty AND the OWN-branch address parts
    -- are present, default to settings.country_id. Defined once (branch-agnostic) so each call
    -- writes both physical_country_id and postal_country_id consistently — preventing the next
    -- branch's run from clobbering the defaulted value.
    v_physical_country_id_expr TEXT;
    v_postal_country_id_expr TEXT;

    -- For coordinate validation
    v_coord_cast_error_json_expr_sql TEXT;
    v_coord_range_error_json_expr_sql TEXT;
    v_postal_coord_present_error_json_expr_sql TEXT := $$'{}'::jsonb$$; -- Default to SQL literal for empty JSONB
    v_coord_invalid_value_json_expr_sql TEXT;
    v_any_coord_error_condition_sql TEXT;
BEGIN
    RAISE DEBUG '[Job %] analyse_location (Batch) for step_code %: Starting analysis for batch_seq %', p_job_id, p_step_code, p_batch_seq;

    -- Load default country from settings for region validation - FAIL FAST if not configured.
    -- This is the foundation for both region-context checks and country defaulting (below).
    SELECT country_id INTO v_default_country_id FROM public.settings LIMIT 1;
    IF v_default_country_id IS NULL THEN
        RAISE EXCEPTION '[Job %] analyse_location: No country_id configured in settings table. System must be configured with a default country before processing location data. Run getting-started setup first.', p_job_id;
    END IF;

    -- Validate that the country_id actually exists in the country table
    IF NOT EXISTS (SELECT 1 FROM public.country WHERE id = v_default_country_id) THEN
        RAISE EXCEPTION '[Job %] analyse_location: Invalid country_id % in settings table. Country does not exist in country table.', p_job_id, v_default_country_id;
    END IF;

    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;

    -- Find the step details from the snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = p_step_code;
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] analyse_location: Step with code % not found in snapshot.', p_job_id, p_step_code;
    END IF;

    RAISE DEBUG '[Job %] analyse_location: Processing for target % (code: %, priority %)', p_job_id, v_step.name, v_step.code, v_step.priority;

    -- Branch-agnostic defaulting expressions for the UPDATE clause. Both branches write
    -- both physical_country_id and postal_country_id (legacy of the unified UPDATE), so
    -- defaulting must reference each column's OWN address-present condition independently.
    v_physical_country_id_expr := format($$
        CASE WHEN NULLIF(dt.physical_country_iso_2_raw, '') IS NULL
                  AND (NULLIF(dt.physical_address_part1_raw, '') IS NOT NULL
                       OR NULLIF(dt.physical_address_part2_raw, '') IS NOT NULL
                       OR NULLIF(dt.physical_address_part3_raw, '') IS NOT NULL
                       OR NULLIF(dt.physical_postcode_raw, '') IS NOT NULL
                       OR NULLIF(dt.physical_postplace_raw, '') IS NOT NULL
                       OR NULLIF(dt.physical_region_code_raw, '') IS NOT NULL)
             THEN %1$L::INTEGER
             ELSE l.resolved_physical_country_id
        END
    $$, v_default_country_id);
    v_postal_country_id_expr := format($$
        CASE WHEN NULLIF(dt.postal_country_iso_2_raw, '') IS NULL
                  AND (NULLIF(dt.postal_address_part1_raw, '') IS NOT NULL
                       OR NULLIF(dt.postal_address_part2_raw, '') IS NOT NULL
                       OR NULLIF(dt.postal_address_part3_raw, '') IS NOT NULL
                       OR NULLIF(dt.postal_postcode_raw, '') IS NOT NULL
                       OR NULLIF(dt.postal_postplace_raw, '') IS NOT NULL
                       OR NULLIF(dt.postal_region_code_raw, '') IS NOT NULL)
             THEN %1$L::INTEGER
             ELSE l.resolved_postal_country_id
        END
    $$, v_default_country_id);

    IF p_step_code = 'physical_location' THEN
        v_error_keys_to_clear_arr := ARRAY[
            'physical_region_code_raw',
            'physical_country_iso_2_raw',
            'latitude_raw', -- Error key for latitude issues
            'longitude_raw', -- Error key for longitude issues
            'altitude_raw' -- Error key for altitude issues
        ];
        v_warning_keys_to_clear_arr := ARRAY['physical_region_code_raw', 'physical_country_iso_2_raw', 'latitude_raw', 'longitude_raw', 'altitude_raw'];
        v_address_present_condition_sql := $$
            (NULLIF(dt.physical_address_part1_raw, '') IS NOT NULL OR NULLIF(dt.physical_address_part2_raw, '') IS NOT NULL OR NULLIF(dt.physical_address_part3_raw, '') IS NOT NULL OR
             NULLIF(dt.physical_postcode_raw, '') IS NOT NULL OR NULLIF(dt.physical_postplace_raw, '') IS NOT NULL OR NULLIF(dt.physical_region_code_raw, '') IS NOT NULL)
        $$;
        -- Fatal conditions (two, mutually exclusive on a single row):
        --   (a) Country code supplied + invalid + address present → unprincipled, can't store.
        --   (b) Region supplied + country resolved as foreign → unprincipled (region is domestic-only).
        v_fatal_error_condition_sql := format($$(
            (%2$s AND NULLIF(dt.physical_country_iso_2_raw, '') IS NOT NULL AND l.resolved_physical_country_id IS NULL)
            OR
            (dt.physical_region_code_raw IS NOT NULL AND l.resolved_physical_country_id IS NOT NULL AND l.resolved_physical_country_id IS DISTINCT FROM %1$L)
        )$$, v_default_country_id, v_address_present_condition_sql);
        v_fatal_error_json_expr_sql := format($$
            jsonb_strip_nulls(jsonb_build_object(
                'physical_country_iso_2_raw',
                CASE WHEN (%2$s AND NULLIF(dt.physical_country_iso_2_raw, '') IS NOT NULL AND l.resolved_physical_country_id IS NULL)
                     THEN 'Country is required and must be valid when other physical address details are provided.'
                     ELSE NULL END,
                'physical_region_code_raw',
                CASE WHEN (dt.physical_region_code_raw IS NOT NULL AND l.resolved_physical_country_id IS NOT NULL AND l.resolved_physical_country_id IS DISTINCT FROM %1$L)
                     THEN 'Region can only be supplied for the domestic country.'
                     ELSE NULL END
            ))
        $$, v_default_country_id, v_address_present_condition_sql);
        v_error_condition_sql := format($$
            -- Invalid region codes for any country (both domestic and foreign)
            (dt.physical_region_code_raw IS NOT NULL AND l.resolved_physical_region_id IS NULL) OR
            -- Missing region warnings for domestic countries: either resolved-as-domestic
            -- or country-defaulted-to-domestic (source NULL + address present). The warning
            -- lives on the field that is actually missing — the region. Country defaulting
            -- itself is silent (regions exist only in the domestic country, so when a region
            -- is supplied the country is implied; when neither is supplied the country
            -- defaults silently and the missing-region warning surfaces below).
            (dt.physical_region_code_raw IS NULL AND (
                (l.resolved_physical_country_id IS NOT DISTINCT FROM %1$L AND l.resolved_physical_country_id IS NOT NULL)
                OR (NULLIF(dt.physical_country_iso_2_raw, '') IS NULL AND %2$s)
            )) OR
            -- Invalid country code without address (no-address case, otherwise fatal handles it).
            (dt.physical_country_iso_2_raw IS NOT NULL AND l.resolved_physical_country_id IS NULL AND NOT (%2$s)) OR
            (dt.latitude_raw IS NOT NULL AND l.latitude_error_msg IS NOT NULL) OR
            (dt.longitude_raw IS NOT NULL AND l.longitude_error_msg IS NOT NULL) OR
            (dt.altitude_raw IS NOT NULL AND l.altitude_error_msg IS NOT NULL)
        $$, v_default_country_id, v_address_present_condition_sql);

        v_warnings_json_expr_sql := format($$
            CASE
                WHEN dt.physical_region_code_raw IS NOT NULL AND l.resolved_physical_region_id IS NULL THEN jsonb_build_object('physical_region_code_raw', dt.physical_region_code_raw)  -- Invalid region code
                WHEN dt.physical_region_code_raw IS NULL AND (
                       (l.resolved_physical_country_id IS NOT DISTINCT FROM %1$L AND l.resolved_physical_country_id IS NOT NULL)
                       OR (NULLIF(dt.physical_country_iso_2_raw, '') IS NULL AND %2$s)
                     ) THEN jsonb_build_object('physical_region_code_raw', NULL)  -- Missing region for domestic country (resolved or defaulted)
                ELSE '{}'::jsonb
            END ||
            -- NOTE: no country_defaulted warning. The warning about absence lives on the
            -- region above — that's the actually-missing data. Country defaulting is silent
            -- because the region (when supplied) implies the country.
            CASE WHEN dt.physical_country_iso_2_raw IS NOT NULL AND l.resolved_physical_country_id IS NULL THEN jsonb_build_object('physical_country_iso_2_raw', dt.physical_country_iso_2_raw) ELSE '{}'::jsonb END ||
            CASE WHEN dt.latitude_raw IS NOT NULL AND l.latitude_error_msg IS NOT NULL THEN jsonb_build_object('latitude_raw', dt.latitude_raw) ELSE '{}'::jsonb END ||
            CASE WHEN dt.longitude_raw IS NOT NULL AND l.longitude_error_msg IS NOT NULL THEN jsonb_build_object('longitude_raw', dt.longitude_raw) ELSE '{}'::jsonb END ||
            CASE WHEN dt.altitude_raw IS NOT NULL AND l.altitude_error_msg IS NOT NULL THEN jsonb_build_object('altitude_raw', dt.altitude_raw) ELSE '{}'::jsonb END
        $$, v_default_country_id, v_address_present_condition_sql);

        -- Coordinate error expressions for physical location
        v_coord_cast_error_json_expr_sql := $$
            jsonb_strip_nulls(
                jsonb_build_object('latitude_raw', l.latitude_error_msg) ||
                jsonb_build_object('longitude_raw', l.longitude_error_msg) ||
                jsonb_build_object('altitude_raw', l.altitude_error_msg)
            )
        $$;
        v_coord_range_error_json_expr_sql := $jsonb_expr$
            jsonb_strip_nulls(
                jsonb_build_object('latitude_raw', CASE WHEN l.resolved_typed_latitude IS NOT NULL AND (l.resolved_typed_latitude < -90 OR l.resolved_typed_latitude > 90) THEN format($$Value %1$s out of range. Expected -90 to 90.$$, l.resolved_typed_latitude::TEXT /* %1$s */) ELSE NULL END) ||
                jsonb_build_object('longitude_raw', CASE WHEN l.resolved_typed_longitude IS NOT NULL AND (l.resolved_typed_longitude < -180 OR l.resolved_typed_longitude > 180) THEN format($$Value %1$s out of range. Expected -180 to 180.$$, l.resolved_typed_longitude::TEXT /* %1$s */) ELSE NULL END) ||
                jsonb_build_object('altitude_raw', CASE WHEN l.resolved_typed_altitude IS NOT NULL AND l.resolved_typed_altitude < 0 THEN format($$Value %1$s cannot be negative. Expected >= 0.$$, l.resolved_typed_altitude::TEXT /* %1$s */) ELSE NULL END)
            )
        $jsonb_expr$;
        v_coord_invalid_value_json_expr_sql := $$
            jsonb_strip_nulls(
                jsonb_build_object('latitude_raw', CASE WHEN (dt.latitude_raw IS NOT NULL AND l.latitude_error_msg IS NOT NULL) OR (l.resolved_typed_latitude IS NOT NULL AND (l.resolved_typed_latitude < -90 OR l.resolved_typed_latitude > 90)) THEN dt.latitude_raw ELSE NULL END) ||
                jsonb_build_object('longitude_raw', CASE WHEN (dt.longitude_raw IS NOT NULL AND l.longitude_error_msg IS NOT NULL) OR (l.resolved_typed_longitude IS NOT NULL AND (l.resolved_typed_longitude < -180 OR l.resolved_typed_longitude > 180)) THEN dt.longitude_raw ELSE NULL END) ||
                jsonb_build_object('altitude_raw', CASE WHEN (dt.altitude_raw IS NOT NULL AND l.altitude_error_msg IS NOT NULL) OR (l.resolved_typed_altitude IS NOT NULL AND l.resolved_typed_altitude < 0) THEN dt.altitude_raw ELSE NULL END)
            )
        $$;
        v_any_coord_error_condition_sql := $$
            (l.latitude_error_msg IS NOT NULL) OR (l.resolved_typed_latitude IS NOT NULL AND (l.resolved_typed_latitude < -90 OR l.resolved_typed_latitude > 90)) OR
            (l.longitude_error_msg IS NOT NULL) OR (l.resolved_typed_longitude IS NOT NULL AND (l.resolved_typed_longitude < -180 OR l.resolved_typed_longitude > 180)) OR
            (l.altitude_error_msg IS NOT NULL) OR (l.resolved_typed_altitude IS NOT NULL AND l.resolved_typed_altitude < 0)
        $$;

    ELSIF p_step_code = 'postal_location' THEN
        v_error_keys_to_clear_arr := ARRAY[
            'postal_region_code_raw',
            'postal_country_iso_2_raw'
        ];
        v_warning_keys_to_clear_arr := ARRAY['postal_region_code_raw', 'postal_country_iso_2_raw'];
        v_address_present_condition_sql := $$
            (NULLIF(dt.postal_address_part1_raw, '') IS NOT NULL OR NULLIF(dt.postal_address_part2_raw, '') IS NOT NULL OR NULLIF(dt.postal_address_part3_raw, '') IS NOT NULL OR
             NULLIF(dt.postal_postcode_raw, '') IS NOT NULL OR NULLIF(dt.postal_postplace_raw, '') IS NOT NULL OR NULLIF(dt.postal_region_code_raw, '') IS NOT NULL)
        $$;
        v_fatal_error_condition_sql := format($$(
            (%2$s AND NULLIF(dt.postal_country_iso_2_raw, '') IS NOT NULL AND l.resolved_postal_country_id IS NULL)
            OR
            (dt.postal_region_code_raw IS NOT NULL AND l.resolved_postal_country_id IS NOT NULL AND l.resolved_postal_country_id IS DISTINCT FROM %1$L)
        )$$, v_default_country_id, v_address_present_condition_sql);
        v_fatal_error_json_expr_sql := format($$
            jsonb_strip_nulls(jsonb_build_object(
                'postal_country_iso_2_raw',
                CASE WHEN (%2$s AND NULLIF(dt.postal_country_iso_2_raw, '') IS NOT NULL AND l.resolved_postal_country_id IS NULL)
                     THEN 'Country is required and must be valid when other postal address details are provided.'
                     ELSE NULL END,
                'postal_region_code_raw',
                CASE WHEN (dt.postal_region_code_raw IS NOT NULL AND l.resolved_postal_country_id IS NOT NULL AND l.resolved_postal_country_id IS DISTINCT FROM %1$L)
                     THEN 'Region can only be supplied for the domestic country.'
                     ELSE NULL END
            ))
        $$, v_default_country_id, v_address_present_condition_sql);
        v_error_condition_sql := format($$
            -- Invalid region codes for any country (both domestic and foreign)
            (dt.postal_region_code_raw IS NOT NULL AND l.resolved_postal_region_id IS NULL) OR
            -- NOTE: postal does NOT emit a domestic-NULL-region warning. Region is not required
            -- for postal addresses; absence is a principled state, not missing data.
            -- NOTE: postal does NOT emit a country-defaulted warning either. For a postal address,
            -- "no country" naturally means "domestic" — the default IS the principled valid state,
            -- not missingness. With country defaulting silent (per unified principle) and no
            -- domestic-NULL-region warning, postal stays fully silent for region/country handling.
            -- Invalid country code without address (no-address case, otherwise fatal handles it).
            (dt.postal_country_iso_2_raw IS NOT NULL AND l.resolved_postal_country_id IS NULL AND NOT (%2$s))
        $$, v_default_country_id, v_address_present_condition_sql);

        v_warnings_json_expr_sql := format($$
            CASE
                WHEN dt.postal_region_code_raw IS NOT NULL AND l.resolved_postal_region_id IS NULL THEN jsonb_build_object('postal_region_code_raw', dt.postal_region_code_raw)  -- Invalid region code
                -- NOTE: no domestic-NULL-region warning for postal; absence is principled.
                ELSE '{}'::jsonb
            END ||
            -- NOTE: no country-defaulted warning emission for postal either. The WRITE still
            -- defaults to settings.country_id via v_postal_country_id_expr; the defaulting
            -- is silent because absent-country-on-postal IS the principled valid state.
            CASE WHEN dt.postal_country_iso_2_raw IS NOT NULL AND l.resolved_postal_country_id IS NULL THEN jsonb_build_object('postal_country_iso_2_raw', dt.postal_country_iso_2_raw) ELSE '{}'::jsonb END
        $$, v_default_country_id, v_address_present_condition_sql);

        -- A postal address carries no position (public.location's
        -- postal_locations_cannot_have_coordinates): the postal step takes no
        -- coordinate columns, so it has no coordinate errors.
        v_coord_cast_error_json_expr_sql := $$'{}'::jsonb$$;
        v_coord_range_error_json_expr_sql := $$'{}'::jsonb$$;
        v_coord_invalid_value_json_expr_sql := $$'{}'::jsonb$$;
        v_any_coord_error_condition_sql := $$false$$;

    ELSE
        RAISE EXCEPTION '[Job %] analyse_location: Invalid p_step_code provided: %. Expected ''physical_location'' or ''postal_location''.', p_job_id, p_step_code;
    END IF;

    -- Step 1: Materialize the batch data into a temp table for performance.
    IF to_regclass('pg_temp.t_batch_data') IS NOT NULL THEN DROP TABLE t_batch_data; END IF;
    v_sql := format($$
        CREATE TEMP TABLE t_batch_data ON COMMIT DROP AS
        SELECT
            dt.row_id,
            dt.physical_region_code_raw, dt.physical_country_iso_2_raw,
            dt.postal_region_code_raw, dt.postal_country_iso_2_raw,
            dt.latitude_raw, dt.longitude_raw, dt.altitude_raw
        FROM %I dt
        WHERE dt.batch_seq = $1
          AND dt.action IS DISTINCT FROM 'skip';
    $$, v_data_table_name);
    EXECUTE v_sql USING p_batch_seq;

    ANALYZE t_batch_data;

    -- Step 2: Resolve all distinct codes and numerics from the batch in separate temp tables.
    IF to_regclass('pg_temp.t_resolved_codes') IS NOT NULL THEN DROP TABLE t_resolved_codes; END IF;
    CREATE TEMP TABLE t_resolved_codes ON COMMIT DROP AS
    WITH distinct_codes AS (
        SELECT physical_region_code_raw AS code, 'region' AS type FROM t_batch_data WHERE NULLIF(physical_region_code_raw, '') IS NOT NULL
        UNION SELECT physical_country_iso_2_raw AS code, 'country' AS type FROM t_batch_data WHERE NULLIF(physical_country_iso_2_raw, '') IS NOT NULL
        UNION SELECT postal_region_code_raw AS code, 'region' AS type FROM t_batch_data WHERE NULLIF(postal_region_code_raw, '') IS NOT NULL
        UNION SELECT postal_country_iso_2_raw AS code, 'country' AS type FROM t_batch_data WHERE NULLIF(postal_country_iso_2_raw, '') IS NOT NULL
    )
    SELECT dc.code, dc.type, COALESCE(r.id, c.id) as resolved_id
    FROM distinct_codes dc
    LEFT JOIN public.region r ON dc.type = 'region' AND dc.code = r.code
    LEFT JOIN public.country c ON dc.type = 'country' AND dc.code = c.iso_2;

    IF to_regclass('pg_temp.t_resolved_numerics') IS NOT NULL THEN DROP TABLE t_resolved_numerics; END IF;
    CREATE TEMP TABLE t_resolved_numerics ON COMMIT DROP AS
    WITH distinct_numerics AS (
        SELECT latitude_raw AS num_string, 'NUMERIC(9,6)' AS num_type FROM t_batch_data WHERE NULLIF(latitude_raw, '') IS NOT NULL
        UNION SELECT longitude_raw AS num_string, 'NUMERIC(9,6)' AS num_type FROM t_batch_data WHERE NULLIF(longitude_raw, '') IS NOT NULL
        UNION SELECT altitude_raw AS num_string, 'NUMERIC(6,1)' AS num_type FROM t_batch_data WHERE NULLIF(altitude_raw, '') IS NOT NULL
    )
    SELECT
        dn.num_string, dn.num_type,
        cast_result.p_value, cast_result.p_error_message
    FROM distinct_numerics dn
    LEFT JOIN LATERAL import.try_cast_to_numeric_specific(dn.num_string, dn.num_type) AS cast_result ON TRUE;

    ANALYZE t_resolved_codes;
    ANALYZE t_resolved_numerics;

    v_sql := format($SQL$
        WITH
        lookups AS (
            SELECT
                bd.row_id AS data_row_id,
                -- Enhanced region resolution: always look for region by code, but validate context later
                (SELECT r.id FROM public.region r WHERE r.code = bd.physical_region_code_raw AND r.version_id = (SELECT region_version_id FROM public.settings LIMIT 1)) as resolved_physical_region_id,
                phys_c.resolved_id as resolved_physical_country_id,
                -- Enhanced region resolution: always look for region by code, but validate context later
                (SELECT r.id FROM public.region r WHERE r.code = bd.postal_region_code_raw AND r.version_id = (SELECT region_version_id FROM public.settings LIMIT 1)) as resolved_postal_region_id,
                post_c.resolved_id as resolved_postal_country_id,
                phys_lat.p_value as resolved_typed_latitude,
                phys_lat.p_error_message as latitude_error_msg,
                phys_lon.p_value as resolved_typed_longitude,
                phys_lon.p_error_message as longitude_error_msg,
                phys_alt.p_value as resolved_typed_altitude,
                phys_alt.p_error_message as altitude_error_msg
            FROM t_batch_data bd
            LEFT JOIN t_resolved_codes phys_c ON bd.physical_country_iso_2_raw = phys_c.code AND phys_c.type = 'country'
            LEFT JOIN t_resolved_codes post_c ON bd.postal_country_iso_2_raw = post_c.code AND post_c.type = 'country'
            LEFT JOIN t_resolved_numerics phys_lat ON bd.latitude_raw = phys_lat.num_string AND phys_lat.num_type = 'NUMERIC(9,6)'
            LEFT JOIN t_resolved_numerics phys_lon ON bd.longitude_raw = phys_lon.num_string AND phys_lon.num_type = 'NUMERIC(9,6)'
            LEFT JOIN t_resolved_numerics phys_alt ON bd.altitude_raw = phys_alt.num_string AND phys_alt.num_type = 'NUMERIC(6,1)'
        )
        UPDATE public.%1$I dt SET
            physical_address_part1 = NULLIF(dt.physical_address_part1_raw, ''),
            physical_address_part2 = NULLIF(dt.physical_address_part2_raw, ''),
            physical_address_part3 = NULLIF(dt.physical_address_part3_raw, ''),
            physical_postcode = NULLIF(dt.physical_postcode_raw, ''),
            physical_postplace = NULLIF(dt.physical_postplace_raw, ''),
            physical_region_id = l.resolved_physical_region_id,
            physical_country_id = %15$s,
            latitude = l.resolved_typed_latitude,
            longitude = l.resolved_typed_longitude,
            altitude = l.resolved_typed_altitude,
            postal_address_part1 = NULLIF(dt.postal_address_part1_raw, ''),
            postal_address_part2 = NULLIF(dt.postal_address_part2_raw, ''),
            postal_address_part3 = NULLIF(dt.postal_address_part3_raw, ''),
            postal_postcode = NULLIF(dt.postal_postcode_raw, ''),
            postal_postplace = NULLIF(dt.postal_postplace_raw, ''),
            postal_region_id = l.resolved_postal_region_id,
            postal_country_id = %16$s,
            action = CASE
                        WHEN (%6$s) OR (%10$s) THEN 'skip'::public.import_row_action_type -- Fatal error: set action to skip
                        ELSE dt.action -- Preserve existing action otherwise
                     END,
            state = CASE
                        WHEN (%6$s) OR (%10$s) THEN 'error'::public.import_data_state -- Fatal country error OR any coordinate error
                        ELSE 'analysing'::public.import_data_state
                    END,
            errors = jsonb_strip_nulls(
                        (dt.errors - %3$L::text[]) -- Start with existing errors, clearing old ones for this step
                        || CASE WHEN (%6$s) THEN (%7$s) ELSE '{}'::jsonb END -- Add Fatal country/region error message
                        || (%11$s) -- Add Coordinate cast error messages
                        || (%12$s) -- Add Coordinate range error messages
                        || (%13$s) -- Add Postal coordinate present error message
                    ),
            warnings = (
                        (dt.warnings - %8$L::text[]) -- Start with existing warnings, clearing old ones for this step
                        || CASE WHEN (%4$s) AND NOT ((%6$s) OR (%10$s)) THEN (%5$s) ELSE '{}'::jsonb END -- Add Non-fatal region/country codes (if no fatal/coord error)
                        || CASE WHEN (%10$s) THEN jsonb_strip_nulls(%14$s) ELSE '{}'::jsonb END -- Add Original invalid coordinate values (strip nulls here)
                    ),
            last_completed_priority = %9$L::INTEGER -- Always v_step.priority
        FROM lookups l
        WHERE dt.row_id = l.data_row_id;
    $SQL$,
        v_data_table_name,                          /* %1$I (target table) */
        v_default_country_id,                       /* %2$L (default country for region resolution) */
        v_error_keys_to_clear_arr,                  /* %3$L (for clearing error keys) */
        v_error_condition_sql,                      /* %4$s (non-fatal region/country error condition) */
        v_warnings_json_expr_sql,                   /* %5$s (for adding non-fatal region/country warnings) */
        v_fatal_error_condition_sql,                /* %6$s (fatal country/region error condition) */
        v_fatal_error_json_expr_sql,                /* %7$s (for adding fatal country/region error message) */
        v_warning_keys_to_clear_arr,                /* %8$L (for clearing warnings keys) */
        v_step.priority,                            /* %9$L (for last_completed_priority) */
        v_any_coord_error_condition_sql,            /* %10$s (any coordinate error condition) */
        v_coord_cast_error_json_expr_sql,           /* %11$s (coordinate cast error JSON) */
        v_coord_range_error_json_expr_sql,          /* %12$s (coordinate range error JSON) */
        v_postal_coord_present_error_json_expr_sql, /* %13$s (postal has coords error JSON) */
        v_coord_invalid_value_json_expr_sql,        /* %14$s (original invalid coordinate values JSON) */
        v_physical_country_id_expr,                 /* %15$s (physical_country_id with default fallback) */
        v_postal_country_id_expr                    /* %16$s (postal_country_id with default fallback) */
    );

    RAISE DEBUG '[Job %] analyse_location: Single-pass batch update for non-skipped rows for step %: %', p_job_id, p_step_code, v_sql;

    BEGIN
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_location: Updated % non-skipped rows in single pass for step %.', p_job_id, v_update_count, p_step_code;

        -- Unconditionally advance priority for all rows in batch to ensure progress
        v_sql := format($$
            UPDATE public.%1$I dt SET
                last_completed_priority = %2$L
            WHERE dt.batch_seq = $1 AND dt.last_completed_priority < %2$L;
        $$, v_data_table_name /* %1$I */, v_step.priority /* %2$L */);
        RAISE DEBUG '[Job %] analyse_location: Unconditionally advancing priority for all batch rows with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql USING p_batch_seq;
        GET DIAGNOSTICS v_skipped_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_location: Advanced last_completed_priority for % total rows in batch for step %.', p_job_id, v_skipped_update_count, p_step_code;

        v_sql := format($$SELECT COUNT(*) FROM public.%1$I dt WHERE dt.batch_seq = $1 AND dt.state = 'error' AND (dt.errors ?| %2$L::text[])$$,
                       v_data_table_name /* %1$I */, v_error_keys_to_clear_arr /* %2$L */);
        RAISE DEBUG '[Job %] analyse_location: Counting errors with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql
        INTO v_error_count
        USING p_batch_seq;
        RAISE DEBUG '[Job %] analyse_location: Estimated errors in this step for batch: %', p_job_id, v_error_count;

    EXCEPTION
        WHEN PROGRAM_LIMIT_EXCEEDED THEN -- e.g. statement too complex, or other similar limit errors
            error_message := SQLERRM;
            RAISE WARNING '[Job %] analyse_location: Program limit exceeded during single-pass batch update for step %: %. SQLSTATE: %', p_job_id, p_step_code, error_message, SQLSTATE;
            -- Fallback or simplified error marking might be needed here if the main query is too complex
            UPDATE public.import_job
            SET error = jsonb_build_object('analyse_location_error', format($$Program limit error for step %1$s: %2$s$$, p_step_code /* %1$s */, error_message /* %2$s */))::TEXT,
                state = 'failed'
            WHERE id = p_job_id;
            -- Don't re-throw - job is marked as failed
        WHEN OTHERS THEN
            error_message := SQLERRM;
            RAISE WARNING '[Job %] analyse_location: Unexpected error during single-pass batch update for step %: %. SQLSTATE: %', p_job_id, p_step_code, error_message, SQLSTATE;
            -- Attempt to mark individual data rows as error (best effort)
            BEGIN
                v_sql := format($$
                    UPDATE public.%1$I dt SET
                        state = %2$L,
                        errors = dt.errors || jsonb_build_object('location_batch_error', 'Unexpected error during update for step %3$s: ' || %4$L),
                        last_completed_priority = dt.last_completed_priority -- Do not advance priority on unexpected error, use existing LCP
                    WHERE dt.batch_seq = $1;
                $$, v_data_table_name /* %1$I */, 'error'::public.import_data_state /* %2$L */, p_step_code /* %3$s */, error_message /* %4$L */);
                RAISE DEBUG '[Job %] analyse_location: Marking rows as error in exception handler with SQL: %', p_job_id, v_sql;
                EXECUTE v_sql USING p_batch_seq;
            EXCEPTION WHEN OTHERS THEN
                RAISE WARNING '[Job %] analyse_location: Could not mark individual data rows as error after unexpected error: %', p_job_id, SQLERRM;
            END;
            -- Mark the job as failed
            UPDATE public.import_job
            SET error = jsonb_build_object('analyse_location_error', format($SQL$Unexpected error for step %1$s: %2$s$SQL$, p_step_code /* %1$s */, error_message /* %2$s */))::TEXT,
                state = 'failed'
            WHERE id = p_job_id;
            RAISE DEBUG '[Job %] analyse_location: Marked job as failed due to unexpected error for step %: %', p_job_id, p_step_code, error_message;
            -- Don't re-throw - job is marked as failed
    END;

    -- Propagate errors to all rows of a new entity if one fails (best-effort)
    BEGIN
        CALL import.propagate_fatal_error_to_entity_batch(p_job_id, v_data_table_name, p_batch_seq, v_error_keys_to_clear_arr, p_step_code);
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '[Job %] analyse_location: Non-fatal error during error propagation: %', p_job_id, SQLERRM;
    END;

    RAISE DEBUG '[Job %] analyse_location (Batch): Finished analysis for batch for step %. Errors newly marked in this step: %', p_job_id, p_step_code, v_error_count;
END;
$procedure$
;

CREATE OR REPLACE PROCEDURE import.process_location(IN p_job_id integer, IN p_batch_seq integer, IN p_step_code text)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_job public.import_job;
    v_definition public.import_definition;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_sql TEXT;
    v_error_count INT := 0;
    v_update_count INT := 0;
    error_message TEXT;
    v_job_mode public.import_mode;
    v_select_lu_id_expr TEXT;
    v_select_est_id_expr TEXT;
    v_source_view_name TEXT;
    v_relevant_rows_count INT;
    v_merge_mode sql_saga.temporal_merge_mode;
BEGIN
    RAISE DEBUG '[Job %] process_location (Batch) for step_code %: Starting operation for batch_seq %', p_job_id, p_step_code, p_batch_seq;

    -- Get job details
    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    SELECT * INTO v_definition FROM jsonb_populate_record(NULL::public.import_definition, v_job.definition_snapshot->'import_definition');
    IF v_definition IS NULL THEN RAISE EXCEPTION '[Job %] Failed to load import_definition from snapshot', p_job_id; END IF;

    -- Get step details
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = p_step_code;
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] process_location: Step with code % not found in snapshot.', p_job_id, p_step_code; END IF;

    v_job_mode := v_definition.mode;

    -- Select the correct parent unit ID column based on job mode, or NULL if not applicable.
    IF v_job_mode = 'legal_unit' THEN
        v_select_lu_id_expr := 'dt.legal_unit_id';
        v_select_est_id_expr := 'NULL::INTEGER';
    ELSIF v_job_mode = 'establishment_formal' THEN
        v_select_lu_id_expr := 'NULL::INTEGER';
        v_select_est_id_expr := 'dt.establishment_id';
    ELSIF v_job_mode = 'establishment_informal' THEN
        v_select_lu_id_expr := 'NULL::INTEGER';
        v_select_est_id_expr := 'dt.establishment_id';
    ELSE
        RAISE EXCEPTION '[Job %] process_location: Unhandled job mode % for unit ID selection.', p_job_id, v_job_mode;
    END IF;

    -- Create an updatable view over the relevant data for this step
    v_source_view_name := 'temp_loc_source_view_' || p_step_code;
    IF p_step_code = 'physical_location' THEN
        v_sql := format($$
            CREATE OR REPLACE TEMP VIEW %1$I AS
            SELECT
                dt.row_id,
                dt.founding_row_id,
                dt.physical_location_id AS id,
                %2$s AS legal_unit_id,
                %3$s AS establishment_id,
                'physical'::public.location_type AS type,
                dt.valid_from,
                dt.valid_to,
                dt.valid_until,
                dt.physical_address_part1 AS address_part1, dt.physical_address_part2 AS address_part2, dt.physical_address_part3 AS address_part3,
                dt.physical_postcode AS postcode, dt.physical_postplace AS postplace,
                dt.physical_region_id AS region_id, (SELECT r.version_id FROM public.region r WHERE r.id = dt.physical_region_id) AS region_version_id, dt.physical_country_id AS country_id,
                dt.latitude, dt.longitude, dt.altitude,
                dt.data_source_id,
                dt.edit_by_user_id, dt.edit_at, dt.edit_comment,
                dt.errors, dt.merge_status
            FROM public.%4$I dt
            WHERE dt.batch_seq = %5$L
              AND dt.action = 'use'
              AND dt.physical_country_id IS NOT NULL
              AND (NULLIF(dt.physical_region_code_raw, '') IS NOT NULL OR NULLIF(dt.physical_country_iso_2_raw, '') IS NOT NULL OR NULLIF(dt.physical_address_part1_raw, '') IS NOT NULL OR NULLIF(dt.physical_postcode_raw, '') IS NOT NULL);
        $$,
            v_source_view_name,    /* %1$I */
            v_select_lu_id_expr,   /* %2$s */
            v_select_est_id_expr,  /* %3$s */
            v_data_table_name,     /* %4$I */
            p_batch_seq            /* %5$L */
        );

    ELSIF p_step_code = 'postal_location' THEN
        v_sql := format($$
            CREATE OR REPLACE TEMP VIEW %1$I AS
            SELECT
                dt.row_id,
                dt.founding_row_id,
                dt.postal_location_id AS id,
                %2$s AS legal_unit_id,
                %3$s AS establishment_id,
                'postal'::public.location_type AS type,
                dt.valid_from,
                dt.valid_to,
                dt.valid_until,
                dt.postal_address_part1 AS address_part1, dt.postal_address_part2 AS address_part2, dt.postal_address_part3 AS address_part3,
                dt.postal_postcode AS postcode, dt.postal_postplace AS postplace,
                dt.postal_region_id AS region_id, (SELECT r.version_id FROM public.region r WHERE r.id = dt.postal_region_id) AS region_version_id, dt.postal_country_id AS country_id,
                NULL::numeric(9,6) AS latitude, NULL::numeric(9,6) AS longitude, NULL::numeric(6,1) AS altitude, -- a postal address has no position
                dt.data_source_id,
                dt.edit_by_user_id, dt.edit_at, dt.edit_comment,
                dt.errors, dt.merge_status
            FROM public.%4$I dt
            WHERE dt.batch_seq = %5$L
              AND dt.action = 'use'
              AND dt.postal_country_id IS NOT NULL
              AND (NULLIF(dt.postal_region_code_raw, '') IS NOT NULL OR NULLIF(dt.postal_country_iso_2_raw, '') IS NOT NULL OR NULLIF(dt.postal_address_part1_raw, '') IS NOT NULL OR NULLIF(dt.postal_postcode_raw, '') IS NOT NULL);
        $$,
            v_source_view_name,    /* %1$I */
            v_select_lu_id_expr,   /* %2$s */
            v_select_est_id_expr,  /* %3$s */
            v_data_table_name,     /* %4$I */
            p_batch_seq            /* %5$L */
        );
    ELSE
        RAISE EXCEPTION '[Job %] process_location: Invalid step_code %.', p_job_id, p_step_code;
    END IF;

    RAISE DEBUG '[Job %] process_location: Creating temp source view %s with SQL: %', p_job_id, v_source_view_name, v_sql;
    EXECUTE v_sql;

    v_sql := format('SELECT count(*) FROM %I', v_source_view_name);
    RAISE DEBUG '[Job %] process_location: Counting relevant rows with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql INTO v_relevant_rows_count;
    IF v_relevant_rows_count = 0 THEN
        RAISE DEBUG '[Job %] process_location: No usable location data in this batch for step %. Skipping.', p_job_id, p_step_code;
        RETURN;
    END IF;

    RAISE DEBUG '[Job %] process_location: Calling sql_saga.temporal_merge for % rows (step: %).', p_job_id, v_relevant_rows_count, p_step_code;

    BEGIN
        -- Determine merge mode from job strategy
        v_merge_mode := CASE v_definition.strategy
            WHEN 'insert_or_replace' THEN 'MERGE_ENTITY_REPLACE'::sql_saga.temporal_merge_mode
            WHEN 'replace_only' THEN 'REPLACE_FOR_PORTION_OF'::sql_saga.temporal_merge_mode
            WHEN 'insert_or_update' THEN 'MERGE_ENTITY_PATCH'::sql_saga.temporal_merge_mode
            WHEN 'update_only' THEN 'UPDATE_FOR_PORTION_OF'::sql_saga.temporal_merge_mode
            ELSE 'MERGE_ENTITY_PATCH'::sql_saga.temporal_merge_mode -- Default to safer patch for other cases
        END;
        RAISE DEBUG '[Job %] process_location: Determined merge mode % from strategy %', p_job_id, v_merge_mode, v_definition.strategy;

        CALL sql_saga.temporal_merge(
            target_table => 'public.location'::regclass,
            source_table => v_source_view_name::regclass,
            primary_identity_columns => ARRAY['id'],
            natural_identity_columns => ARRAY['legal_unit_id', 'establishment_id', 'type'],
            mode => v_merge_mode,
            row_id_column => 'row_id',
            founding_id_column => 'founding_row_id',
            update_source_with_identity => true,
            update_source_with_feedback => true,
            feedback_status_column => 'merge_status',
            feedback_status_key => p_step_code,
            feedback_error_column => 'errors',
            feedback_error_key => p_step_code
        );

        v_sql := format($$ SELECT count(*) FROM public.%1$I dt WHERE dt.batch_seq = $1 AND dt.errors->%2$L IS NOT NULL $$,
            v_data_table_name, /* %1$I */
            p_step_code        /* %2$L */
        );
        RAISE DEBUG '[Job %] process_location: Counting merge errors with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql INTO v_error_count USING p_batch_seq;

        v_sql := format($$
            UPDATE public.%1$I dt SET
                state = (CASE WHEN dt.errors ? %3$L THEN 'error' ELSE 'processing' END)::public.import_data_state
            FROM %2$I v
            WHERE dt.row_id = v.row_id;
        $$,
            v_data_table_name,  /* %1$I */
            v_source_view_name, /* %2$I */
            p_step_code         /* %3$L */
        );
        RAISE DEBUG '[Job %] process_location: Updating state post-merge with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        v_update_count := v_update_count - v_error_count;

        RAISE DEBUG '[Job %] process_location: Merge finished for step %. Success: %, Errors: %', p_job_id, p_step_code, v_update_count, v_error_count;

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_location: Error during temporal_merge for step %: %. SQLSTATE: %', p_job_id, p_step_code, error_message, SQLSTATE;
        v_sql := format($$UPDATE public.%1$I dt SET state = 'error'::public.import_data_state, errors = errors || jsonb_build_object('batch_error_process_location', %2$L) WHERE dt.batch_seq = $1$$,
                        v_data_table_name, /* %1$I */
                        error_message      /* %2$L */
        );
        RAISE DEBUG '[Job %] process_location: Marking rows as error in exception handler with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql USING p_batch_seq;
        RAISE; -- Re-throw
    END;

    RAISE DEBUG '[Job %] process_location (Batch): Finished for step %. Total Processed: %, Errors: %',
        p_job_id, p_step_code, v_update_count + v_error_count, v_error_count;
END;
$procedure$
;

CREATE OR REPLACE FUNCTION import.get_statistical_unit_data_partial(p_unit_type statistical_unit_type, p_id_ranges int4multirange)
 RETURNS SETOF statistical_unit
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    v_ids INT[] := public.int4multirange_to_array(p_id_ranges);
BEGIN
    IF p_unit_type = 'establishment' THEN
        RETURN QUERY
        SELECT t.unit_type, t.unit_id, t.valid_from, t.valid_to, t.valid_until,
            COALESCE(eia1.external_idents, '{}'::jsonb) AS external_idents,
            t.name, t.birth_date, t.death_date, t.search,
            t.primary_activity_category_id, t.primary_activity_category_path, t.primary_activity_category_code,
            t.secondary_activity_category_id, t.secondary_activity_category_path, t.secondary_activity_category_code,
            t.activity_category_paths, t.sector_id, t.sector_path, t.sector_code, t.sector_name,
            t.data_source_ids, t.data_source_codes, t.legal_form_id, t.legal_form_code, t.legal_form_name,
            t.physical_address_part1, t.physical_address_part2, t.physical_address_part3, t.physical_postcode, t.physical_postplace,
            t.physical_region_id, t.physical_region_path, t.physical_region_code, t.physical_country_id, t.physical_country_iso_2,
            t.latitude, t.longitude, t.altitude, t.domestic,
            t.postal_address_part1, t.postal_address_part2, t.postal_address_part3, t.postal_postcode, t.postal_postplace,
            t.postal_region_id, t.postal_region_path, t.postal_region_code, t.postal_country_id, t.postal_country_iso_2,
            t.web_address, t.email_address, t.phone_number, t.landline, t.mobile_number, t.fax_number,
            t.unit_size_id, t.unit_size_code, t.status_id, t.status_code, t.used_for_counting,
            t.last_edit_comment, t.last_edit_by_user_id, t.last_edit_at, t.has_legal_unit,
            t.related_establishment_ids, t.excluded_establishment_ids, t.included_establishment_ids,
            t.related_legal_unit_ids, t.excluded_legal_unit_ids, t.included_legal_unit_ids,
            t.related_enterprise_ids, t.excluded_enterprise_ids, t.included_enterprise_ids,
            t.stats, t.stats_summary,
            array_length(t.included_establishment_ids, 1) AS included_establishment_count,
            array_length(t.included_legal_unit_ids, 1) AS included_legal_unit_count,
            array_length(t.included_enterprise_ids, 1) AS included_enterprise_count,
            COALESCE(tpa.tag_paths, ARRAY[]::public.ltree[]) AS tag_paths,
            daterange(t.valid_from, t.valid_until) AS valid_range,
            public.hash_slot(t.unit_type, t.unit_id) AS hash_slot
        FROM public.timeline_establishment t
        LEFT JOIN LATERAL (SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents FROM public.external_ident ei JOIN public.external_ident_type eit ON ei.type_id = eit.id WHERE ei.establishment_id = t.unit_id) eia1 ON true
        LEFT JOIN LATERAL (SELECT array_agg(tag.path ORDER BY tag.path) AS tag_paths FROM public.tag_for_unit tfu JOIN public.tag ON tfu.tag_id = tag.id WHERE tfu.establishment_id = t.unit_id) tpa ON true
        WHERE t.unit_id = ANY(v_ids);

    ELSIF p_unit_type = 'legal_unit' THEN
        RETURN QUERY
        SELECT t.unit_type, t.unit_id, t.valid_from, t.valid_to, t.valid_until,
            COALESCE(eia1.external_idents, '{}'::jsonb) AS external_idents,
            t.name, t.birth_date, t.death_date, t.search,
            t.primary_activity_category_id, t.primary_activity_category_path, t.primary_activity_category_code,
            t.secondary_activity_category_id, t.secondary_activity_category_path, t.secondary_activity_category_code,
            t.activity_category_paths, t.sector_id, t.sector_path, t.sector_code, t.sector_name,
            t.data_source_ids, t.data_source_codes, t.legal_form_id, t.legal_form_code, t.legal_form_name,
            t.physical_address_part1, t.physical_address_part2, t.physical_address_part3, t.physical_postcode, t.physical_postplace,
            t.physical_region_id, t.physical_region_path, t.physical_region_code, t.physical_country_id, t.physical_country_iso_2,
            t.latitude, t.longitude, t.altitude, t.domestic,
            t.postal_address_part1, t.postal_address_part2, t.postal_address_part3, t.postal_postcode, t.postal_postplace,
            t.postal_region_id, t.postal_region_path, t.postal_region_code, t.postal_country_id, t.postal_country_iso_2,
            t.web_address, t.email_address, t.phone_number, t.landline, t.mobile_number, t.fax_number,
            t.unit_size_id, t.unit_size_code, t.status_id, t.status_code, t.used_for_counting,
            t.last_edit_comment, t.last_edit_by_user_id, t.last_edit_at, t.has_legal_unit,
            t.related_establishment_ids, t.excluded_establishment_ids, t.included_establishment_ids,
            t.related_legal_unit_ids, t.excluded_legal_unit_ids, t.included_legal_unit_ids,
            t.related_enterprise_ids, t.excluded_enterprise_ids, t.included_enterprise_ids,
            t.stats, t.stats_summary,
            array_length(t.included_establishment_ids, 1) AS included_establishment_count,
            array_length(t.included_legal_unit_ids, 1) AS included_legal_unit_count,
            array_length(t.included_enterprise_ids, 1) AS included_enterprise_count,
            COALESCE(tpa.tag_paths, ARRAY[]::public.ltree[]) AS tag_paths,
            daterange(t.valid_from, t.valid_until) AS valid_range,
            public.hash_slot(t.unit_type, t.unit_id) AS hash_slot
        FROM public.timeline_legal_unit t
        LEFT JOIN LATERAL (SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents FROM public.external_ident ei JOIN public.external_ident_type eit ON ei.type_id = eit.id WHERE ei.legal_unit_id = t.unit_id) eia1 ON true
        LEFT JOIN LATERAL (SELECT array_agg(tag.path ORDER BY tag.path) AS tag_paths FROM public.tag_for_unit tfu JOIN public.tag ON tfu.tag_id = tag.id WHERE tfu.legal_unit_id = t.unit_id) tpa ON true
        WHERE t.unit_id = ANY(v_ids);

    ELSIF p_unit_type = 'enterprise' THEN
        RETURN QUERY
        SELECT t.unit_type, t.unit_id, t.valid_from, t.valid_to, t.valid_until,
            COALESCE(eia1.external_idents, eia2.external_idents, eia3.external_idents, '{}'::jsonb) AS external_idents,
            t.name::varchar, t.birth_date, t.death_date, t.search,
            t.primary_activity_category_id, t.primary_activity_category_path, t.primary_activity_category_code,
            t.secondary_activity_category_id, t.secondary_activity_category_path, t.secondary_activity_category_code,
            t.activity_category_paths, t.sector_id, t.sector_path, t.sector_code, t.sector_name,
            t.data_source_ids, t.data_source_codes, t.legal_form_id, t.legal_form_code, t.legal_form_name,
            t.physical_address_part1, t.physical_address_part2, t.physical_address_part3, t.physical_postcode, t.physical_postplace,
            t.physical_region_id, t.physical_region_path, t.physical_region_code, t.physical_country_id, t.physical_country_iso_2,
            t.latitude, t.longitude, t.altitude, t.domestic,
            t.postal_address_part1, t.postal_address_part2, t.postal_address_part3, t.postal_postcode, t.postal_postplace,
            t.postal_region_id, t.postal_region_path, t.postal_region_code, t.postal_country_id, t.postal_country_iso_2,
            t.web_address, t.email_address, t.phone_number, t.landline, t.mobile_number, t.fax_number,
            t.unit_size_id, t.unit_size_code, t.status_id, t.status_code, t.used_for_counting,
            t.last_edit_comment, t.last_edit_by_user_id, t.last_edit_at, t.has_legal_unit,
            t.related_establishment_ids, t.excluded_establishment_ids, t.included_establishment_ids,
            t.related_legal_unit_ids, t.excluded_legal_unit_ids, t.included_legal_unit_ids,
            t.related_enterprise_ids, t.excluded_enterprise_ids, t.included_enterprise_ids,
            NULL::JSONB AS stats, t.stats_summary,
            array_length(t.included_establishment_ids, 1) AS included_establishment_count,
            array_length(t.included_legal_unit_ids, 1) AS included_legal_unit_count,
            array_length(t.included_enterprise_ids, 1) AS included_enterprise_count,
            COALESCE(tpa.tag_paths, ARRAY[]::public.ltree[]) AS tag_paths,
            daterange(t.valid_from, t.valid_until) AS valid_range,
            public.hash_slot(t.unit_type, t.unit_id) AS hash_slot
        FROM public.timeline_enterprise t
        LEFT JOIN LATERAL (SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents FROM public.external_ident ei JOIN public.external_ident_type eit ON ei.type_id = eit.id WHERE ei.enterprise_id = t.unit_id) eia1 ON true
        LEFT JOIN LATERAL (SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents FROM public.external_ident ei JOIN public.external_ident_type eit ON ei.type_id = eit.id WHERE ei.establishment_id = t.primary_establishment_id) eia2 ON true
        LEFT JOIN LATERAL (SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents FROM public.external_ident ei JOIN public.external_ident_type eit ON ei.type_id = eit.id WHERE ei.legal_unit_id = t.primary_legal_unit_id) eia3 ON true
        LEFT JOIN LATERAL (SELECT array_agg(tag.path ORDER BY tag.path) AS tag_paths FROM public.tag_for_unit tfu JOIN public.tag ON tfu.tag_id = tag.id WHERE tfu.enterprise_id = t.unit_id) tpa ON true
        WHERE t.unit_id = ANY(v_ids);

    ELSIF p_unit_type = 'power_group' THEN
        RETURN QUERY
        SELECT t.unit_type, t.unit_id, t.valid_from, t.valid_to, t.valid_until,
            COALESCE(eia1.external_idents, '{}'::jsonb) AS external_idents,
            t.name::varchar, t.birth_date, t.death_date, t.search,
            t.primary_activity_category_id, t.primary_activity_category_path, t.primary_activity_category_code,
            t.secondary_activity_category_id, t.secondary_activity_category_path, t.secondary_activity_category_code,
            t.activity_category_paths, t.sector_id, t.sector_path, t.sector_code, t.sector_name,
            t.data_source_ids, t.data_source_codes, t.legal_form_id, t.legal_form_code, t.legal_form_name,
            t.physical_address_part1, t.physical_address_part2, t.physical_address_part3, t.physical_postcode, t.physical_postplace,
            t.physical_region_id, t.physical_region_path, t.physical_region_code, t.physical_country_id, t.physical_country_iso_2,
            t.latitude, t.longitude, t.altitude, t.domestic,
            t.postal_address_part1, t.postal_address_part2, t.postal_address_part3, t.postal_postcode, t.postal_postplace,
            t.postal_region_id, t.postal_region_path, t.postal_region_code, t.postal_country_id, t.postal_country_iso_2,
            t.web_address, t.email_address, t.phone_number, t.landline, t.mobile_number, t.fax_number,
            t.unit_size_id, t.unit_size_code, t.status_id, t.status_code, t.used_for_counting,
            t.last_edit_comment, t.last_edit_by_user_id, t.last_edit_at, t.has_legal_unit,
            t.related_establishment_ids, t.excluded_establishment_ids, t.included_establishment_ids,
            t.related_legal_unit_ids, t.excluded_legal_unit_ids, t.included_legal_unit_ids,
            t.related_enterprise_ids, t.excluded_enterprise_ids, t.included_enterprise_ids,
            NULL::JSONB AS stats, t.stats_summary,
            array_length(t.included_establishment_ids, 1) AS included_establishment_count,
            array_length(t.included_legal_unit_ids, 1) AS included_legal_unit_count,
            array_length(t.included_enterprise_ids, 1) AS included_enterprise_count,
            COALESCE(tpa.tag_paths, ARRAY[]::public.ltree[]) AS tag_paths,
            daterange(t.valid_from, t.valid_until) AS valid_range,
            public.hash_slot(t.unit_type, t.unit_id) AS hash_slot
        FROM public.timeline_power_group t
        LEFT JOIN LATERAL (SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents FROM public.external_ident ei JOIN public.external_ident_type eit ON ei.type_id = eit.id WHERE ei.power_group_id = t.power_group_id) eia1 ON true
        LEFT JOIN LATERAL (SELECT array_agg(tag.path ORDER BY tag.path) AS tag_paths FROM public.tag_for_unit tfu JOIN public.tag ON tfu.tag_id = tag.id WHERE tfu.power_group_id = t.power_group_id) tpa ON true
        WHERE t.unit_id = ANY(v_ids);
    END IF;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.timeline_establishment_def_for(p_unit_ids integer[])
 RETURNS SETOF timeline_establishment
 LANGUAGE sql
 STABLE
AS $function$
 WITH establishment_stats AS (
         SELECT t_1.unit_id,
            t_1.valid_from,
            public.jsonb_stats_agg(sd.code::text, sfu.stat) FILTER (WHERE sd.code IS NOT NULL) AS stats
           FROM public.timesegments t_1
             JOIN public.stat_for_unit sfu ON sfu.establishment_id = t_1.unit_id AND public.from_until_overlaps(t_1.valid_from, t_1.valid_until, sfu.valid_from, sfu.valid_until)
             JOIN public.stat_definition sd ON sfu.stat_definition_id = sd.id
          WHERE t_1.unit_type = 'establishment'::public.statistical_unit_type AND (p_unit_ids IS NULL OR t_1.unit_id = ANY (p_unit_ids))
          GROUP BY t_1.unit_id, t_1.valid_from
        )
 SELECT t.unit_type,
    t.unit_id,
    t.valid_from,
    (t.valid_until - '1 day'::interval)::date AS valid_to,
    t.valid_until,
    es.name,
    es.birth_date,
    es.death_date,
    to_tsvector('simple'::regconfig, es.name::text) AS search,
    pa.category_id AS primary_activity_category_id,
    pac.path AS primary_activity_category_path,
    pac.code AS primary_activity_category_code,
    sa.category_id AS secondary_activity_category_id,
    sac.path AS secondary_activity_category_path,
    sac.code AS secondary_activity_category_code,
    NULLIF(array_remove(ARRAY[pac.path, sac.path], NULL::public.ltree), '{}'::public.ltree[]) AS activity_category_paths,
    s.id AS sector_id,
    s.path AS sector_path,
    s.code AS sector_code,
    s.name AS sector_name,
    COALESCE(ds.ids, ARRAY[]::integer[]) AS data_source_ids,
    COALESCE(ds.codes, ARRAY[]::text[]) AS data_source_codes,
    NULL::integer AS legal_form_id,
    NULL::text AS legal_form_code,
    NULL::text AS legal_form_name,
    phl.address_part1 AS physical_address_part1,
    phl.address_part2 AS physical_address_part2,
    phl.address_part3 AS physical_address_part3,
    phl.postcode AS physical_postcode,
    phl.postplace AS physical_postplace,
    phl.region_id AS physical_region_id,
    phr.path AS physical_region_path,
    phr.code AS physical_region_code,
    phl.country_id AS physical_country_id,
    phc.iso_2 AS physical_country_iso_2,
    phl.latitude,
    phl.longitude,
    phl.altitude,
    current_settings.country_id = phl.country_id AS domestic,
    pol.address_part1 AS postal_address_part1,
    pol.address_part2 AS postal_address_part2,
    pol.address_part3 AS postal_address_part3,
    pol.postcode AS postal_postcode,
    pol.postplace AS postal_postplace,
    pol.region_id AS postal_region_id,
    por.path AS postal_region_path,
    por.code AS postal_region_code,
    pol.country_id AS postal_country_id,
    poc.iso_2 AS postal_country_iso_2,
    c.web_address,
    c.email_address,
    c.phone_number,
    c.landline,
    c.mobile_number,
    c.fax_number,
    es.unit_size_id,
    us.code AS unit_size_code,
    es.status_id,
    st.code AS status_code,
    st.used_for_counting,
    last_edit.edit_comment AS last_edit_comment,
    last_edit.edit_by_user_id AS last_edit_by_user_id,
    last_edit.edit_at AS last_edit_at,
    es.legal_unit_id IS NOT NULL AS has_legal_unit,
    es.id AS establishment_id,
    es.legal_unit_id,
    es.enterprise_id,
    es.primary_for_enterprise,
    es.primary_for_legal_unit,
    COALESCE(es_stats.stats, '{}'::jsonb) AS stats,
    public.jsonb_stats_to_agg(COALESCE(es_stats.stats, '{}'::jsonb)) AS stats_summary,
    ARRAY[t.unit_id] AS related_establishment_ids,
    ARRAY[]::integer[] AS excluded_establishment_ids,
        CASE
            WHEN st.used_for_counting THEN ARRAY[t.unit_id]
            ELSE '{}'::integer[]
        END AS included_establishment_ids,
        CASE
            WHEN es.legal_unit_id IS NOT NULL THEN ARRAY[es.legal_unit_id]
            ELSE ARRAY[]::integer[]
        END AS related_legal_unit_ids,
    ARRAY[]::integer[] AS excluded_legal_unit_ids,
    ARRAY[]::integer[] AS included_legal_unit_ids,
        CASE
            WHEN es.enterprise_id IS NOT NULL THEN ARRAY[es.enterprise_id]
            ELSE ARRAY[]::integer[]
        END AS related_enterprise_ids,
    ARRAY[]::integer[] AS excluded_enterprise_ids,
    ARRAY[]::integer[] AS included_enterprise_ids
   FROM public.timesegments t
     JOIN LATERAL ( SELECT es_1.id,
            es_1.valid_range,
            es_1.valid_from,
            es_1.valid_to,
            es_1.valid_until,
            es_1.name,
            es_1.birth_date,
            es_1.death_date,
            es_1.free_econ_zone,
            es_1.sector_id,
            es_1.status_id,
            es_1.edit_comment,
            es_1.edit_by_user_id,
            es_1.edit_at,
            es_1.unit_size_id,
            es_1.data_source_id,
            es_1.enterprise_id,
            es_1.legal_unit_id,
            es_1.primary_for_legal_unit,
            es_1.primary_for_enterprise,
            es_1.image_id
           FROM public.establishment es_1
          WHERE es_1.id = t.unit_id AND public.from_until_overlaps(t.valid_from, t.valid_until, es_1.valid_from, es_1.valid_until)
          ORDER BY es_1.id DESC, es_1.valid_from DESC
         LIMIT 1) es ON true
     LEFT JOIN establishment_stats es_stats ON es_stats.unit_id = t.unit_id AND es_stats.valid_from = t.valid_from
     LEFT JOIN LATERAL ( SELECT a.id,
            a.valid_range,
            a.valid_from,
            a.valid_to,
            a.valid_until,
            a.type,
            a.category_id,
            a.data_source_id,
            a.edit_comment,
            a.edit_by_user_id,
            a.edit_at,
            a.establishment_id,
            a.legal_unit_id
           FROM public.activity a
          WHERE a.establishment_id = es.id AND a.type = 'primary'::public.activity_type AND public.from_until_overlaps(t.valid_from, t.valid_until, a.valid_from, a.valid_until)
          ORDER BY a.id DESC
         LIMIT 1) pa ON true
     LEFT JOIN public.activity_category pac ON pa.category_id = pac.id
     LEFT JOIN LATERAL ( SELECT a.id,
            a.valid_range,
            a.valid_from,
            a.valid_to,
            a.valid_until,
            a.type,
            a.category_id,
            a.data_source_id,
            a.edit_comment,
            a.edit_by_user_id,
            a.edit_at,
            a.establishment_id,
            a.legal_unit_id
           FROM public.activity a
          WHERE a.establishment_id = es.id AND a.type = 'secondary'::public.activity_type AND public.from_until_overlaps(t.valid_from, t.valid_until, a.valid_from, a.valid_until)
          ORDER BY a.id DESC
         LIMIT 1) sa ON true
     LEFT JOIN public.activity_category sac ON sa.category_id = sac.id
     LEFT JOIN public.sector s ON es.sector_id = s.id
     LEFT JOIN LATERAL ( SELECT l.id,
            l.valid_range,
            l.valid_from,
            l.valid_to,
            l.valid_until,
            l.type,
            l.address_part1,
            l.address_part2,
            l.address_part3,
            l.postcode,
            l.postplace,
            l.region_id,
            l.country_id,
            l.latitude,
            l.longitude,
            l.altitude,
            l.establishment_id,
            l.legal_unit_id,
            l.data_source_id,
            l.edit_comment,
            l.edit_by_user_id,
            l.edit_at
           FROM public.location l
          WHERE l.establishment_id = es.id AND l.type = 'physical'::public.location_type AND public.from_until_overlaps(t.valid_from, t.valid_until, l.valid_from, l.valid_until)
          ORDER BY l.id DESC
         LIMIT 1) phl ON true
     LEFT JOIN public.region phr ON phl.region_id = phr.id
     LEFT JOIN public.country phc ON phl.country_id = phc.id
     LEFT JOIN LATERAL ( SELECT l.id,
            l.valid_range,
            l.valid_from,
            l.valid_to,
            l.valid_until,
            l.type,
            l.address_part1,
            l.address_part2,
            l.address_part3,
            l.postcode,
            l.postplace,
            l.region_id,
            l.country_id,
            l.latitude,
            l.longitude,
            l.altitude,
            l.establishment_id,
            l.legal_unit_id,
            l.data_source_id,
            l.edit_comment,
            l.edit_by_user_id,
            l.edit_at
           FROM public.location l
          WHERE l.establishment_id = es.id AND l.type = 'postal'::public.location_type AND public.from_until_overlaps(t.valid_from, t.valid_until, l.valid_from, l.valid_until)
          ORDER BY l.id DESC
         LIMIT 1) pol ON true
     LEFT JOIN public.region por ON pol.region_id = por.id
     LEFT JOIN public.country poc ON pol.country_id = poc.id
     LEFT JOIN LATERAL ( SELECT c_1.id,
            c_1.valid_range,
            c_1.valid_from,
            c_1.valid_to,
            c_1.valid_until,
            c_1.web_address,
            c_1.email_address,
            c_1.phone_number,
            c_1.landline,
            c_1.mobile_number,
            c_1.fax_number,
            c_1.establishment_id,
            c_1.legal_unit_id,
            c_1.data_source_id,
            c_1.edit_comment,
            c_1.edit_by_user_id,
            c_1.edit_at
           FROM public.contact c_1
          WHERE c_1.establishment_id = es.id AND public.from_until_overlaps(t.valid_from, t.valid_until, c_1.valid_from, c_1.valid_until)
          ORDER BY c_1.id DESC
         LIMIT 1) c ON true
     LEFT JOIN public.unit_size us ON es.unit_size_id = us.id
     LEFT JOIN public.status st ON es.status_id = st.id
     LEFT JOIN LATERAL ( SELECT array_agg(DISTINCT sfu.data_source_id) FILTER (WHERE sfu.data_source_id IS NOT NULL) AS data_source_ids
           FROM public.stat_for_unit sfu
          WHERE sfu.establishment_id = es.id AND public.from_until_overlaps(t.valid_from, t.valid_until, sfu.valid_from, sfu.valid_until)) sfu_ds ON true
     LEFT JOIN LATERAL ( SELECT sfu.edit_comment,
            sfu.edit_by_user_id,
            sfu.edit_at
           FROM public.stat_for_unit sfu
          WHERE sfu.establishment_id = es.id AND public.from_until_overlaps(t.valid_from, t.valid_until, sfu.valid_from, sfu.valid_until)
          ORDER BY sfu.edit_at DESC
         LIMIT 1) sfu_le ON true
     LEFT JOIN LATERAL ( SELECT array_agg(ds_1.id) AS ids,
            array_agg(ds_1.code) AS codes
           FROM public.data_source ds_1
          WHERE COALESCE(ds_1.id = es.data_source_id, false) OR COALESCE(ds_1.id = pa.data_source_id, false) OR COALESCE(ds_1.id = sa.data_source_id, false) OR COALESCE(ds_1.id = phl.data_source_id, false) OR COALESCE(ds_1.id = pol.data_source_id, false) OR COALESCE(ds_1.id = ANY (sfu_ds.data_source_ids), false)) ds ON true
     LEFT JOIN LATERAL ( SELECT all_edits.edit_comment,
            all_edits.edit_by_user_id,
            all_edits.edit_at
           FROM ( VALUES (es.edit_comment,es.edit_by_user_id,es.edit_at), (pa.edit_comment,pa.edit_by_user_id,pa.edit_at), (sa.edit_comment,sa.edit_by_user_id,sa.edit_at), (phl.edit_comment,phl.edit_by_user_id,phl.edit_at), (pol.edit_comment,pol.edit_by_user_id,pol.edit_at), (c.edit_comment,c.edit_by_user_id,c.edit_at), (sfu_le.edit_comment,sfu_le.edit_by_user_id,sfu_le.edit_at)) all_edits(edit_comment, edit_by_user_id, edit_at)
          WHERE all_edits.edit_at IS NOT NULL
          ORDER BY all_edits.edit_at DESC
         LIMIT 1) last_edit ON true,
    public.settings current_settings
  WHERE t.unit_type = 'establishment'::public.statistical_unit_type AND (p_unit_ids IS NULL OR t.unit_id = ANY (p_unit_ids))
  ORDER BY t.unit_type, t.unit_id, t.valid_from
$function$
;

CREATE OR REPLACE FUNCTION public.timeline_legal_unit_def_for(p_unit_ids integer[])
 RETURNS SETOF timeline_legal_unit
 LANGUAGE sql
 STABLE
AS $function$
 WITH legal_unit_stats AS (
         SELECT t.unit_id,
            t.valid_from,
            public.jsonb_stats_agg(sd.code::text, sfu.stat) FILTER (WHERE sd.code IS NOT NULL) AS stats
           FROM public.timesegments t
             JOIN public.stat_for_unit sfu ON sfu.legal_unit_id = t.unit_id AND public.from_until_overlaps(t.valid_from, t.valid_until, sfu.valid_from, sfu.valid_until)
             JOIN public.stat_definition sd ON sfu.stat_definition_id = sd.id
          WHERE t.unit_type = 'legal_unit'::public.statistical_unit_type AND (p_unit_ids IS NULL OR t.unit_id = ANY (p_unit_ids))
          GROUP BY t.unit_id, t.valid_from
        ), establishment_aggs AS (
         SELECT t.unit_id,
            t.valid_from,
            public.array_distinct_concat(tes.data_source_ids) AS data_source_ids,
            public.array_distinct_concat(tes.data_source_codes) AS data_source_codes,
            array_agg(DISTINCT tes.establishment_id) FILTER (WHERE tes.establishment_id IS NOT NULL) AS related_establishment_ids,
            array_agg(DISTINCT tes.establishment_id) FILTER (WHERE tes.establishment_id IS NOT NULL AND NOT tes.used_for_counting) AS excluded_establishment_ids,
            array_agg(DISTINCT tes.establishment_id) FILTER (WHERE tes.establishment_id IS NOT NULL AND tes.used_for_counting) AS included_establishment_ids,
            public.jsonb_stats_merge_agg(tes.stats_summary) FILTER (WHERE tes.used_for_counting) AS stats_summary
           FROM public.timesegments t
             JOIN public.timeline_establishment tes ON tes.legal_unit_id = t.unit_id AND public.from_until_overlaps(t.valid_from, t.valid_until, tes.valid_from, tes.valid_until)
          WHERE t.unit_type = 'legal_unit'::public.statistical_unit_type AND (p_unit_ids IS NULL OR t.unit_id = ANY (p_unit_ids))
          GROUP BY t.unit_id, t.valid_from
        ), basis AS (
         SELECT t.unit_type,
            t.unit_id,
            t.valid_from,
            (t.valid_until - '1 day'::interval)::date AS valid_to,
            t.valid_until,
            lu.name,
            lu.birth_date,
            lu.death_date,
            to_tsvector('simple'::regconfig, lu.name::text) AS search,
            pa.category_id AS primary_activity_category_id,
            pac.path AS primary_activity_category_path,
            pac.code AS primary_activity_category_code,
            sa.category_id AS secondary_activity_category_id,
            sac.path AS secondary_activity_category_path,
            sac.code AS secondary_activity_category_code,
            NULLIF(array_remove(ARRAY[pac.path, sac.path], NULL::public.ltree), '{}'::public.ltree[]) AS activity_category_paths,
            s.id AS sector_id,
            s.path AS sector_path,
            s.code AS sector_code,
            s.name AS sector_name,
            COALESCE(ds.ids, ARRAY[]::integer[]) AS data_source_ids,
            COALESCE(ds.codes, ARRAY[]::text[]) AS data_source_codes,
            lf.id AS legal_form_id,
            lf.code AS legal_form_code,
            lf.name AS legal_form_name,
            phl.address_part1 AS physical_address_part1,
            phl.address_part2 AS physical_address_part2,
            phl.address_part3 AS physical_address_part3,
            phl.postcode AS physical_postcode,
            phl.postplace AS physical_postplace,
            phl.region_id AS physical_region_id,
            phr.path AS physical_region_path,
            phr.code AS physical_region_code,
            phl.country_id AS physical_country_id,
            phc.iso_2 AS physical_country_iso_2,
            phl.latitude,
            phl.longitude,
            phl.altitude,
            current_settings.country_id = phl.country_id AS domestic,
            pol.address_part1 AS postal_address_part1,
            pol.address_part2 AS postal_address_part2,
            pol.address_part3 AS postal_address_part3,
            pol.postcode AS postal_postcode,
            pol.postplace AS postal_postplace,
            pol.region_id AS postal_region_id,
            por.path AS postal_region_path,
            por.code AS postal_region_code,
            pol.country_id AS postal_country_id,
            poc.iso_2 AS postal_country_iso_2,
            c.web_address,
            c.email_address,
            c.phone_number,
            c.landline,
            c.mobile_number,
            c.fax_number,
            lu.unit_size_id,
            us.code AS unit_size_code,
            lu.status_id,
            st.code AS status_code,
            st.used_for_counting,
            last_edit.edit_comment AS last_edit_comment,
            last_edit.edit_by_user_id AS last_edit_by_user_id,
            last_edit.edit_at AS last_edit_at,
            true AS has_legal_unit,
            lu.id AS legal_unit_id,
            lu.enterprise_id,
            lu.primary_for_enterprise,
            COALESCE(lu_stats.stats, '{}'::jsonb) AS stats,
            public.jsonb_stats_to_agg(COALESCE(lu_stats.stats, '{}'::jsonb)) AS stats_summary
           FROM public.timesegments t
             JOIN LATERAL ( SELECT lu_1.id,
                    lu_1.valid_range,
                    lu_1.valid_from,
                    lu_1.valid_to,
                    lu_1.valid_until,
                    lu_1.name,
                    lu_1.birth_date,
                    lu_1.death_date,
                    lu_1.free_econ_zone,
                    lu_1.sector_id,
                    lu_1.status_id,
                    lu_1.legal_form_id,
                    lu_1.edit_comment,
                    lu_1.edit_by_user_id,
                    lu_1.edit_at,
                    lu_1.unit_size_id,
                    lu_1.foreign_participation_id,
                    lu_1.data_source_id,
                    lu_1.enterprise_id,
                    lu_1.primary_for_enterprise,
                    lu_1.image_id
                   FROM public.legal_unit lu_1
                  WHERE lu_1.id = t.unit_id AND public.from_until_overlaps(t.valid_from, t.valid_until, lu_1.valid_from, lu_1.valid_until)
                  ORDER BY lu_1.id DESC, lu_1.valid_from DESC
                 LIMIT 1) lu ON true
             LEFT JOIN legal_unit_stats lu_stats ON lu_stats.unit_id = t.unit_id AND lu_stats.valid_from = t.valid_from
             LEFT JOIN LATERAL ( SELECT a.id,
                    a.valid_range,
                    a.valid_from,
                    a.valid_to,
                    a.valid_until,
                    a.type,
                    a.category_id,
                    a.data_source_id,
                    a.edit_comment,
                    a.edit_by_user_id,
                    a.edit_at,
                    a.establishment_id,
                    a.legal_unit_id
                   FROM public.activity a
                  WHERE a.legal_unit_id = lu.id AND a.type = 'primary'::public.activity_type AND public.from_until_overlaps(t.valid_from, t.valid_until, a.valid_from, a.valid_until)
                  ORDER BY a.id DESC
                 LIMIT 1) pa ON true
             LEFT JOIN public.activity_category pac ON pa.category_id = pac.id
             LEFT JOIN LATERAL ( SELECT a.id,
                    a.valid_range,
                    a.valid_from,
                    a.valid_to,
                    a.valid_until,
                    a.type,
                    a.category_id,
                    a.data_source_id,
                    a.edit_comment,
                    a.edit_by_user_id,
                    a.edit_at,
                    a.establishment_id,
                    a.legal_unit_id
                   FROM public.activity a
                  WHERE a.legal_unit_id = lu.id AND a.type = 'secondary'::public.activity_type AND public.from_until_overlaps(t.valid_from, t.valid_until, a.valid_from, a.valid_until)
                  ORDER BY a.id DESC
                 LIMIT 1) sa ON true
             LEFT JOIN public.activity_category sac ON sa.category_id = sac.id
             LEFT JOIN public.sector s ON lu.sector_id = s.id
             LEFT JOIN public.legal_form lf ON lu.legal_form_id = lf.id
             LEFT JOIN LATERAL ( SELECT l.id,
                    l.valid_range,
                    l.valid_from,
                    l.valid_to,
                    l.valid_until,
                    l.type,
                    l.address_part1,
                    l.address_part2,
                    l.address_part3,
                    l.postcode,
                    l.postplace,
                    l.region_id,
                    l.country_id,
                    l.latitude,
                    l.longitude,
                    l.altitude,
                    l.establishment_id,
                    l.legal_unit_id,
                    l.data_source_id,
                    l.edit_comment,
                    l.edit_by_user_id,
                    l.edit_at
                   FROM public.location l
                  WHERE l.legal_unit_id = lu.id AND l.type = 'physical'::public.location_type AND public.from_until_overlaps(t.valid_from, t.valid_until, l.valid_from, l.valid_until)
                  ORDER BY l.id DESC
                 LIMIT 1) phl ON true
             LEFT JOIN public.region phr ON phl.region_id = phr.id
             LEFT JOIN public.country phc ON phl.country_id = phc.id
             LEFT JOIN LATERAL ( SELECT l.id,
                    l.valid_range,
                    l.valid_from,
                    l.valid_to,
                    l.valid_until,
                    l.type,
                    l.address_part1,
                    l.address_part2,
                    l.address_part3,
                    l.postcode,
                    l.postplace,
                    l.region_id,
                    l.country_id,
                    l.latitude,
                    l.longitude,
                    l.altitude,
                    l.establishment_id,
                    l.legal_unit_id,
                    l.data_source_id,
                    l.edit_comment,
                    l.edit_by_user_id,
                    l.edit_at
                   FROM public.location l
                  WHERE l.legal_unit_id = lu.id AND l.type = 'postal'::public.location_type AND public.from_until_overlaps(t.valid_from, t.valid_until, l.valid_from, l.valid_until)
                  ORDER BY l.id DESC
                 LIMIT 1) pol ON true
             LEFT JOIN public.region por ON pol.region_id = por.id
             LEFT JOIN public.country poc ON pol.country_id = poc.id
             LEFT JOIN LATERAL ( SELECT c_1.id,
                    c_1.valid_range,
                    c_1.valid_from,
                    c_1.valid_to,
                    c_1.valid_until,
                    c_1.web_address,
                    c_1.email_address,
                    c_1.phone_number,
                    c_1.landline,
                    c_1.mobile_number,
                    c_1.fax_number,
                    c_1.establishment_id,
                    c_1.legal_unit_id,
                    c_1.data_source_id,
                    c_1.edit_comment,
                    c_1.edit_by_user_id,
                    c_1.edit_at
                   FROM public.contact c_1
                  WHERE c_1.legal_unit_id = lu.id AND public.from_until_overlaps(t.valid_from, t.valid_until, c_1.valid_from, c_1.valid_until)
                  ORDER BY c_1.id DESC
                 LIMIT 1) c ON true
             LEFT JOIN public.unit_size us ON lu.unit_size_id = us.id
             LEFT JOIN public.status st ON lu.status_id = st.id
             LEFT JOIN LATERAL ( SELECT array_agg(DISTINCT sfu.data_source_id) FILTER (WHERE sfu.data_source_id IS NOT NULL) AS data_source_ids
                   FROM public.stat_for_unit sfu
                  WHERE sfu.legal_unit_id = lu.id AND public.from_until_overlaps(t.valid_from, t.valid_until, sfu.valid_from, sfu.valid_until)) sfu_ds ON true
             LEFT JOIN LATERAL ( SELECT sfu.edit_comment,
                    sfu.edit_by_user_id,
                    sfu.edit_at
                   FROM public.stat_for_unit sfu
                  WHERE sfu.legal_unit_id = lu.id AND public.from_until_overlaps(t.valid_from, t.valid_until, sfu.valid_from, sfu.valid_until)
                  ORDER BY sfu.edit_at DESC
                 LIMIT 1) sfu_le ON true
             LEFT JOIN LATERAL ( SELECT array_agg(ds_1.id) AS ids,
                    array_agg(ds_1.code) AS codes
                   FROM public.data_source ds_1
                  WHERE COALESCE(ds_1.id = lu.data_source_id, false) OR COALESCE(ds_1.id = pa.data_source_id, false) OR COALESCE(ds_1.id = sa.data_source_id, false) OR COALESCE(ds_1.id = phl.data_source_id, false) OR COALESCE(ds_1.id = pol.data_source_id, false) OR COALESCE(ds_1.id = ANY (sfu_ds.data_source_ids), false)) ds ON true
             LEFT JOIN LATERAL ( SELECT all_edits.edit_comment,
                    all_edits.edit_by_user_id,
                    all_edits.edit_at
                   FROM ( VALUES (lu.edit_comment,lu.edit_by_user_id,lu.edit_at), (pa.edit_comment,pa.edit_by_user_id,pa.edit_at), (sa.edit_comment,sa.edit_by_user_id,sa.edit_at), (phl.edit_comment,phl.edit_by_user_id,phl.edit_at), (pol.edit_comment,pol.edit_by_user_id,pol.edit_at), (c.edit_comment,c.edit_by_user_id,c.edit_at), (sfu_le.edit_comment,sfu_le.edit_by_user_id,sfu_le.edit_at)) all_edits(edit_comment, edit_by_user_id, edit_at)
                  WHERE all_edits.edit_at IS NOT NULL
                  ORDER BY all_edits.edit_at DESC
                 LIMIT 1) last_edit ON true,
            public.settings current_settings
          WHERE t.unit_type = 'legal_unit'::public.statistical_unit_type AND (p_unit_ids IS NULL OR t.unit_id = ANY (p_unit_ids))
        )
 SELECT basis.unit_type,
    basis.unit_id,
    basis.valid_from,
    basis.valid_to,
    basis.valid_until,
    basis.name,
    basis.birth_date,
    basis.death_date,
    basis.search,
    basis.primary_activity_category_id,
    basis.primary_activity_category_path,
    basis.primary_activity_category_code,
    basis.secondary_activity_category_id,
    basis.secondary_activity_category_path,
    basis.secondary_activity_category_code,
    basis.activity_category_paths,
    basis.sector_id,
    basis.sector_path,
    basis.sector_code,
    basis.sector_name,
    ( SELECT array_agg(DISTINCT ids.id) AS array_agg
           FROM ( SELECT unnest(basis.data_source_ids) AS id
                UNION ALL
                 SELECT unnest(esa.data_source_ids) AS id) ids) AS data_source_ids,
    ( SELECT array_agg(DISTINCT codes.code) AS array_agg
           FROM ( SELECT unnest(basis.data_source_codes) AS code
                UNION ALL
                 SELECT unnest(esa.data_source_codes) AS code) codes) AS data_source_codes,
    basis.legal_form_id,
    basis.legal_form_code,
    basis.legal_form_name,
    basis.physical_address_part1,
    basis.physical_address_part2,
    basis.physical_address_part3,
    basis.physical_postcode,
    basis.physical_postplace,
    basis.physical_region_id,
    basis.physical_region_path,
    basis.physical_region_code,
    basis.physical_country_id,
    basis.physical_country_iso_2,
    basis.latitude,
    basis.longitude,
    basis.altitude,
    basis.domestic,
    basis.postal_address_part1,
    basis.postal_address_part2,
    basis.postal_address_part3,
    basis.postal_postcode,
    basis.postal_postplace,
    basis.postal_region_id,
    basis.postal_region_path,
    basis.postal_region_code,
    basis.postal_country_id,
    basis.postal_country_iso_2,
    basis.web_address,
    basis.email_address,
    basis.phone_number,
    basis.landline,
    basis.mobile_number,
    basis.fax_number,
    basis.unit_size_id,
    basis.unit_size_code,
    basis.status_id,
    basis.status_code,
    basis.used_for_counting,
    basis.last_edit_comment,
    basis.last_edit_by_user_id,
    basis.last_edit_at,
    basis.has_legal_unit,
    COALESCE(esa.related_establishment_ids, ARRAY[]::integer[]) AS related_establishment_ids,
    COALESCE(esa.excluded_establishment_ids, ARRAY[]::integer[]) AS excluded_establishment_ids,
    COALESCE(esa.included_establishment_ids, ARRAY[]::integer[]) AS included_establishment_ids,
    ARRAY[basis.unit_id] AS related_legal_unit_ids,
    ARRAY[]::integer[] AS excluded_legal_unit_ids,
        CASE
            WHEN basis.used_for_counting THEN ARRAY[basis.unit_id]
            ELSE '{}'::integer[]
        END AS included_legal_unit_ids,
        CASE
            WHEN basis.enterprise_id IS NOT NULL THEN ARRAY[basis.enterprise_id]
            ELSE ARRAY[]::integer[]
        END AS related_enterprise_ids,
    ARRAY[]::integer[] AS excluded_enterprise_ids,
    ARRAY[]::integer[] AS included_enterprise_ids,
    basis.legal_unit_id,
    basis.enterprise_id,
    basis.primary_for_enterprise,
    basis.stats,
        CASE
            WHEN basis.used_for_counting THEN COALESCE(public.jsonb_stats_covers(own => basis.stats_summary, parts => esa.stats_summary), '{}'::jsonb)
            ELSE '{}'::jsonb
        END AS stats_summary
   FROM basis
     LEFT JOIN establishment_aggs esa ON esa.unit_id = basis.unit_id AND esa.valid_from = basis.valid_from
  ORDER BY basis.unit_type, basis.unit_id, basis.valid_from
$function$
;

CREATE OR REPLACE FUNCTION public.relevant_statistical_units(unit_type statistical_unit_type, unit_id integer, valid_on date DEFAULT CURRENT_DATE)
 RETURNS SETOF statistical_unit
 LANGUAGE sql
 STABLE
AS $function$
    -- Step 1: Find the enterprise row directly via temporal PK index
    WITH root_unit AS (
        SELECT su.unit_type, su.unit_id,
               su.related_legal_unit_ids,
               su.related_establishment_ids,
               su.external_idents
        FROM public.statistical_unit AS su
        WHERE su.unit_type = 'enterprise'
          AND su.unit_id = public.statistical_unit_enterprise_id($1, $2, $3)
          AND public.existence_from(su) <= $3 AND $3 < public.existence_until(su)
    -- Step 2: Collect all relevant (unit_type, unit_id) pairs from arrays
    ), relevant_ids AS (
        SELECT 'enterprise'::statistical_unit_type AS unit_type, ru.unit_id FROM root_unit AS ru
        UNION ALL
        SELECT 'legal_unit'::statistical_unit_type, unnest(ru.related_legal_unit_ids) FROM root_unit AS ru
        UNION ALL
        SELECT 'establishment'::statistical_unit_type, unnest(ru.related_establishment_ids) FROM root_unit AS ru
    -- Step 3: Single join back to get full rows, ordered by external ident priority
    ), full_units AS (
        SELECT su.*
            , first_external.ident AS first_external_ident
        FROM relevant_ids AS ri
        JOIN public.statistical_unit AS su
          ON su.unit_type = ri.unit_type
         AND su.unit_id = ri.unit_id
         AND public.existence_from(su) <= $3 AND $3 < public.existence_until(su)
        LEFT JOIN LATERAL (
            SELECT eit.code, (su.external_idents->>eit.code)::text AS ident
            FROM public.external_ident_type AS eit
            ORDER BY eit.priority
            LIMIT 1
        ) first_external ON true
        ORDER BY su.unit_type, first_external_ident NULLS LAST, su.unit_id
    )
    SELECT unit_type
         , unit_id
         , valid_from
         , valid_to
         , valid_until
         , external_idents
         , name
         , birth_date
         , death_date
         , search
         , primary_activity_category_id
         , primary_activity_category_path
         , primary_activity_category_code
         , secondary_activity_category_id
         , secondary_activity_category_path
         , secondary_activity_category_code
         , activity_category_paths
         , sector_id
         , sector_path
         , sector_code
         , sector_name
         , data_source_ids
         , data_source_codes
         , legal_form_id
         , legal_form_code
         , legal_form_name
         --
         , physical_address_part1
         , physical_address_part2
         , physical_address_part3
         , physical_postcode
         , physical_postplace
         , physical_region_id
         , physical_region_path
         , physical_region_code
         , physical_country_id
         , physical_country_iso_2
         , latitude
         , longitude
         , altitude
         --
         , domestic
         --
         , postal_address_part1
         , postal_address_part2
         , postal_address_part3
         , postal_postcode
         , postal_postplace
         , postal_region_id
         , postal_region_path
         , postal_region_code
         , postal_country_id
         , postal_country_iso_2
         --
         , web_address
         , email_address
         , phone_number
         , landline
         , mobile_number
         , fax_number
         --
         , unit_size_id
         , unit_size_code
         --
         , status_id
         , status_code
         , used_for_counting
         --
         , last_edit_comment
         , last_edit_by_user_id
         , last_edit_at
         --
         , has_legal_unit
         , related_establishment_ids
         , excluded_establishment_ids
         , included_establishment_ids
         , related_legal_unit_ids
         , excluded_legal_unit_ids
         , included_legal_unit_ids
         , related_enterprise_ids
         , excluded_enterprise_ids
         , included_enterprise_ids
         , stats
         , stats_summary
         , included_establishment_count
         , included_legal_unit_count
         , included_enterprise_count
         , tag_paths
         , daterange(valid_from, valid_until) AS valid_range
         , hash_slot
    FROM full_units;
$function$
;

CREATE OR REPLACE PROCEDURE public.statistical_unit_refresh(IN p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange, IN p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange, IN p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange, IN p_power_group_id_ranges int4multirange DEFAULT NULL::int4multirange)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_batch_size INT := 262144;
    v_min_id int; v_max_id int; v_start_id int; v_end_id int;
    v_batch_num INT; v_total_units INT;
    v_batch_start_time timestamptz; v_batch_duration_ms numeric; v_batch_speed numeric; v_current_batch_size int;
    v_is_partial_refresh BOOLEAN;
    v_col_list TEXT;
BEGIN
    v_is_partial_refresh := (p_establishment_id_ranges IS NOT NULL
                            OR p_legal_unit_id_ranges IS NOT NULL
                            OR p_enterprise_id_ranges IS NOT NULL
                            OR p_power_group_id_ranges IS NOT NULL);

    -- Column list used for all INSERT statements (excludes GENERATED valid_range)
    v_col_list := 'unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
        primary_activity_category_id, primary_activity_category_path, primary_activity_category_code,
        secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code,
        activity_category_paths, sector_id, sector_path, sector_code, sector_name,
        data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name,
        physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace,
        physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2,
        latitude, longitude, altitude, domestic,
        postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace,
        postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2,
        web_address, email_address, phone_number, landline, mobile_number, fax_number,
        unit_size_id, unit_size_code, status_id, status_code, used_for_counting,
        last_edit_comment, last_edit_by_user_id, last_edit_at, has_legal_unit,
        related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
        related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
        related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
        stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths';

    IF NOT v_is_partial_refresh THEN
        ANALYZE public.timeline_establishment, public.timeline_legal_unit, public.timeline_enterprise, public.timeline_power_group;
        CREATE TEMP TABLE statistical_unit_new (LIKE public.statistical_unit) ON COMMIT DROP;
        ALTER TABLE statistical_unit_new DROP COLUMN IF EXISTS valid_range;

        -- Establishments
        v_batch_num := 0;
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = 'establishment';
        RAISE DEBUG 'Refreshing statistical units for % establishments...', v_total_units;
        IF v_min_id IS NOT NULL THEN FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_num := v_batch_num + 1; v_start_id := i; v_end_id := i + v_batch_size - 1;
            EXECUTE format('INSERT INTO statistical_unit_new (%s) SELECT %s FROM public.statistical_unit_def WHERE unit_type = %L AND unit_id BETWEEN %s AND %s', v_col_list, v_col_list, 'establishment', v_start_id, v_end_id);
        END LOOP; END IF;

        -- Legal Units
        v_batch_num := 0;
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = 'legal_unit';
        RAISE DEBUG 'Refreshing statistical units for % legal units...', v_total_units;
        IF v_min_id IS NOT NULL THEN FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_num := v_batch_num + 1; v_start_id := i; v_end_id := i + v_batch_size - 1;
            EXECUTE format('INSERT INTO statistical_unit_new (%s) SELECT %s FROM public.statistical_unit_def WHERE unit_type = %L AND unit_id BETWEEN %s AND %s', v_col_list, v_col_list, 'legal_unit', v_start_id, v_end_id);
        END LOOP; END IF;

        -- Enterprises
        v_batch_num := 0;
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = 'enterprise';
        RAISE DEBUG 'Refreshing statistical units for % enterprises...', v_total_units;
        IF v_min_id IS NOT NULL THEN FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_num := v_batch_num + 1; v_start_id := i; v_end_id := i + v_batch_size - 1;
            EXECUTE format('INSERT INTO statistical_unit_new (%s) SELECT %s FROM public.statistical_unit_def WHERE unit_type = %L AND unit_id BETWEEN %s AND %s', v_col_list, v_col_list, 'enterprise', v_start_id, v_end_id);
        END LOOP; END IF;

        -- Power Groups
        v_batch_num := 0;
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = 'power_group';
        RAISE DEBUG 'Refreshing statistical units for % power groups...', v_total_units;
        IF v_min_id IS NOT NULL THEN FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_num := v_batch_num + 1; v_start_id := i; v_end_id := i + v_batch_size - 1;
            EXECUTE format('INSERT INTO statistical_unit_new (%s) SELECT %s FROM public.statistical_unit_def WHERE unit_type = %L AND unit_id BETWEEN %s AND %s', v_col_list, v_col_list, 'power_group', v_start_id, v_end_id);
        END LOOP; END IF;

        -- quality_finding points at the rows replaced here and is refilled by the next
        -- worker.derive_quality. It references statistical_unit by a NOT ENFORCED foreign
        -- key, which TRUNCATE refuses without CASCADE even with both tables listed.
        TRUNCATE public.statistical_unit, public.quality_finding CASCADE;
        EXECUTE format('INSERT INTO public.statistical_unit (%s) SELECT %s FROM statistical_unit_new', v_col_list, v_col_list);
        ANALYZE public.statistical_unit;
    ELSE
        -- Partial refresh: Write to staging table
        IF p_establishment_id_ranges IS NOT NULL THEN
            DELETE FROM public.statistical_unit_staging WHERE unit_type = 'establishment' AND unit_id = ANY(public.int4multirange_to_array(p_establishment_id_ranges));
            EXECUTE format('INSERT INTO public.statistical_unit_staging (%s) SELECT %s FROM import.get_statistical_unit_data_partial(%L, %L::int4multirange)', v_col_list, v_col_list, 'establishment', p_establishment_id_ranges::text);
        END IF;
        IF p_legal_unit_id_ranges IS NOT NULL THEN
            DELETE FROM public.statistical_unit_staging WHERE unit_type = 'legal_unit' AND unit_id = ANY(public.int4multirange_to_array(p_legal_unit_id_ranges));
            EXECUTE format('INSERT INTO public.statistical_unit_staging (%s) SELECT %s FROM import.get_statistical_unit_data_partial(%L, %L::int4multirange)', v_col_list, v_col_list, 'legal_unit', p_legal_unit_id_ranges::text);
        END IF;
        IF p_enterprise_id_ranges IS NOT NULL THEN
            DELETE FROM public.statistical_unit_staging WHERE unit_type = 'enterprise' AND unit_id = ANY(public.int4multirange_to_array(p_enterprise_id_ranges));
            EXECUTE format('INSERT INTO public.statistical_unit_staging (%s) SELECT %s FROM import.get_statistical_unit_data_partial(%L, %L::int4multirange)', v_col_list, v_col_list, 'enterprise', p_enterprise_id_ranges::text);
        END IF;
        IF p_power_group_id_ranges IS NOT NULL THEN
            DELETE FROM public.statistical_unit_staging WHERE unit_type = 'power_group' AND unit_id = ANY(public.int4multirange_to_array(p_power_group_id_ranges));
            EXECUTE format('INSERT INTO public.statistical_unit_staging (%s) SELECT %s FROM import.get_statistical_unit_data_partial(%L, %L::int4multirange)', v_col_list, v_col_list, 'power_group', p_power_group_id_ranges::text);
        END IF;
    END IF;
END;
$procedure$
;

CREATE OR REPLACE PROCEDURE public.statistical_unit_flush_staging()
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_staging_count BIGINT;
    v_start_time timestamptz;
    v_delete_duration_ms numeric;
    v_merge_duration_ms numeric;
BEGIN
    -- Bail early if nothing to flush.
    SELECT count(*) INTO v_staging_count FROM public.statistical_unit_staging;
    IF v_staging_count = 0 THEN
        RAISE DEBUG 'statistical_unit_flush_staging: Nothing to flush (staging empty)';
        RETURN;
    END IF;

    RAISE DEBUG 'statistical_unit_flush_staging: Flushing % rows from staging', v_staging_count;

    -- Staging is truncated after every flush and refilled by the refresh
    -- batches, so its statistics describe an earlier, usually much smaller
    -- load. Plans built from them treat a large staging as small and match
    -- it unit by unit through the main table's index (STATBUS-599: 1.8M
    -- staged rows took 221 s instead of 25 s). Fresh statistics let the
    -- DELETE and MERGE below choose hash joins for large loads and index
    -- lookups for small ones.
    ANALYZE public.statistical_unit_staging;

    -- Step 1: Pre-cleanup DELETE.
    -- Remove main rows for affected (unit_type, unit_id) tuples that have
    -- no matching temporal slice in staging. Scoped to affected units so we
    -- never touch unrelated rows. The affected units are a semi join on
    -- staging, which needs no DISTINCT; the main rows are found through
    -- statistical_unit_unit_idx (STATBUS-613).
    v_start_time := clock_timestamp();
    DELETE FROM public.statistical_unit AS t
    WHERE EXISTS (
          SELECT 1 FROM public.statistical_unit_staging AS u
          WHERE u.unit_type = t.unit_type AND u.unit_id = t.unit_id
      )
      AND NOT EXISTS (
          SELECT 1 FROM public.statistical_unit_staging AS s
          WHERE s.unit_type = t.unit_type
            AND s.unit_id = t.unit_id
            AND s.valid_from = t.valid_from
            AND s.valid_to = t.valid_to
            AND COALESCE(s.valid_until, 'infinity'::date) = COALESCE(t.valid_until, 'infinity'::date)
      );
    v_delete_duration_ms := EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000;
    RAISE DEBUG 'statistical_unit_flush_staging: Pre-cleanup DELETE in % ms', round(v_delete_duration_ms);

    -- Step 2: MERGE with skip-unchanged.
    -- Match on (unit_type, unit_id, valid_from, valid_to, valid_until).
    -- WHEN MATCHED AND row tuples differ → UPDATE; identical → skip (no WAL,
    -- no index churn). WHEN NOT MATCHED BY TARGET → INSERT.
    v_start_time := clock_timestamp();
    MERGE INTO public.statistical_unit AS target
    USING public.statistical_unit_staging AS source
       ON target.unit_type = source.unit_type
      AND target.unit_id   = source.unit_id
      AND target.valid_from = source.valid_from
      AND target.valid_to   = source.valid_to
      AND COALESCE(target.valid_until, 'infinity'::date) = COALESCE(source.valid_until, 'infinity'::date)
    WHEN MATCHED AND (
           (target.external_idents, target.name, target.birth_date, target.death_date, target.search,
            target.primary_activity_category_id, target.primary_activity_category_path, target.primary_activity_category_code,
            target.secondary_activity_category_id, target.secondary_activity_category_path, target.secondary_activity_category_code,
            target.activity_category_paths, target.sector_id, target.sector_path, target.sector_code, target.sector_name,
            target.data_source_ids, target.data_source_codes, target.legal_form_id, target.legal_form_code, target.legal_form_name,
            target.physical_address_part1, target.physical_address_part2, target.physical_address_part3, target.physical_postcode, target.physical_postplace,
            target.physical_region_id, target.physical_region_path, target.physical_region_code, target.physical_country_id, target.physical_country_iso_2,
            target.latitude, target.longitude, target.altitude, target.domestic,
            target.postal_address_part1, target.postal_address_part2, target.postal_address_part3, target.postal_postcode, target.postal_postplace,
            target.postal_region_id, target.postal_region_path, target.postal_region_code, target.postal_country_id, target.postal_country_iso_2,
            target.web_address, target.email_address, target.phone_number, target.landline, target.mobile_number, target.fax_number,
            target.unit_size_id, target.unit_size_code, target.status_id, target.status_code, target.used_for_counting,
            target.last_edit_comment, target.last_edit_by_user_id, target.last_edit_at, target.has_legal_unit,
            target.related_establishment_ids, target.excluded_establishment_ids, target.included_establishment_ids,
            target.related_legal_unit_ids, target.excluded_legal_unit_ids, target.included_legal_unit_ids,
            target.related_enterprise_ids, target.excluded_enterprise_ids, target.included_enterprise_ids,
            target.stats, target.stats_summary, target.included_establishment_count, target.included_legal_unit_count, target.included_enterprise_count, target.tag_paths)
           IS DISTINCT FROM
           (source.external_idents, source.name, source.birth_date, source.death_date, source.search,
            source.primary_activity_category_id, source.primary_activity_category_path, source.primary_activity_category_code,
            source.secondary_activity_category_id, source.secondary_activity_category_path, source.secondary_activity_category_code,
            source.activity_category_paths, source.sector_id, source.sector_path, source.sector_code, source.sector_name,
            source.data_source_ids, source.data_source_codes, source.legal_form_id, source.legal_form_code, source.legal_form_name,
            source.physical_address_part1, source.physical_address_part2, source.physical_address_part3, source.physical_postcode, source.physical_postplace,
            source.physical_region_id, source.physical_region_path, source.physical_region_code, source.physical_country_id, source.physical_country_iso_2,
            source.latitude, source.longitude, source.altitude, source.domestic,
            source.postal_address_part1, source.postal_address_part2, source.postal_address_part3, source.postal_postcode, source.postal_postplace,
            source.postal_region_id, source.postal_region_path, source.postal_region_code, source.postal_country_id, source.postal_country_iso_2,
            source.web_address, source.email_address, source.phone_number, source.landline, source.mobile_number, source.fax_number,
            source.unit_size_id, source.unit_size_code, source.status_id, source.status_code, source.used_for_counting,
            source.last_edit_comment, source.last_edit_by_user_id, source.last_edit_at, source.has_legal_unit,
            source.related_establishment_ids, source.excluded_establishment_ids, source.included_establishment_ids,
            source.related_legal_unit_ids, source.excluded_legal_unit_ids, source.included_legal_unit_ids,
            source.related_enterprise_ids, source.excluded_enterprise_ids, source.included_enterprise_ids,
            source.stats, source.stats_summary, source.included_establishment_count, source.included_legal_unit_count, source.included_enterprise_count, source.tag_paths)
       ) THEN UPDATE SET
            external_idents = source.external_idents, name = source.name, birth_date = source.birth_date, death_date = source.death_date, search = source.search,
            primary_activity_category_id = source.primary_activity_category_id, primary_activity_category_path = source.primary_activity_category_path, primary_activity_category_code = source.primary_activity_category_code,
            secondary_activity_category_id = source.secondary_activity_category_id, secondary_activity_category_path = source.secondary_activity_category_path, secondary_activity_category_code = source.secondary_activity_category_code,
            activity_category_paths = source.activity_category_paths, sector_id = source.sector_id, sector_path = source.sector_path, sector_code = source.sector_code, sector_name = source.sector_name,
            data_source_ids = source.data_source_ids, data_source_codes = source.data_source_codes, legal_form_id = source.legal_form_id, legal_form_code = source.legal_form_code, legal_form_name = source.legal_form_name,
            physical_address_part1 = source.physical_address_part1, physical_address_part2 = source.physical_address_part2, physical_address_part3 = source.physical_address_part3, physical_postcode = source.physical_postcode, physical_postplace = source.physical_postplace,
            physical_region_id = source.physical_region_id, physical_region_path = source.physical_region_path, physical_region_code = source.physical_region_code, physical_country_id = source.physical_country_id, physical_country_iso_2 = source.physical_country_iso_2,
            latitude = source.latitude, longitude = source.longitude, altitude = source.altitude, domestic = source.domestic,
            postal_address_part1 = source.postal_address_part1, postal_address_part2 = source.postal_address_part2, postal_address_part3 = source.postal_address_part3, postal_postcode = source.postal_postcode, postal_postplace = source.postal_postplace,
            postal_region_id = source.postal_region_id, postal_region_path = source.postal_region_path, postal_region_code = source.postal_region_code, postal_country_id = source.postal_country_id, postal_country_iso_2 = source.postal_country_iso_2,
            web_address = source.web_address, email_address = source.email_address, phone_number = source.phone_number, landline = source.landline, mobile_number = source.mobile_number, fax_number = source.fax_number,
            unit_size_id = source.unit_size_id, unit_size_code = source.unit_size_code, status_id = source.status_id, status_code = source.status_code, used_for_counting = source.used_for_counting,
            last_edit_comment = source.last_edit_comment, last_edit_by_user_id = source.last_edit_by_user_id, last_edit_at = source.last_edit_at, has_legal_unit = source.has_legal_unit,
            related_establishment_ids = source.related_establishment_ids, excluded_establishment_ids = source.excluded_establishment_ids, included_establishment_ids = source.included_establishment_ids,
            related_legal_unit_ids = source.related_legal_unit_ids, excluded_legal_unit_ids = source.excluded_legal_unit_ids, included_legal_unit_ids = source.included_legal_unit_ids,
            related_enterprise_ids = source.related_enterprise_ids, excluded_enterprise_ids = source.excluded_enterprise_ids, included_enterprise_ids = source.included_enterprise_ids,
            stats = source.stats, stats_summary = source.stats_summary, included_establishment_count = source.included_establishment_count, included_legal_unit_count = source.included_legal_unit_count, included_enterprise_count = source.included_enterprise_count, tag_paths = source.tag_paths
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
                primary_activity_category_id, primary_activity_category_path, primary_activity_category_code,
                secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code,
                activity_category_paths, sector_id, sector_path, sector_code, sector_name,
                data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name,
                physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace,
                physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2,
                latitude, longitude, altitude, domestic,
                postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace,
                postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2,
                web_address, email_address, phone_number, landline, mobile_number, fax_number,
                unit_size_id, unit_size_code, status_id, status_code, used_for_counting,
                last_edit_comment, last_edit_by_user_id, last_edit_at, has_legal_unit,
                related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
                related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
                related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
                stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths)
        VALUES (source.unit_type, source.unit_id, source.valid_from, source.valid_to, source.valid_until, source.external_idents, source.name, source.birth_date, source.death_date, source.search,
                source.primary_activity_category_id, source.primary_activity_category_path, source.primary_activity_category_code,
                source.secondary_activity_category_id, source.secondary_activity_category_path, source.secondary_activity_category_code,
                source.activity_category_paths, source.sector_id, source.sector_path, source.sector_code, source.sector_name,
                source.data_source_ids, source.data_source_codes, source.legal_form_id, source.legal_form_code, source.legal_form_name,
                source.physical_address_part1, source.physical_address_part2, source.physical_address_part3, source.physical_postcode, source.physical_postplace,
                source.physical_region_id, source.physical_region_path, source.physical_region_code, source.physical_country_id, source.physical_country_iso_2,
                source.latitude, source.longitude, source.altitude, source.domestic,
                source.postal_address_part1, source.postal_address_part2, source.postal_address_part3, source.postal_postcode, source.postal_postplace,
                source.postal_region_id, source.postal_region_path, source.postal_region_code, source.postal_country_id, source.postal_country_iso_2,
                source.web_address, source.email_address, source.phone_number, source.landline, source.mobile_number, source.fax_number,
                source.unit_size_id, source.unit_size_code, source.status_id, source.status_code, source.used_for_counting,
                source.last_edit_comment, source.last_edit_by_user_id, source.last_edit_at, source.has_legal_unit,
                source.related_establishment_ids, source.excluded_establishment_ids, source.included_establishment_ids,
                source.related_legal_unit_ids, source.excluded_legal_unit_ids, source.included_legal_unit_ids,
                source.related_enterprise_ids, source.excluded_enterprise_ids, source.included_enterprise_ids,
                source.stats, source.stats_summary, source.included_establishment_count, source.included_legal_unit_count, source.included_enterprise_count, source.tag_paths);
    v_merge_duration_ms := EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000;
    RAISE DEBUG 'statistical_unit_flush_staging: MERGE in % ms', round(v_merge_duration_ms);

    -- Step 3: Clear staging table
    TRUNCATE public.statistical_unit_staging;

    -- Step 4: Update statistics
    ANALYZE public.statistical_unit;

    RAISE DEBUG 'statistical_unit_flush_staging: Complete (delete: % ms, merge: % ms)',
        round(v_delete_duration_ms), round(v_merge_duration_ms);
END;
$procedure$
;

CREATE OR REPLACE PROCEDURE public.timeline_enterprise_refresh(IN p_unit_id_ranges int4multirange DEFAULT NULL::int4multirange)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    p_target_table text := 'timeline_enterprise';
    p_unit_type public.statistical_unit_type := 'enterprise';
    v_batch_size INT := 32768;
    v_def_view_name text := p_target_table || '_def';
    v_min_id int; v_max_id int; v_start_id int; v_end_id int;
    v_batch_num INT := 0;
    v_total_units INT;
    v_batch_start_time timestamptz;
    v_batch_duration_ms numeric;
    v_batch_speed numeric;
    v_current_batch_size int;
    v_unit_ids INT[];
BEGIN
    IF p_unit_id_ranges IS NULL THEN
        -- Full refresh: ANALYZE and use the generic view-based approach
        ANALYZE public.timesegments, public.enterprise, public.timeline_legal_unit, public.timeline_establishment;

        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units
        FROM public.timesegments WHERE unit_type = p_unit_type;
        IF v_min_id IS NULL THEN RETURN; END IF;

        RAISE DEBUG 'Refreshing enterprise timeline for % units in batches of %...', v_total_units, v_batch_size;
        FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_start_time := clock_timestamp();
            v_batch_num := v_batch_num + 1;
            v_start_id := i; v_end_id := i + v_batch_size - 1;
            EXECUTE format('DELETE FROM public.%I WHERE unit_type = %L AND unit_id BETWEEN %L AND %L',
                           p_target_table, p_unit_type, v_start_id, v_end_id);
            EXECUTE format('INSERT INTO public.%I SELECT * FROM public.%I WHERE unit_type = %L AND unit_id BETWEEN %L AND %L',
                           p_target_table, v_def_view_name, p_unit_type, v_start_id, v_end_id);

            v_batch_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_batch_start_time))) * 1000;
            v_current_batch_size := v_batch_size;
            v_batch_speed := v_current_batch_size / (v_batch_duration_ms / 1000.0);
            RAISE DEBUG 'Enterprise timeline batch %/% done. (% units, % ms, % units/s)',
                v_batch_num, ceil(v_total_units::decimal / v_batch_size), v_current_batch_size,
                round(v_batch_duration_ms), round(v_batch_speed);
        END LOOP;

        EXECUTE format('ANALYZE public.%I', p_target_table);
    ELSE
        -- Partial refresh: Pre-materialize filtered tables to avoid O(n²) scan
        v_unit_ids := public.int4multirange_to_array(p_unit_id_ranges);

        -- Drop staging tables if exist from previous run (silent, no NOTICE)
        PERFORM set_config('client_min_messages', 'warning', true);
        DROP TABLE IF EXISTS public.timeline_legal_unit_filtered;
        DROP TABLE IF EXISTS public.timeline_establishment_filtered;
        DROP TABLE IF EXISTS pg_temp.timesegments_filtered;
        PERFORM set_config('client_min_messages', 'notice', true);

        -- The batch's enterprise segments, materialized and analyzed like the filtered timelines below: both
        -- joins read them once per enterprise, and statistics that undercount timesegments (a cloned database,
        -- an earlier rolled-back load) planned a scan of every enterprise segment per enterprise instead, growing
        -- with the square of the batch (3,000 enterprises 22 s, 500 enterprises 0.27 s; STATBUS-614).
        CREATE TEMP TABLE timesegments_filtered ON COMMIT DROP AS
        SELECT t.unit_type, t.unit_id, t.valid_from, t.valid_until
        FROM public.timesegments AS t
        WHERE t.unit_type = 'enterprise'::public.statistical_unit_type
          AND t.unit_id = ANY(v_unit_ids);
        CREATE INDEX ON pg_temp.timesegments_filtered (unit_id, valid_from);
        ANALYZE pg_temp.timesegments_filtered;

        -- Pre-filter timeline_legal_unit to only rows for these enterprises
        -- Use UNLOGGED for cross-session visibility (enables concurrency > 1)
        CREATE UNLOGGED TABLE public.timeline_legal_unit_filtered AS
        SELECT tlu.*
        FROM public.timeline_legal_unit tlu
        WHERE tlu.enterprise_id = ANY(v_unit_ids);

        -- Create index for the join
        CREATE INDEX ON public.timeline_legal_unit_filtered (enterprise_id, valid_from, valid_until);
        ANALYZE public.timeline_legal_unit_filtered;

        -- Pre-filter timeline_establishment to only rows for these enterprises
        CREATE UNLOGGED TABLE public.timeline_establishment_filtered AS
        SELECT tes.*
        FROM public.timeline_establishment tes
        WHERE tes.enterprise_id = ANY(v_unit_ids);

        -- Create index for the join
        CREATE INDEX ON public.timeline_establishment_filtered (enterprise_id, valid_from, valid_until);
        ANALYZE public.timeline_establishment_filtered;

        -- Delete existing rows for these units
        DELETE FROM public.timeline_enterprise
        WHERE unit_type = 'enterprise' AND unit_id = ANY(v_unit_ids);

        -- Insert using pre-filtered temp tables
        -- This is the timeline_enterprise_def query but using temp tables
        INSERT INTO public.timeline_enterprise
        WITH aggregation AS (
            SELECT ten.enterprise_id,
                ten.valid_from,
                ten.valid_until,
                public.array_distinct_concat(COALESCE(array_cat(tlu.data_source_ids, tes.data_source_ids), tlu.data_source_ids, tes.data_source_ids)) AS data_source_ids,
                public.array_distinct_concat(COALESCE(array_cat(tlu.data_source_codes, tes.data_source_codes), tlu.data_source_codes, tes.data_source_codes)) AS data_source_codes,
                public.array_distinct_concat(COALESCE(array_cat(tlu.related_establishment_ids, tes.related_establishment_ids), tlu.related_establishment_ids, tes.related_establishment_ids)) AS related_establishment_ids,
                public.array_distinct_concat(COALESCE(array_cat(tlu.excluded_establishment_ids, tes.excluded_establishment_ids), tlu.excluded_establishment_ids, tes.excluded_establishment_ids)) AS excluded_establishment_ids,
                public.array_distinct_concat(COALESCE(array_cat(tlu.included_establishment_ids, tes.included_establishment_ids), tlu.included_establishment_ids, tes.included_establishment_ids)) AS included_establishment_ids,
                public.array_distinct_concat(tlu.related_legal_unit_ids) AS related_legal_unit_ids,
                public.array_distinct_concat(tlu.excluded_legal_unit_ids) AS excluded_legal_unit_ids,
                public.array_distinct_concat(tlu.included_legal_unit_ids) AS included_legal_unit_ids,
                COALESCE(public.jsonb_stats_merge_agg(COALESCE(public.jsonb_stats_merge(tlu.stats_summary, tes.stats_summary), tlu.stats_summary, tes.stats_summary)), '{}'::jsonb) AS stats_summary
            FROM (
                SELECT t.unit_type,
                    t.unit_id,
                    t.valid_from,
                    t.valid_until,
                    en.id,
                    en.enabled,
                    en.short_name,
                    en.edit_comment,
                    en.edit_by_user_id,
                    en.edit_at,
                    en.id AS enterprise_id
                FROM pg_temp.timesegments_filtered t
                JOIN public.enterprise en ON t.unit_type = 'enterprise'::public.statistical_unit_type AND t.unit_id = en.id
                WHERE t.unit_id = ANY(v_unit_ids)
            ) ten
            -- CRITICAL FIX: Join against pre-filtered temp table instead of full timeline_legal_unit
            LEFT JOIN LATERAL (
                SELECT tlu_f.enterprise_id,
                    ten.valid_from,
                    ten.valid_until,
                    public.array_distinct_concat(tlu_f.data_source_ids) AS data_source_ids,
                    public.array_distinct_concat(tlu_f.data_source_codes) AS data_source_codes,
                    public.array_distinct_concat(tlu_f.related_establishment_ids) AS related_establishment_ids,
                    public.array_distinct_concat(tlu_f.excluded_establishment_ids) AS excluded_establishment_ids,
                    public.array_distinct_concat(tlu_f.included_establishment_ids) AS included_establishment_ids,
                    array_agg(DISTINCT tlu_f.legal_unit_id) AS related_legal_unit_ids,
                    array_agg(DISTINCT tlu_f.legal_unit_id) FILTER (WHERE NOT tlu_f.used_for_counting) AS excluded_legal_unit_ids,
                    array_agg(DISTINCT tlu_f.legal_unit_id) FILTER (WHERE tlu_f.used_for_counting) AS included_legal_unit_ids,
                    public.jsonb_stats_merge_agg(tlu_f.stats_summary) FILTER (WHERE tlu_f.used_for_counting) AS stats_summary
                FROM public.timeline_legal_unit_filtered tlu_f
                WHERE tlu_f.enterprise_id = ten.enterprise_id
                  AND public.from_until_overlaps(ten.valid_from, ten.valid_until, tlu_f.valid_from, tlu_f.valid_until)
                GROUP BY tlu_f.enterprise_id, ten.valid_from, ten.valid_until
            ) tlu ON true
            -- CRITICAL FIX: Join against pre-filtered temp table instead of full timeline_establishment
            LEFT JOIN LATERAL (
                SELECT tes_f.enterprise_id,
                    ten.valid_from,
                    ten.valid_until,
                    public.array_distinct_concat(tes_f.data_source_ids) AS data_source_ids,
                    public.array_distinct_concat(tes_f.data_source_codes) AS data_source_codes,
                    array_agg(DISTINCT tes_f.establishment_id) AS related_establishment_ids,
                    array_agg(DISTINCT tes_f.establishment_id) FILTER (WHERE NOT tes_f.used_for_counting) AS excluded_establishment_ids,
                    array_agg(DISTINCT tes_f.establishment_id) FILTER (WHERE tes_f.used_for_counting) AS included_establishment_ids,
                    public.jsonb_stats_merge_agg(tes_f.stats_summary) FILTER (WHERE tes_f.used_for_counting) AS stats_summary
                FROM public.timeline_establishment_filtered tes_f
                WHERE tes_f.enterprise_id = ten.enterprise_id
                  AND public.from_until_overlaps(ten.valid_from, ten.valid_until, tes_f.valid_from, tes_f.valid_until)
                GROUP BY tes_f.enterprise_id, ten.valid_from, ten.valid_until
            ) tes ON true
            GROUP BY ten.enterprise_id, ten.valid_from, ten.valid_until
        ), enterprise_with_primary_and_aggregation AS (
            SELECT
                (SELECT array_agg(DISTINCT ids.id) FROM (
                    SELECT unnest(basis.data_source_ids) AS id
                    UNION
                    SELECT unnest(aggregation.data_source_ids) AS id
                ) ids) AS data_source_ids,
                (SELECT array_agg(DISTINCT codes.code) FROM (
                    SELECT unnest(basis.data_source_codes) AS code
                    UNION ALL
                    SELECT unnest(aggregation.data_source_codes) AS code
                ) codes) AS data_source_codes,
                basis.unit_type,
                basis.unit_id,
                basis.valid_from,
                basis.valid_to,
                basis.valid_until,
                basis.name,
                basis.birth_date,
                basis.death_date,
                basis.search,
                basis.primary_activity_category_id,
                basis.primary_activity_category_path,
                basis.primary_activity_category_code,
                basis.secondary_activity_category_id,
                basis.secondary_activity_category_path,
                basis.secondary_activity_category_code,
                basis.activity_category_paths,
                basis.sector_id,
                basis.sector_path,
                basis.sector_code,
                basis.sector_name,
                basis.legal_form_id,
                basis.legal_form_code,
                basis.legal_form_name,
                basis.physical_address_part1,
                basis.physical_address_part2,
                basis.physical_address_part3,
                basis.physical_postcode,
                basis.physical_postplace,
                basis.physical_region_id,
                basis.physical_region_path,
                basis.physical_region_code,
                basis.physical_country_id,
                basis.physical_country_iso_2,
                basis.latitude,
                basis.longitude,
                basis.altitude,
                basis.domestic,
                basis.postal_address_part1,
                basis.postal_address_part2,
                basis.postal_address_part3,
                basis.postal_postcode,
                basis.postal_postplace,
                basis.postal_region_id,
                basis.postal_region_path,
                basis.postal_region_code,
                basis.postal_country_id,
                basis.postal_country_iso_2,
                basis.web_address,
                basis.email_address,
                basis.phone_number,
                basis.landline,
                basis.mobile_number,
                basis.fax_number,
                basis.unit_size_id,
                basis.unit_size_code,
                basis.status_id,
                basis.status_code,
                basis.used_for_counting,
                basis.last_edit_comment,
                basis.last_edit_by_user_id,
                basis.last_edit_at,
                basis.has_legal_unit,
                aggregation.related_establishment_ids,
                aggregation.excluded_establishment_ids,
                aggregation.included_establishment_ids,
                aggregation.related_legal_unit_ids,
                aggregation.excluded_legal_unit_ids,
                aggregation.included_legal_unit_ids,
                basis.enterprise_id,
                basis.primary_establishment_id,
                basis.primary_legal_unit_id,
                CASE WHEN basis.used_for_counting THEN aggregation.stats_summary ELSE '{}'::jsonb END AS stats_summary
            FROM (
                SELECT
                    t.unit_type,
                    t.unit_id,
                    t.valid_from,
                    (t.valid_until - '1 day'::interval)::date AS valid_to,
                    t.valid_until,
                    COALESCE(NULLIF(en.short_name::text, ''::text), plu.name::text, pes.name::text) AS name,
                    COALESCE(plu.birth_date, pes.birth_date) AS birth_date,
                    COALESCE(plu.death_date, pes.death_date) AS death_date,
                    to_tsvector('simple'::regconfig, COALESCE(NULLIF(en.short_name::text, ''::text), plu.name::text, pes.name::text)) AS search,
                    COALESCE(plu.primary_activity_category_id, pes.primary_activity_category_id) AS primary_activity_category_id,
                    COALESCE(plu.primary_activity_category_path, pes.primary_activity_category_path) AS primary_activity_category_path,
                    COALESCE(plu.primary_activity_category_code, pes.primary_activity_category_code) AS primary_activity_category_code,
                    COALESCE(plu.secondary_activity_category_id, pes.secondary_activity_category_id) AS secondary_activity_category_id,
                    COALESCE(plu.secondary_activity_category_path, pes.secondary_activity_category_path) AS secondary_activity_category_path,
                    COALESCE(plu.secondary_activity_category_code, pes.secondary_activity_category_code) AS secondary_activity_category_code,
                    COALESCE(plu.activity_category_paths, pes.activity_category_paths) AS activity_category_paths,
                    COALESCE(plu.sector_id, pes.sector_id) AS sector_id,
                    COALESCE(plu.sector_path, pes.sector_path) AS sector_path,
                    COALESCE(plu.sector_code, pes.sector_code) AS sector_code,
                    COALESCE(plu.sector_name, pes.sector_name) AS sector_name,
                    COALESCE(plu.data_source_ids, pes.data_source_ids) AS data_source_ids,
                    COALESCE(plu.data_source_codes, pes.data_source_codes) AS data_source_codes,
                    COALESCE(plu.legal_form_id, pes.legal_form_id) AS legal_form_id,
                    COALESCE(plu.legal_form_code, pes.legal_form_code) AS legal_form_code,
                    COALESCE(plu.legal_form_name, pes.legal_form_name) AS legal_form_name,
                    COALESCE(plu.physical_address_part1, pes.physical_address_part1) AS physical_address_part1,
                    COALESCE(plu.physical_address_part2, pes.physical_address_part2) AS physical_address_part2,
                    COALESCE(plu.physical_address_part3, pes.physical_address_part3) AS physical_address_part3,
                    COALESCE(plu.physical_postcode, pes.physical_postcode) AS physical_postcode,
                    COALESCE(plu.physical_postplace, pes.physical_postplace) AS physical_postplace,
                    COALESCE(plu.physical_region_id, pes.physical_region_id) AS physical_region_id,
                    COALESCE(plu.physical_region_path, pes.physical_region_path) AS physical_region_path,
                    COALESCE(plu.physical_region_code, pes.physical_region_code) AS physical_region_code,
                    COALESCE(plu.physical_country_id, pes.physical_country_id) AS physical_country_id,
                    COALESCE(plu.physical_country_iso_2, pes.physical_country_iso_2) AS physical_country_iso_2,
                    COALESCE(plu.latitude, pes.latitude) AS latitude,
                    COALESCE(plu.longitude, pes.longitude) AS longitude,
                    COALESCE(plu.altitude, pes.altitude) AS altitude,
                    COALESCE(plu.domestic, pes.domestic) AS domestic,
                    COALESCE(plu.postal_address_part1, pes.postal_address_part1) AS postal_address_part1,
                    COALESCE(plu.postal_address_part2, pes.postal_address_part2) AS postal_address_part2,
                    COALESCE(plu.postal_address_part3, pes.postal_address_part3) AS postal_address_part3,
                    COALESCE(plu.postal_postcode, pes.postal_postcode) AS postal_postcode,
                    COALESCE(plu.postal_postplace, pes.postal_postplace) AS postal_postplace,
                    COALESCE(plu.postal_region_id, pes.postal_region_id) AS postal_region_id,
                    COALESCE(plu.postal_region_path, pes.postal_region_path) AS postal_region_path,
                    COALESCE(plu.postal_region_code, pes.postal_region_code) AS postal_region_code,
                    COALESCE(plu.postal_country_id, pes.postal_country_id) AS postal_country_id,
                    COALESCE(plu.postal_country_iso_2, pes.postal_country_iso_2) AS postal_country_iso_2,
                    COALESCE(plu.web_address, pes.web_address) AS web_address,
                    COALESCE(plu.email_address, pes.email_address) AS email_address,
                    COALESCE(plu.phone_number, pes.phone_number) AS phone_number,
                    COALESCE(plu.landline, pes.landline) AS landline,
                    COALESCE(plu.mobile_number, pes.mobile_number) AS mobile_number,
                    COALESCE(plu.fax_number, pes.fax_number) AS fax_number,
                    COALESCE(plu.unit_size_id, pes.unit_size_id) AS unit_size_id,
                    COALESCE(plu.unit_size_code, pes.unit_size_code) AS unit_size_code,
                    COALESCE(plu.status_id, pes.status_id) AS status_id,
                    COALESCE(plu.status_code, pes.status_code) AS status_code,
                    COALESCE(plu.used_for_counting, pes.used_for_counting, false) AS used_for_counting,
                    last_edit.edit_comment AS last_edit_comment,
                    last_edit.edit_by_user_id AS last_edit_by_user_id,
                    last_edit.edit_at AS last_edit_at,
                    plu.legal_unit_id IS NOT NULL AS has_legal_unit,
                    en.id AS enterprise_id,
                    pes.establishment_id AS primary_establishment_id,
                    plu.legal_unit_id AS primary_legal_unit_id
                FROM pg_temp.timesegments_filtered t
                JOIN public.enterprise en ON t.unit_type = 'enterprise'::public.statistical_unit_type AND t.unit_id = en.id
                -- Use temp table for primary legal unit lookup
                LEFT JOIN LATERAL (
                    SELECT tlu_f.*
                    FROM public.timeline_legal_unit_filtered tlu_f
                    WHERE tlu_f.enterprise_id = en.id
                      AND tlu_f.primary_for_enterprise = true
                      AND public.from_until_overlaps(t.valid_from, t.valid_until, tlu_f.valid_from, tlu_f.valid_until)
                    ORDER BY tlu_f.valid_from DESC, tlu_f.legal_unit_id DESC
                    LIMIT 1
                ) plu ON true
                -- Use temp table for primary establishment lookup
                LEFT JOIN LATERAL (
                    SELECT tes_f.*
                    FROM public.timeline_establishment_filtered tes_f
                    WHERE tes_f.enterprise_id = en.id
                      AND tes_f.primary_for_enterprise = true
                      AND public.from_until_overlaps(t.valid_from, t.valid_until, tes_f.valid_from, tes_f.valid_until)
                    ORDER BY tes_f.valid_from DESC, tes_f.establishment_id DESC
                    LIMIT 1
                ) pes ON true
                -- Pick the most recent edit from enterprise, primary legal unit, or primary establishment
                LEFT JOIN LATERAL (
                    SELECT all_edits.edit_comment,
                           all_edits.edit_by_user_id,
                           all_edits.edit_at
                    FROM ( VALUES
                        (en.edit_comment, en.edit_by_user_id, en.edit_at),
                        (plu.last_edit_comment, plu.last_edit_by_user_id, plu.last_edit_at),
                        (pes.last_edit_comment, pes.last_edit_by_user_id, pes.last_edit_at)
                    ) all_edits(edit_comment, edit_by_user_id, edit_at)
                    WHERE all_edits.edit_at IS NOT NULL
                    ORDER BY all_edits.edit_at DESC
                    LIMIT 1
                ) last_edit ON true
                WHERE t.unit_id = ANY(v_unit_ids)
            ) basis
            JOIN aggregation ON basis.enterprise_id = aggregation.enterprise_id
                AND basis.valid_from = aggregation.valid_from
                AND basis.valid_until = aggregation.valid_until
        )
        SELECT
            unit_type,
            unit_id,
            valid_from,
            valid_to,
            valid_until,
            name,
            birth_date,
            death_date,
            search,
            primary_activity_category_id,
            primary_activity_category_path,
            primary_activity_category_code,
            secondary_activity_category_id,
            secondary_activity_category_path,
            secondary_activity_category_code,
            activity_category_paths,
            sector_id,
            sector_path,
            sector_code,
            sector_name,
            data_source_ids,
            data_source_codes,
            legal_form_id,
            legal_form_code,
            legal_form_name,
            physical_address_part1,
            physical_address_part2,
            physical_address_part3,
            physical_postcode,
            physical_postplace,
            physical_region_id,
            physical_region_path,
            physical_region_code,
            physical_country_id,
            physical_country_iso_2,
            latitude,
            longitude,
            altitude,
            domestic,
            postal_address_part1,
            postal_address_part2,
            postal_address_part3,
            postal_postcode,
            postal_postplace,
            postal_region_id,
            postal_region_path,
            postal_region_code,
            postal_country_id,
            postal_country_iso_2,
            web_address,
            email_address,
            phone_number,
            landline,
            mobile_number,
            fax_number,
            unit_size_id,
            unit_size_code,
            status_id,
            status_code,
            used_for_counting,
            last_edit_comment,
            last_edit_by_user_id,
            last_edit_at,
            has_legal_unit,
            related_establishment_ids,
            excluded_establishment_ids,
            included_establishment_ids,
            related_legal_unit_ids,
            excluded_legal_unit_ids,
            included_legal_unit_ids,
            ARRAY[enterprise_id] AS related_enterprise_ids,
            ARRAY[]::integer[] AS excluded_enterprise_ids,
            CASE WHEN used_for_counting THEN ARRAY[enterprise_id] ELSE ARRAY[]::integer[] END AS included_enterprise_ids,
            enterprise_id,
            primary_establishment_id,
            primary_legal_unit_id,
            stats_summary
        FROM enterprise_with_primary_and_aggregation
        ORDER BY unit_type, unit_id, valid_from;

        -- Clean up staging tables (silent, no NOTICE)
        PERFORM set_config('client_min_messages', 'warning', true);
        DROP TABLE IF EXISTS public.timeline_legal_unit_filtered;
        DROP TABLE IF EXISTS public.timeline_establishment_filtered;
        DROP TABLE IF EXISTS pg_temp.timesegments_filtered;
        PERFORM set_config('client_min_messages', 'notice', true);
    END IF;
END;
$procedure$
;

CREATE OR REPLACE PROCEDURE public.timeline_power_group_refresh(IN p_unit_id_ranges int4multirange DEFAULT NULL::int4multirange)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_unit_ids INT[];
BEGIN
    IF p_unit_id_ranges IS NULL THEN
        TRUNCATE public.timeline_power_group;
        INSERT INTO public.timeline_power_group SELECT * FROM public.timeline_power_group_def;
        ANALYZE public.timeline_power_group;
    ELSE
        v_unit_ids := public.int4multirange_to_array(p_unit_id_ranges);
        DELETE FROM public.timeline_power_group WHERE unit_id = ANY(v_unit_ids);

        -- Materialize power_group_membership ONCE to avoid re-evaluating the view
        -- in each LATERAL iteration (view has UNION DISTINCT + NOT EXISTS).
        IF to_regclass('pg_temp.pgm_temp') IS NOT NULL THEN DROP TABLE pgm_temp; END IF;
        CREATE TEMP TABLE pgm_temp ON COMMIT DROP AS
        SELECT power_group_id, legal_unit_id, power_level, valid_range
        FROM public.power_group_membership
        WHERE power_group_id = ANY(v_unit_ids);
        CREATE INDEX ON pgm_temp (power_group_id);

        -- Inline the timeline_power_group_def view logic but use pgm_temp
        INSERT INTO public.timeline_power_group
        -- MATERIALIZED: aggregate the batch's power groups once; inlined into
        -- the LEFT JOIN below it is re-evaluated per power-group row.
        WITH aggregation AS MATERIALIZED (
            SELECT
                tpg.power_group_id,
                tpg.valid_from,
                tpg.valid_until,
                array_distinct_concat(tlu.data_source_ids) AS data_source_ids,
                array_distinct_concat(tlu.data_source_codes) AS data_source_codes,
                array_distinct_concat(tlu.related_establishment_ids) AS related_establishment_ids,
                array_distinct_concat(tlu.excluded_establishment_ids) AS excluded_establishment_ids,
                array_distinct_concat(tlu.included_establishment_ids) AS included_establishment_ids,
                array_agg(DISTINCT tlu.legal_unit_id) AS related_legal_unit_ids,
                array_agg(DISTINCT tlu.legal_unit_id) FILTER (WHERE NOT tlu.used_for_counting) AS excluded_legal_unit_ids,
                array_agg(DISTINCT tlu.legal_unit_id) FILTER (WHERE tlu.used_for_counting) AS included_legal_unit_ids,
                array_agg(DISTINCT tlu.enterprise_id) AS related_enterprise_ids,
                array_agg(DISTINCT tlu.enterprise_id) FILTER (WHERE NOT tlu.used_for_counting) AS excluded_enterprise_ids,
                array_agg(DISTINCT tlu.enterprise_id) FILTER (WHERE tlu.used_for_counting) AS included_enterprise_ids,
                COALESCE(jsonb_stats_merge_agg(tlu.stats_summary) FILTER (WHERE tlu.used_for_counting), '{}'::jsonb) AS stats_summary
            FROM (
                SELECT t.unit_type, t.unit_id, t.valid_from, t.valid_until, pg.id AS power_group_id
                FROM timesegments AS t
                JOIN power_group AS pg ON t.unit_type = 'power_group'::statistical_unit_type AND t.unit_id = pg.id
                WHERE t.unit_id = ANY(v_unit_ids)
            ) AS tpg
            LEFT JOIN LATERAL (
                SELECT tlu_inner.legal_unit_id, tlu_inner.enterprise_id,
                       tlu_inner.data_source_ids, tlu_inner.data_source_codes,
                       tlu_inner.related_establishment_ids, tlu_inner.excluded_establishment_ids, tlu_inner.included_establishment_ids,
                       tlu_inner.used_for_counting, tlu_inner.stats_summary
                FROM pgm_temp AS pgm
                JOIN public.timeline_legal_unit AS tlu_inner
                    ON tlu_inner.legal_unit_id = pgm.legal_unit_id
                    AND from_until_overlaps(tpg.valid_from, tpg.valid_until, tlu_inner.valid_from, tlu_inner.valid_until)
                WHERE pgm.power_group_id = tpg.power_group_id
                  AND pgm.valid_range && daterange(tpg.valid_from, tpg.valid_until)
            ) AS tlu ON true
            GROUP BY tpg.power_group_id, tpg.valid_from, tpg.valid_until
        ),
        power_group_basis AS (
            SELECT
                tpg.unit_type, tpg.unit_id, tpg.valid_from, tpg.valid_until,
                tpg.power_group_id,
                COALESCE(NULLIF(tpg.short_name::text, ''::text), pgplu.name::text) AS name,
                pgplu.birth_date, pgplu.death_date,
                pgplu.primary_activity_category_id, pgplu.primary_activity_category_path, pgplu.primary_activity_category_code,
                pgplu.secondary_activity_category_id, pgplu.secondary_activity_category_path, pgplu.secondary_activity_category_code,
                pgplu.sector_id, pgplu.sector_path, pgplu.sector_code, pgplu.sector_name,
                pgplu.data_source_ids, pgplu.data_source_codes,
                pgplu.legal_form_id, pgplu.legal_form_code, pgplu.legal_form_name,
                pgplu.physical_address_part1, pgplu.physical_address_part2, pgplu.physical_address_part3,
                pgplu.physical_postcode, pgplu.physical_postplace,
                pgplu.physical_region_id, pgplu.physical_region_path, pgplu.physical_region_code,
                pgplu.physical_country_id, pgplu.physical_country_iso_2,
                pgplu.latitude, pgplu.longitude, pgplu.altitude,
                pgplu.domestic,
                pgplu.postal_address_part1, pgplu.postal_address_part2, pgplu.postal_address_part3,
                pgplu.postal_postcode, pgplu.postal_postplace,
                pgplu.postal_region_id, pgplu.postal_region_path, pgplu.postal_region_code,
                pgplu.postal_country_id, pgplu.postal_country_iso_2,
                pgplu.web_address, pgplu.email_address, pgplu.phone_number,
                pgplu.landline, pgplu.mobile_number, pgplu.fax_number,
                pgplu.unit_size_id, pgplu.unit_size_code,
                pgplu.status_id, pgplu.status_code,
                TRUE AS used_for_counting,
                last_edit.edit_comment AS last_edit_comment,
                last_edit.edit_by_user_id AS last_edit_by_user_id,
                last_edit.edit_at AS last_edit_at,
                CASE WHEN pgplu.legal_unit_id IS NOT NULL THEN TRUE ELSE FALSE END AS has_legal_unit,
                pgplu.legal_unit_id AS primary_legal_unit_id
            FROM (
                SELECT t.unit_type, t.unit_id, t.valid_from, t.valid_until,
                       pg.id AS power_group_id, pg.short_name, pg.edit_comment, pg.edit_by_user_id, pg.edit_at
                FROM timesegments AS t
                JOIN power_group AS pg ON t.unit_type = 'power_group'::statistical_unit_type AND t.unit_id = pg.id
                WHERE t.unit_id = ANY(v_unit_ids)
            ) AS tpg
            LEFT JOIN LATERAL (
                SELECT tlu_p.legal_unit_id, tlu_p.enterprise_id,
                       tlu_p.name, tlu_p.birth_date, tlu_p.death_date,
                       tlu_p.primary_activity_category_id, tlu_p.primary_activity_category_path, tlu_p.primary_activity_category_code,
                       tlu_p.secondary_activity_category_id, tlu_p.secondary_activity_category_path, tlu_p.secondary_activity_category_code,
                       tlu_p.sector_id, tlu_p.sector_path, tlu_p.sector_code, tlu_p.sector_name,
                       tlu_p.data_source_ids, tlu_p.data_source_codes,
                       tlu_p.legal_form_id, tlu_p.legal_form_code, tlu_p.legal_form_name,
                       tlu_p.physical_address_part1, tlu_p.physical_address_part2, tlu_p.physical_address_part3,
                       tlu_p.physical_postcode, tlu_p.physical_postplace,
                       tlu_p.physical_region_id, tlu_p.physical_region_path, tlu_p.physical_region_code,
                       tlu_p.physical_country_id, tlu_p.physical_country_iso_2,
                       tlu_p.latitude, tlu_p.longitude, tlu_p.altitude,
                       tlu_p.domestic,
                       tlu_p.postal_address_part1, tlu_p.postal_address_part2, tlu_p.postal_address_part3,
                       tlu_p.postal_postcode, tlu_p.postal_postplace,
                       tlu_p.postal_region_id, tlu_p.postal_region_path, tlu_p.postal_region_code,
                       tlu_p.postal_country_id, tlu_p.postal_country_iso_2,
                       tlu_p.web_address, tlu_p.email_address, tlu_p.phone_number,
                       tlu_p.landline, tlu_p.mobile_number, tlu_p.fax_number,
                       tlu_p.unit_size_id, tlu_p.unit_size_code,
                       tlu_p.status_id, tlu_p.status_code,
                       tlu_p.last_edit_comment, tlu_p.last_edit_by_user_id, tlu_p.last_edit_at
                FROM pgm_temp AS pgm
                JOIN public.timeline_legal_unit AS tlu_p
                    ON tlu_p.legal_unit_id = pgm.legal_unit_id
                    AND from_until_overlaps(tpg.valid_from, tpg.valid_until, tlu_p.valid_from, tlu_p.valid_until)
                WHERE pgm.power_group_id = tpg.power_group_id
                  AND pgm.power_level = 0
                  AND pgm.valid_range && daterange(tpg.valid_from, tpg.valid_until)
                ORDER BY tlu_p.valid_from DESC, tlu_p.legal_unit_id DESC
                LIMIT 1
            ) AS pgplu ON true
            LEFT JOIN LATERAL (
                SELECT all_edits.edit_comment, all_edits.edit_by_user_id, all_edits.edit_at
                FROM (VALUES
                    (tpg.edit_comment, tpg.edit_by_user_id, tpg.edit_at),
                    (pgplu.last_edit_comment, pgplu.last_edit_by_user_id, pgplu.last_edit_at)
                ) AS all_edits(edit_comment, edit_by_user_id, edit_at)
                WHERE all_edits.edit_at IS NOT NULL
                ORDER BY all_edits.edit_at DESC
                LIMIT 1
            ) AS last_edit ON true
        )
        SELECT
            b.unit_type, b.unit_id, b.valid_from,
            (b.valid_until - '1 day'::interval)::date AS valid_to,
            b.valid_until,
            b.name, b.birth_date, b.death_date,
            to_tsvector('simple'::regconfig, COALESCE(b.name, '')) AS search,
            b.primary_activity_category_id, b.primary_activity_category_path, b.primary_activity_category_code,
            b.secondary_activity_category_id, b.secondary_activity_category_path, b.secondary_activity_category_code,
            NULLIF(array_remove(ARRAY[b.primary_activity_category_path, b.secondary_activity_category_path], NULL::ltree), '{}'::ltree[]) AS activity_category_paths,
            b.sector_id, b.sector_path, b.sector_code, b.sector_name,
            COALESCE(
                ( SELECT array_agg(DISTINCT ids.id) FROM (SELECT unnest(b.data_source_ids) AS id UNION SELECT unnest(a.data_source_ids) AS id) ids ),
                a.data_source_ids, b.data_source_ids
            ) AS data_source_ids,
            COALESCE(
                ( SELECT array_agg(DISTINCT codes.code) FROM (SELECT unnest(b.data_source_codes) AS code UNION ALL SELECT unnest(a.data_source_codes) AS code) codes ),
                a.data_source_codes, b.data_source_codes
            ) AS data_source_codes,
            b.legal_form_id, b.legal_form_code, b.legal_form_name,
            b.physical_address_part1, b.physical_address_part2, b.physical_address_part3, b.physical_postcode, b.physical_postplace,
            b.physical_region_id, b.physical_region_path, b.physical_region_code, b.physical_country_id, b.physical_country_iso_2,
            b.latitude, b.longitude, b.altitude, b.domestic,
            b.postal_address_part1, b.postal_address_part2, b.postal_address_part3, b.postal_postcode, b.postal_postplace,
            b.postal_region_id, b.postal_region_path, b.postal_region_code, b.postal_country_id, b.postal_country_iso_2,
            b.web_address, b.email_address, b.phone_number, b.landline, b.mobile_number, b.fax_number,
            b.unit_size_id, b.unit_size_code, b.status_id, b.status_code, b.used_for_counting,
            b.last_edit_comment, b.last_edit_by_user_id, b.last_edit_at, b.has_legal_unit,
            a.related_establishment_ids, a.excluded_establishment_ids, a.included_establishment_ids,
            a.related_legal_unit_ids, a.excluded_legal_unit_ids, a.included_legal_unit_ids,
            a.related_enterprise_ids, a.excluded_enterprise_ids, a.included_enterprise_ids,
            b.power_group_id, b.primary_legal_unit_id,
            a.stats_summary
        FROM power_group_basis AS b
        LEFT JOIN aggregation AS a ON b.power_group_id = a.power_group_id
            AND b.valid_from = a.valid_from AND b.valid_until = a.valid_until
        ORDER BY b.unit_type, b.unit_id, b.valid_from;
    END IF;
END;
$procedure$
;

-- 6. Views, from their \sv definitions with the columns renamed.
CREATE VIEW public.region_upload
 WITH (security_invoker='on') AS
 SELECT path::text AS path,
    name,
    latitude::text AS latitude,
    longitude::text AS longitude,
    altitude::text AS altitude
   FROM region
  ORDER BY (path::text)
;

CREATE VIEW public.timeline_establishment_def
 WITH (security_invoker='on') AS
 SELECT unit_type,
    unit_id,
    valid_from,
    valid_to,
    valid_until,
    name,
    birth_date,
    death_date,
    search,
    primary_activity_category_id,
    primary_activity_category_path,
    primary_activity_category_code,
    secondary_activity_category_id,
    secondary_activity_category_path,
    secondary_activity_category_code,
    activity_category_paths,
    sector_id,
    sector_path,
    sector_code,
    sector_name,
    data_source_ids,
    data_source_codes,
    legal_form_id,
    legal_form_code,
    legal_form_name,
    physical_address_part1,
    physical_address_part2,
    physical_address_part3,
    physical_postcode,
    physical_postplace,
    physical_region_id,
    physical_region_path,
    physical_region_code,
    physical_country_id,
    physical_country_iso_2,
    latitude,
    longitude,
    altitude,
    domestic,
    postal_address_part1,
    postal_address_part2,
    postal_address_part3,
    postal_postcode,
    postal_postplace,
    postal_region_id,
    postal_region_path,
    postal_region_code,
    postal_country_id,
    postal_country_iso_2,
    web_address,
    email_address,
    phone_number,
    landline,
    mobile_number,
    fax_number,
    unit_size_id,
    unit_size_code,
    status_id,
    status_code,
    used_for_counting,
    last_edit_comment,
    last_edit_by_user_id,
    last_edit_at,
    has_legal_unit,
    establishment_id,
    legal_unit_id,
    enterprise_id,
    primary_for_enterprise,
    primary_for_legal_unit,
    stats,
    stats_summary,
    related_establishment_ids,
    excluded_establishment_ids,
    included_establishment_ids,
    related_legal_unit_ids,
    excluded_legal_unit_ids,
    included_legal_unit_ids,
    related_enterprise_ids,
    excluded_enterprise_ids,
    included_enterprise_ids
   FROM timeline_establishment_def_for(NULL::integer[]) timeline_establishment_def_for(unit_type, unit_id, valid_from, valid_to, valid_until, name, birth_date, death_date, search, primary_activity_category_id, primary_activity_category_path, primary_activity_category_code, secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code, activity_category_paths, sector_id, sector_path, sector_code, sector_name, data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name, physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace, physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2, latitude, longitude, altitude, domestic, postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace, postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2, web_address, email_address, phone_number, landline, mobile_number, fax_number, unit_size_id, unit_size_code, status_id, status_code, used_for_counting, last_edit_comment, last_edit_by_user_id, last_edit_at, has_legal_unit, establishment_id, legal_unit_id, enterprise_id, primary_for_enterprise, primary_for_legal_unit, stats, stats_summary, related_establishment_ids, excluded_establishment_ids, included_establishment_ids, related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids, related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids)
;

CREATE VIEW public.timeline_legal_unit_def
 WITH (security_invoker='on') AS
 SELECT unit_type,
    unit_id,
    valid_from,
    valid_to,
    valid_until,
    name,
    birth_date,
    death_date,
    search,
    primary_activity_category_id,
    primary_activity_category_path,
    primary_activity_category_code,
    secondary_activity_category_id,
    secondary_activity_category_path,
    secondary_activity_category_code,
    activity_category_paths,
    sector_id,
    sector_path,
    sector_code,
    sector_name,
    data_source_ids,
    data_source_codes,
    legal_form_id,
    legal_form_code,
    legal_form_name,
    physical_address_part1,
    physical_address_part2,
    physical_address_part3,
    physical_postcode,
    physical_postplace,
    physical_region_id,
    physical_region_path,
    physical_region_code,
    physical_country_id,
    physical_country_iso_2,
    latitude,
    longitude,
    altitude,
    domestic,
    postal_address_part1,
    postal_address_part2,
    postal_address_part3,
    postal_postcode,
    postal_postplace,
    postal_region_id,
    postal_region_path,
    postal_region_code,
    postal_country_id,
    postal_country_iso_2,
    web_address,
    email_address,
    phone_number,
    landline,
    mobile_number,
    fax_number,
    unit_size_id,
    unit_size_code,
    status_id,
    status_code,
    used_for_counting,
    last_edit_comment,
    last_edit_by_user_id,
    last_edit_at,
    has_legal_unit,
    related_establishment_ids,
    excluded_establishment_ids,
    included_establishment_ids,
    related_legal_unit_ids,
    excluded_legal_unit_ids,
    included_legal_unit_ids,
    related_enterprise_ids,
    excluded_enterprise_ids,
    included_enterprise_ids,
    legal_unit_id,
    enterprise_id,
    primary_for_enterprise,
    stats,
    stats_summary
   FROM timeline_legal_unit_def_for(NULL::integer[]) timeline_legal_unit_def_for(unit_type, unit_id, valid_from, valid_to, valid_until, name, birth_date, death_date, search, primary_activity_category_id, primary_activity_category_path, primary_activity_category_code, secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code, activity_category_paths, sector_id, sector_path, sector_code, sector_name, data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name, physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace, physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2, latitude, longitude, altitude, domestic, postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace, postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2, web_address, email_address, phone_number, landline, mobile_number, fax_number, unit_size_id, unit_size_code, status_id, status_code, used_for_counting, last_edit_comment, last_edit_by_user_id, last_edit_at, has_legal_unit, related_establishment_ids, excluded_establishment_ids, included_establishment_ids, related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids, related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids, legal_unit_id, enterprise_id, primary_for_enterprise, stats, stats_summary)
;

CREATE VIEW public.timeline_enterprise_def
 WITH (security_invoker='on') AS
 WITH aggregation AS (
         SELECT ten.enterprise_id,
            ten.valid_from,
            ten.valid_until,
            array_distinct_concat(COALESCE(array_cat(tlu.data_source_ids, tes.data_source_ids), tlu.data_source_ids, tes.data_source_ids)) AS data_source_ids,
            array_distinct_concat(COALESCE(array_cat(tlu.data_source_codes, tes.data_source_codes), tlu.data_source_codes, tes.data_source_codes)) AS data_source_codes,
            array_distinct_concat(COALESCE(array_cat(tlu.related_establishment_ids, tes.related_establishment_ids), tlu.related_establishment_ids, tes.related_establishment_ids)) AS related_establishment_ids,
            array_distinct_concat(COALESCE(array_cat(tlu.excluded_establishment_ids, tes.excluded_establishment_ids), tlu.excluded_establishment_ids, tes.excluded_establishment_ids)) AS excluded_establishment_ids,
            array_distinct_concat(COALESCE(array_cat(tlu.included_establishment_ids, tes.included_establishment_ids), tlu.included_establishment_ids, tes.included_establishment_ids)) AS included_establishment_ids,
            array_distinct_concat(tlu.related_legal_unit_ids) AS related_legal_unit_ids,
            array_distinct_concat(tlu.excluded_legal_unit_ids) AS excluded_legal_unit_ids,
            array_distinct_concat(tlu.included_legal_unit_ids) AS included_legal_unit_ids,
            COALESCE(jsonb_stats_merge_agg(COALESCE(jsonb_stats_merge(tlu.stats_summary, tes.stats_summary), tlu.stats_summary, tes.stats_summary)), '{}'::jsonb) AS stats_summary
           FROM ( SELECT t.unit_type,
                    t.unit_id,
                    t.valid_from,
                    t.valid_until,
                    en.id,
                    en.enabled,
                    en.short_name,
                    en.edit_comment,
                    en.edit_by_user_id,
                    en.edit_at,
                    en.id AS enterprise_id
                   FROM timesegments t
                     JOIN enterprise en ON t.unit_type = 'enterprise'::statistical_unit_type AND t.unit_id = en.id) ten
             LEFT JOIN LATERAL ( SELECT timeline_legal_unit.enterprise_id,
                    ten.valid_from,
                    ten.valid_until,
                    array_distinct_concat(timeline_legal_unit.data_source_ids) AS data_source_ids,
                    array_distinct_concat(timeline_legal_unit.data_source_codes) AS data_source_codes,
                    array_distinct_concat(timeline_legal_unit.related_establishment_ids) AS related_establishment_ids,
                    array_distinct_concat(timeline_legal_unit.excluded_establishment_ids) AS excluded_establishment_ids,
                    array_distinct_concat(timeline_legal_unit.included_establishment_ids) AS included_establishment_ids,
                    array_agg(DISTINCT timeline_legal_unit.legal_unit_id) AS related_legal_unit_ids,
                    array_agg(DISTINCT timeline_legal_unit.legal_unit_id) FILTER (WHERE NOT timeline_legal_unit.used_for_counting) AS excluded_legal_unit_ids,
                    array_agg(DISTINCT timeline_legal_unit.legal_unit_id) FILTER (WHERE timeline_legal_unit.used_for_counting) AS included_legal_unit_ids,
                    jsonb_stats_merge_agg(timeline_legal_unit.stats_summary) FILTER (WHERE timeline_legal_unit.used_for_counting) AS stats_summary
                   FROM timeline_legal_unit
                  WHERE timeline_legal_unit.enterprise_id = ten.enterprise_id AND from_until_overlaps(ten.valid_from, ten.valid_until, timeline_legal_unit.valid_from, timeline_legal_unit.valid_until)
                  GROUP BY timeline_legal_unit.enterprise_id, ten.valid_from, ten.valid_until) tlu ON true
             LEFT JOIN LATERAL ( SELECT timeline_establishment.enterprise_id,
                    ten.valid_from,
                    ten.valid_until,
                    array_distinct_concat(timeline_establishment.data_source_ids) AS data_source_ids,
                    array_distinct_concat(timeline_establishment.data_source_codes) AS data_source_codes,
                    array_agg(DISTINCT timeline_establishment.establishment_id) AS related_establishment_ids,
                    array_agg(DISTINCT timeline_establishment.establishment_id) FILTER (WHERE NOT timeline_establishment.used_for_counting) AS excluded_establishment_ids,
                    array_agg(DISTINCT timeline_establishment.establishment_id) FILTER (WHERE timeline_establishment.used_for_counting) AS included_establishment_ids,
                    jsonb_stats_merge_agg(timeline_establishment.stats_summary) FILTER (WHERE timeline_establishment.used_for_counting) AS stats_summary
                   FROM timeline_establishment
                  WHERE timeline_establishment.enterprise_id = ten.enterprise_id AND from_until_overlaps(ten.valid_from, ten.valid_until, timeline_establishment.valid_from, timeline_establishment.valid_until)
                  GROUP BY timeline_establishment.enterprise_id, ten.valid_from, ten.valid_until) tes ON true
          GROUP BY ten.enterprise_id, ten.valid_from, ten.valid_until
        ), enterprise_with_primary_and_aggregation AS (
         SELECT ( SELECT array_agg(DISTINCT ids.id) AS array_agg
                   FROM ( SELECT unnest(basis.data_source_ids) AS id
                        UNION
                         SELECT unnest(aggregation.data_source_ids) AS id) ids) AS data_source_ids,
            ( SELECT array_agg(DISTINCT codes.code) AS array_agg
                   FROM ( SELECT unnest(basis.data_source_codes) AS code
                        UNION ALL
                         SELECT unnest(aggregation.data_source_codes) AS code) codes) AS data_source_codes,
            basis.unit_type,
            basis.unit_id,
            basis.valid_from,
            basis.valid_until,
            basis.enterprise_id,
            basis.name,
            basis.birth_date,
            basis.death_date,
            basis.primary_activity_category_id,
            basis.primary_activity_category_path,
            basis.primary_activity_category_code,
            basis.secondary_activity_category_id,
            basis.secondary_activity_category_path,
            basis.secondary_activity_category_code,
            basis.sector_id,
            basis.sector_path,
            basis.sector_code,
            basis.sector_name,
            basis.legal_form_id,
            basis.legal_form_code,
            basis.legal_form_name,
            basis.physical_address_part1,
            basis.physical_address_part2,
            basis.physical_address_part3,
            basis.physical_postcode,
            basis.physical_postplace,
            basis.physical_region_id,
            basis.physical_region_path,
            basis.physical_region_code,
            basis.physical_country_id,
            basis.physical_country_iso_2,
            basis.latitude,
            basis.longitude,
            basis.altitude,
            basis.domestic,
            basis.postal_address_part1,
            basis.postal_address_part2,
            basis.postal_address_part3,
            basis.postal_postcode,
            basis.postal_postplace,
            basis.postal_region_id,
            basis.postal_region_path,
            basis.postal_region_code,
            basis.postal_country_id,
            basis.postal_country_iso_2,
            basis.web_address,
            basis.email_address,
            basis.phone_number,
            basis.landline,
            basis.mobile_number,
            basis.fax_number,
            basis.unit_size_id,
            basis.unit_size_code,
            basis.status_id,
            basis.status_code,
            basis.used_for_counting,
            basis.last_edit_comment,
            basis.last_edit_by_user_id,
            basis.last_edit_at,
            basis.has_legal_unit,
            basis.primary_legal_unit_id,
            basis.primary_establishment_id,
            aggregation.related_establishment_ids,
            aggregation.excluded_establishment_ids,
            aggregation.included_establishment_ids,
            aggregation.related_legal_unit_ids,
            aggregation.excluded_legal_unit_ids,
            aggregation.included_legal_unit_ids,
            aggregation.stats_summary
           FROM ( SELECT ten.unit_type,
                    ten.unit_id,
                    ten.valid_from,
                    ten.valid_until,
                    ten.enterprise_id,
                    COALESCE(NULLIF(ten.short_name::text, ''::text), enplu.name::text, enpes.name::text) AS name,
                    COALESCE(enplu.birth_date, enpes.birth_date) AS birth_date,
                    COALESCE(enplu.death_date, enpes.death_date) AS death_date,
                    COALESCE(enplu.primary_activity_category_id, enpes.primary_activity_category_id) AS primary_activity_category_id,
                    COALESCE(enplu.primary_activity_category_path, enpes.primary_activity_category_path) AS primary_activity_category_path,
                    COALESCE(enplu.primary_activity_category_code, enpes.primary_activity_category_code) AS primary_activity_category_code,
                    COALESCE(enplu.secondary_activity_category_id, enpes.secondary_activity_category_id) AS secondary_activity_category_id,
                    COALESCE(enplu.secondary_activity_category_path, enpes.secondary_activity_category_path) AS secondary_activity_category_path,
                    COALESCE(enplu.secondary_activity_category_code, enpes.secondary_activity_category_code) AS secondary_activity_category_code,
                    COALESCE(enplu.sector_id, enpes.sector_id) AS sector_id,
                    COALESCE(enplu.sector_path, enpes.sector_path) AS sector_path,
                    COALESCE(enplu.sector_code, enpes.sector_code) AS sector_code,
                    COALESCE(enplu.sector_name, enpes.sector_name) AS sector_name,
                    ( SELECT array_agg(DISTINCT ids.id) AS array_agg
                           FROM ( SELECT unnest(enplu.data_source_ids) AS id
                                UNION
                                 SELECT unnest(enpes.data_source_ids) AS id) ids) AS data_source_ids,
                    ( SELECT array_agg(DISTINCT codes.code) AS array_agg
                           FROM ( SELECT unnest(enplu.data_source_codes) AS code
                                UNION
                                 SELECT unnest(enpes.data_source_codes) AS code) codes) AS data_source_codes,
                    enplu.legal_form_id,
                    enplu.legal_form_code,
                    enplu.legal_form_name,
                    COALESCE(enplu.physical_address_part1, enpes.physical_address_part1) AS physical_address_part1,
                    COALESCE(enplu.physical_address_part2, enpes.physical_address_part2) AS physical_address_part2,
                    COALESCE(enplu.physical_address_part3, enpes.physical_address_part3) AS physical_address_part3,
                    COALESCE(enplu.physical_postcode, enpes.physical_postcode) AS physical_postcode,
                    COALESCE(enplu.physical_postplace, enpes.physical_postplace) AS physical_postplace,
                    COALESCE(enplu.physical_region_id, enpes.physical_region_id) AS physical_region_id,
                    COALESCE(enplu.physical_region_path, enpes.physical_region_path) AS physical_region_path,
                    COALESCE(enplu.physical_region_code, enpes.physical_region_code) AS physical_region_code,
                    COALESCE(enplu.physical_country_id, enpes.physical_country_id) AS physical_country_id,
                    COALESCE(enplu.physical_country_iso_2, enpes.physical_country_iso_2) AS physical_country_iso_2,
                    COALESCE(enplu.latitude, enpes.latitude) AS latitude,
                    COALESCE(enplu.longitude, enpes.longitude) AS longitude,
                    COALESCE(enplu.altitude, enpes.altitude) AS altitude,
                    COALESCE(enplu.domestic, enpes.domestic) AS domestic,
                    COALESCE(enplu.postal_address_part1, enpes.postal_address_part1) AS postal_address_part1,
                    COALESCE(enplu.postal_address_part2, enpes.postal_address_part2) AS postal_address_part2,
                    COALESCE(enplu.postal_address_part3, enpes.postal_address_part3) AS postal_address_part3,
                    COALESCE(enplu.postal_postcode, enpes.postal_postcode) AS postal_postcode,
                    COALESCE(enplu.postal_postplace, enpes.postal_postplace) AS postal_postplace,
                    COALESCE(enplu.postal_region_id, enpes.postal_region_id) AS postal_region_id,
                    COALESCE(enplu.postal_region_path, enpes.postal_region_path) AS postal_region_path,
                    COALESCE(enplu.postal_region_code, enpes.postal_region_code) AS postal_region_code,
                    COALESCE(enplu.postal_country_id, enpes.postal_country_id) AS postal_country_id,
                    COALESCE(enplu.postal_country_iso_2, enpes.postal_country_iso_2) AS postal_country_iso_2,
                    COALESCE(enplu.web_address, enpes.web_address) AS web_address,
                    COALESCE(enplu.email_address, enpes.email_address) AS email_address,
                    COALESCE(enplu.phone_number, enpes.phone_number) AS phone_number,
                    COALESCE(enplu.landline, enpes.landline) AS landline,
                    COALESCE(enplu.mobile_number, enpes.mobile_number) AS mobile_number,
                    COALESCE(enplu.fax_number, enpes.fax_number) AS fax_number,
                    COALESCE(enplu.unit_size_id, enpes.unit_size_id) AS unit_size_id,
                    COALESCE(enplu.unit_size_code, enpes.unit_size_code) AS unit_size_code,
                    COALESCE(enplu.status_id, enpes.status_id) AS status_id,
                    COALESCE(enplu.status_code, enpes.status_code) AS status_code,
                    COALESCE(enplu.used_for_counting, enpes.used_for_counting) AS used_for_counting,
                    last_edit.edit_comment AS last_edit_comment,
                    last_edit.edit_by_user_id AS last_edit_by_user_id,
                    last_edit.edit_at AS last_edit_at,
                    GREATEST(enplu.has_legal_unit, enpes.has_legal_unit) AS has_legal_unit,
                    enplu.legal_unit_id AS primary_legal_unit_id,
                    enpes.establishment_id AS primary_establishment_id
                   FROM ( SELECT t.unit_type,
                            t.unit_id,
                            t.valid_from,
                            t.valid_until,
                            en.id,
                            en.enabled,
                            en.short_name,
                            en.edit_comment,
                            en.edit_by_user_id,
                            en.edit_at,
                            en.id AS enterprise_id
                           FROM timesegments t
                             JOIN enterprise en ON t.unit_type = 'enterprise'::statistical_unit_type AND t.unit_id = en.id) ten
                     LEFT JOIN LATERAL ( SELECT enplu_1.unit_type,
                            enplu_1.unit_id,
                            enplu_1.valid_from,
                            enplu_1.valid_to,
                            enplu_1.valid_until,
                            enplu_1.name,
                            enplu_1.birth_date,
                            enplu_1.death_date,
                            enplu_1.search,
                            enplu_1.primary_activity_category_id,
                            enplu_1.primary_activity_category_path,
                            enplu_1.primary_activity_category_code,
                            enplu_1.secondary_activity_category_id,
                            enplu_1.secondary_activity_category_path,
                            enplu_1.secondary_activity_category_code,
                            enplu_1.activity_category_paths,
                            enplu_1.sector_id,
                            enplu_1.sector_path,
                            enplu_1.sector_code,
                            enplu_1.sector_name,
                            enplu_1.data_source_ids,
                            enplu_1.data_source_codes,
                            enplu_1.legal_form_id,
                            enplu_1.legal_form_code,
                            enplu_1.legal_form_name,
                            enplu_1.physical_address_part1,
                            enplu_1.physical_address_part2,
                            enplu_1.physical_address_part3,
                            enplu_1.physical_postcode,
                            enplu_1.physical_postplace,
                            enplu_1.physical_region_id,
                            enplu_1.physical_region_path,
                            enplu_1.physical_region_code,
                            enplu_1.physical_country_id,
                            enplu_1.physical_country_iso_2,
                            enplu_1.latitude,
                            enplu_1.longitude,
                            enplu_1.altitude,
                            enplu_1.domestic,
                            enplu_1.postal_address_part1,
                            enplu_1.postal_address_part2,
                            enplu_1.postal_address_part3,
                            enplu_1.postal_postcode,
                            enplu_1.postal_postplace,
                            enplu_1.postal_region_id,
                            enplu_1.postal_region_path,
                            enplu_1.postal_region_code,
                            enplu_1.postal_country_id,
                            enplu_1.postal_country_iso_2,
                            enplu_1.web_address,
                            enplu_1.email_address,
                            enplu_1.phone_number,
                            enplu_1.landline,
                            enplu_1.mobile_number,
                            enplu_1.fax_number,
                            enplu_1.unit_size_id,
                            enplu_1.unit_size_code,
                            enplu_1.status_id,
                            enplu_1.status_code,
                            enplu_1.used_for_counting,
                            enplu_1.last_edit_comment,
                            enplu_1.last_edit_by_user_id,
                            enplu_1.last_edit_at,
                            enplu_1.has_legal_unit,
                            enplu_1.related_establishment_ids,
                            enplu_1.excluded_establishment_ids,
                            enplu_1.included_establishment_ids,
                            enplu_1.related_legal_unit_ids,
                            enplu_1.excluded_legal_unit_ids,
                            enplu_1.included_legal_unit_ids,
                            enplu_1.related_enterprise_ids,
                            enplu_1.excluded_enterprise_ids,
                            enplu_1.included_enterprise_ids,
                            enplu_1.legal_unit_id,
                            enplu_1.enterprise_id,
                            enplu_1.primary_for_enterprise,
                            enplu_1.stats,
                            enplu_1.stats_summary
                           FROM timeline_legal_unit enplu_1
                          WHERE enplu_1.enterprise_id = ten.enterprise_id AND enplu_1.primary_for_enterprise = true AND from_until_overlaps(ten.valid_from, ten.valid_until, enplu_1.valid_from, enplu_1.valid_until)
                          ORDER BY enplu_1.valid_from DESC, enplu_1.legal_unit_id DESC
                         LIMIT 1) enplu ON true
                     LEFT JOIN LATERAL ( SELECT enpes_1.unit_type,
                            enpes_1.unit_id,
                            enpes_1.valid_from,
                            enpes_1.valid_to,
                            enpes_1.valid_until,
                            enpes_1.name,
                            enpes_1.birth_date,
                            enpes_1.death_date,
                            enpes_1.search,
                            enpes_1.primary_activity_category_id,
                            enpes_1.primary_activity_category_path,
                            enpes_1.primary_activity_category_code,
                            enpes_1.secondary_activity_category_id,
                            enpes_1.secondary_activity_category_path,
                            enpes_1.secondary_activity_category_code,
                            enpes_1.activity_category_paths,
                            enpes_1.sector_id,
                            enpes_1.sector_path,
                            enpes_1.sector_code,
                            enpes_1.sector_name,
                            enpes_1.data_source_ids,
                            enpes_1.data_source_codes,
                            enpes_1.legal_form_id,
                            enpes_1.legal_form_code,
                            enpes_1.legal_form_name,
                            enpes_1.physical_address_part1,
                            enpes_1.physical_address_part2,
                            enpes_1.physical_address_part3,
                            enpes_1.physical_postcode,
                            enpes_1.physical_postplace,
                            enpes_1.physical_region_id,
                            enpes_1.physical_region_path,
                            enpes_1.physical_region_code,
                            enpes_1.physical_country_id,
                            enpes_1.physical_country_iso_2,
                            enpes_1.latitude,
                            enpes_1.longitude,
                            enpes_1.altitude,
                            enpes_1.domestic,
                            enpes_1.postal_address_part1,
                            enpes_1.postal_address_part2,
                            enpes_1.postal_address_part3,
                            enpes_1.postal_postcode,
                            enpes_1.postal_postplace,
                            enpes_1.postal_region_id,
                            enpes_1.postal_region_path,
                            enpes_1.postal_region_code,
                            enpes_1.postal_country_id,
                            enpes_1.postal_country_iso_2,
                            enpes_1.web_address,
                            enpes_1.email_address,
                            enpes_1.phone_number,
                            enpes_1.landline,
                            enpes_1.mobile_number,
                            enpes_1.fax_number,
                            enpes_1.unit_size_id,
                            enpes_1.unit_size_code,
                            enpes_1.status_id,
                            enpes_1.status_code,
                            enpes_1.used_for_counting,
                            enpes_1.last_edit_comment,
                            enpes_1.last_edit_by_user_id,
                            enpes_1.last_edit_at,
                            enpes_1.has_legal_unit,
                            enpes_1.establishment_id,
                            enpes_1.legal_unit_id,
                            enpes_1.enterprise_id,
                            enpes_1.primary_for_enterprise,
                            enpes_1.primary_for_legal_unit,
                            enpes_1.stats,
                            enpes_1.stats_summary,
                            enpes_1.related_establishment_ids,
                            enpes_1.excluded_establishment_ids,
                            enpes_1.included_establishment_ids,
                            enpes_1.related_legal_unit_ids,
                            enpes_1.excluded_legal_unit_ids,
                            enpes_1.included_legal_unit_ids,
                            enpes_1.related_enterprise_ids,
                            enpes_1.excluded_enterprise_ids,
                            enpes_1.included_enterprise_ids
                           FROM timeline_establishment enpes_1
                          WHERE enpes_1.enterprise_id = ten.enterprise_id AND enpes_1.primary_for_enterprise = true AND from_until_overlaps(ten.valid_from, ten.valid_until, enpes_1.valid_from, enpes_1.valid_until)
                          ORDER BY enpes_1.valid_from DESC, enpes_1.establishment_id DESC
                         LIMIT 1) enpes ON true
                     LEFT JOIN LATERAL ( SELECT all_edits.edit_comment,
                            all_edits.edit_by_user_id,
                            all_edits.edit_at
                           FROM ( VALUES (ten.edit_comment,ten.edit_by_user_id,ten.edit_at), (enplu.last_edit_comment,enplu.last_edit_by_user_id,enplu.last_edit_at), (enpes.last_edit_comment,enpes.last_edit_by_user_id,enpes.last_edit_at)) all_edits(edit_comment, edit_by_user_id, edit_at)
                          WHERE all_edits.edit_at IS NOT NULL
                          ORDER BY all_edits.edit_at DESC
                         LIMIT 1) last_edit ON true) basis
             LEFT JOIN aggregation ON basis.enterprise_id = aggregation.enterprise_id AND basis.valid_from = aggregation.valid_from AND basis.valid_until = aggregation.valid_until
        )
 SELECT unit_type,
    unit_id,
    valid_from,
    (valid_until - '1 day'::interval)::date AS valid_to,
    valid_until,
    name,
    birth_date,
    death_date,
    to_tsvector('simple'::regconfig, name) AS search,
    primary_activity_category_id,
    primary_activity_category_path,
    primary_activity_category_code,
    secondary_activity_category_id,
    secondary_activity_category_path,
    secondary_activity_category_code,
    NULLIF(array_remove(ARRAY[primary_activity_category_path, secondary_activity_category_path], NULL::ltree), '{}'::ltree[]) AS activity_category_paths,
    sector_id,
    sector_path,
    sector_code,
    sector_name,
    data_source_ids,
    data_source_codes,
    legal_form_id,
    legal_form_code,
    legal_form_name,
    physical_address_part1,
    physical_address_part2,
    physical_address_part3,
    physical_postcode,
    physical_postplace,
    physical_region_id,
    physical_region_path,
    physical_region_code,
    physical_country_id,
    physical_country_iso_2,
    latitude,
    longitude,
    altitude,
    domestic,
    postal_address_part1,
    postal_address_part2,
    postal_address_part3,
    postal_postcode,
    postal_postplace,
    postal_region_id,
    postal_region_path,
    postal_region_code,
    postal_country_id,
    postal_country_iso_2,
    web_address,
    email_address,
    phone_number,
    landline,
    mobile_number,
    fax_number,
    unit_size_id,
    unit_size_code,
    status_id,
    status_code,
    used_for_counting,
    last_edit_comment,
    last_edit_by_user_id,
    last_edit_at,
    has_legal_unit,
    related_establishment_ids,
    excluded_establishment_ids,
    included_establishment_ids,
    related_legal_unit_ids,
    excluded_legal_unit_ids,
    included_legal_unit_ids,
    ARRAY[unit_id] AS related_enterprise_ids,
    ARRAY[]::integer[] AS excluded_enterprise_ids,
        CASE
            WHEN used_for_counting THEN ARRAY[unit_id]
            ELSE '{}'::integer[]
        END AS included_enterprise_ids,
    enterprise_id,
    primary_establishment_id,
    primary_legal_unit_id,
    stats_summary
   FROM enterprise_with_primary_and_aggregation
  ORDER BY unit_type, unit_id, valid_from
;

CREATE VIEW public.timeline_power_group_def
 WITH (security_invoker='on') AS
 WITH aggregation AS (
         SELECT tpg.power_group_id,
            tpg.valid_from,
            tpg.valid_until,
            array_distinct_concat(tlu.data_source_ids) AS data_source_ids,
            array_distinct_concat(tlu.data_source_codes) AS data_source_codes,
            array_distinct_concat(tlu.related_establishment_ids) AS related_establishment_ids,
            array_distinct_concat(tlu.excluded_establishment_ids) AS excluded_establishment_ids,
            array_distinct_concat(tlu.included_establishment_ids) AS included_establishment_ids,
            array_agg(DISTINCT tlu.legal_unit_id) AS related_legal_unit_ids,
            array_agg(DISTINCT tlu.legal_unit_id) FILTER (WHERE NOT tlu.used_for_counting) AS excluded_legal_unit_ids,
            array_agg(DISTINCT tlu.legal_unit_id) FILTER (WHERE tlu.used_for_counting) AS included_legal_unit_ids,
            array_agg(DISTINCT tlu.enterprise_id) AS related_enterprise_ids,
            array_agg(DISTINCT tlu.enterprise_id) FILTER (WHERE NOT tlu.used_for_counting) AS excluded_enterprise_ids,
            array_agg(DISTINCT tlu.enterprise_id) FILTER (WHERE tlu.used_for_counting) AS included_enterprise_ids,
            COALESCE(jsonb_stats_merge_agg(tlu.stats_summary) FILTER (WHERE tlu.used_for_counting), '{}'::jsonb) AS stats_summary
           FROM ( SELECT t.unit_type,
                    t.unit_id,
                    t.valid_from,
                    t.valid_until,
                    pg.id AS power_group_id
                   FROM timesegments t
                     JOIN power_group pg ON t.unit_type = 'power_group'::statistical_unit_type AND t.unit_id = pg.id) tpg
             LEFT JOIN LATERAL ( SELECT tlu_inner.legal_unit_id,
                    tlu_inner.enterprise_id,
                    tlu_inner.data_source_ids,
                    tlu_inner.data_source_codes,
                    tlu_inner.related_establishment_ids,
                    tlu_inner.excluded_establishment_ids,
                    tlu_inner.included_establishment_ids,
                    tlu_inner.used_for_counting,
                    tlu_inner.stats_summary
                   FROM power_group_membership pgm
                     JOIN timeline_legal_unit tlu_inner ON tlu_inner.legal_unit_id = pgm.legal_unit_id AND from_until_overlaps(tpg.valid_from, tpg.valid_until, tlu_inner.valid_from, tlu_inner.valid_until)
                  WHERE pgm.power_group_id = tpg.power_group_id AND pgm.valid_range && daterange(tpg.valid_from, tpg.valid_until)) tlu ON true
          GROUP BY tpg.power_group_id, tpg.valid_from, tpg.valid_until
        ), power_group_basis AS (
         SELECT tpg.unit_type,
            tpg.unit_id,
            tpg.valid_from,
            tpg.valid_until,
            tpg.power_group_id,
            COALESCE(NULLIF(tpg.short_name::text, ''::text), pgplu.name::text) AS name,
            pgplu.birth_date,
            pgplu.death_date,
            pgplu.primary_activity_category_id,
            pgplu.primary_activity_category_path,
            pgplu.primary_activity_category_code,
            pgplu.secondary_activity_category_id,
            pgplu.secondary_activity_category_path,
            pgplu.secondary_activity_category_code,
            pgplu.sector_id,
            pgplu.sector_path,
            pgplu.sector_code,
            pgplu.sector_name,
            pgplu.data_source_ids,
            pgplu.data_source_codes,
            pgplu.legal_form_id,
            pgplu.legal_form_code,
            pgplu.legal_form_name,
            pgplu.physical_address_part1,
            pgplu.physical_address_part2,
            pgplu.physical_address_part3,
            pgplu.physical_postcode,
            pgplu.physical_postplace,
            pgplu.physical_region_id,
            pgplu.physical_region_path,
            pgplu.physical_region_code,
            pgplu.physical_country_id,
            pgplu.physical_country_iso_2,
            pgplu.latitude,
            pgplu.longitude,
            pgplu.altitude,
            pgplu.domestic,
            pgplu.postal_address_part1,
            pgplu.postal_address_part2,
            pgplu.postal_address_part3,
            pgplu.postal_postcode,
            pgplu.postal_postplace,
            pgplu.postal_region_id,
            pgplu.postal_region_path,
            pgplu.postal_region_code,
            pgplu.postal_country_id,
            pgplu.postal_country_iso_2,
            pgplu.web_address,
            pgplu.email_address,
            pgplu.phone_number,
            pgplu.landline,
            pgplu.mobile_number,
            pgplu.fax_number,
            pgplu.unit_size_id,
            pgplu.unit_size_code,
            pgplu.status_id,
            pgplu.status_code,
            true AS used_for_counting,
            last_edit.edit_comment AS last_edit_comment,
            last_edit.edit_by_user_id AS last_edit_by_user_id,
            last_edit.edit_at AS last_edit_at,
                CASE
                    WHEN pgplu.legal_unit_id IS NOT NULL THEN true
                    ELSE false
                END AS has_legal_unit,
            pgplu.legal_unit_id AS primary_legal_unit_id
           FROM ( SELECT t.unit_type,
                    t.unit_id,
                    t.valid_from,
                    t.valid_until,
                    pg.id AS power_group_id,
                    pg.short_name,
                    pg.edit_comment,
                    pg.edit_by_user_id,
                    pg.edit_at
                   FROM timesegments t
                     JOIN power_group pg ON t.unit_type = 'power_group'::statistical_unit_type AND t.unit_id = pg.id) tpg
             LEFT JOIN LATERAL ( SELECT tlu_p.legal_unit_id,
                    tlu_p.enterprise_id,
                    tlu_p.name,
                    tlu_p.birth_date,
                    tlu_p.death_date,
                    tlu_p.primary_activity_category_id,
                    tlu_p.primary_activity_category_path,
                    tlu_p.primary_activity_category_code,
                    tlu_p.secondary_activity_category_id,
                    tlu_p.secondary_activity_category_path,
                    tlu_p.secondary_activity_category_code,
                    tlu_p.sector_id,
                    tlu_p.sector_path,
                    tlu_p.sector_code,
                    tlu_p.sector_name,
                    tlu_p.data_source_ids,
                    tlu_p.data_source_codes,
                    tlu_p.legal_form_id,
                    tlu_p.legal_form_code,
                    tlu_p.legal_form_name,
                    tlu_p.physical_address_part1,
                    tlu_p.physical_address_part2,
                    tlu_p.physical_address_part3,
                    tlu_p.physical_postcode,
                    tlu_p.physical_postplace,
                    tlu_p.physical_region_id,
                    tlu_p.physical_region_path,
                    tlu_p.physical_region_code,
                    tlu_p.physical_country_id,
                    tlu_p.physical_country_iso_2,
                    tlu_p.latitude,
                    tlu_p.longitude,
                    tlu_p.altitude,
                    tlu_p.domestic,
                    tlu_p.postal_address_part1,
                    tlu_p.postal_address_part2,
                    tlu_p.postal_address_part3,
                    tlu_p.postal_postcode,
                    tlu_p.postal_postplace,
                    tlu_p.postal_region_id,
                    tlu_p.postal_region_path,
                    tlu_p.postal_region_code,
                    tlu_p.postal_country_id,
                    tlu_p.postal_country_iso_2,
                    tlu_p.web_address,
                    tlu_p.email_address,
                    tlu_p.phone_number,
                    tlu_p.landline,
                    tlu_p.mobile_number,
                    tlu_p.fax_number,
                    tlu_p.unit_size_id,
                    tlu_p.unit_size_code,
                    tlu_p.status_id,
                    tlu_p.status_code,
                    tlu_p.last_edit_comment,
                    tlu_p.last_edit_by_user_id,
                    tlu_p.last_edit_at
                   FROM power_group_membership pgm
                     JOIN timeline_legal_unit tlu_p ON tlu_p.legal_unit_id = pgm.legal_unit_id AND from_until_overlaps(tpg.valid_from, tpg.valid_until, tlu_p.valid_from, tlu_p.valid_until)
                  WHERE pgm.power_group_id = tpg.power_group_id AND pgm.power_level = 0 AND pgm.valid_range && daterange(tpg.valid_from, tpg.valid_until)
                  ORDER BY tlu_p.valid_from DESC, tlu_p.legal_unit_id DESC
                 LIMIT 1) pgplu ON true
             LEFT JOIN LATERAL ( SELECT all_edits.edit_comment,
                    all_edits.edit_by_user_id,
                    all_edits.edit_at
                   FROM ( VALUES (tpg.edit_comment,tpg.edit_by_user_id,tpg.edit_at), (pgplu.last_edit_comment,pgplu.last_edit_by_user_id,pgplu.last_edit_at)) all_edits(edit_comment, edit_by_user_id, edit_at)
                  WHERE all_edits.edit_at IS NOT NULL
                  ORDER BY all_edits.edit_at DESC
                 LIMIT 1) last_edit ON true
        )
 SELECT b.unit_type,
    b.unit_id,
    b.valid_from,
    (b.valid_until - '1 day'::interval)::date AS valid_to,
    b.valid_until,
    b.name,
    b.birth_date,
    b.death_date,
    to_tsvector('simple'::regconfig, COALESCE(b.name, ''::text)) AS search,
    b.primary_activity_category_id,
    b.primary_activity_category_path,
    b.primary_activity_category_code,
    b.secondary_activity_category_id,
    b.secondary_activity_category_path,
    b.secondary_activity_category_code,
    NULLIF(array_remove(ARRAY[b.primary_activity_category_path, b.secondary_activity_category_path], NULL::ltree), '{}'::ltree[]) AS activity_category_paths,
    b.sector_id,
    b.sector_path,
    b.sector_code,
    b.sector_name,
    COALESCE(( SELECT array_agg(DISTINCT ids.id) AS array_agg
           FROM ( SELECT unnest(b.data_source_ids) AS id
                UNION
                 SELECT unnest(a.data_source_ids) AS id) ids), a.data_source_ids, b.data_source_ids) AS data_source_ids,
    COALESCE(( SELECT array_agg(DISTINCT codes.code) AS array_agg
           FROM ( SELECT unnest(b.data_source_codes) AS code
                UNION ALL
                 SELECT unnest(a.data_source_codes) AS code) codes), a.data_source_codes, b.data_source_codes) AS data_source_codes,
    b.legal_form_id,
    b.legal_form_code,
    b.legal_form_name,
    b.physical_address_part1,
    b.physical_address_part2,
    b.physical_address_part3,
    b.physical_postcode,
    b.physical_postplace,
    b.physical_region_id,
    b.physical_region_path,
    b.physical_region_code,
    b.physical_country_id,
    b.physical_country_iso_2,
    b.latitude,
    b.longitude,
    b.altitude,
    b.domestic,
    b.postal_address_part1,
    b.postal_address_part2,
    b.postal_address_part3,
    b.postal_postcode,
    b.postal_postplace,
    b.postal_region_id,
    b.postal_region_path,
    b.postal_region_code,
    b.postal_country_id,
    b.postal_country_iso_2,
    b.web_address,
    b.email_address,
    b.phone_number,
    b.landline,
    b.mobile_number,
    b.fax_number,
    b.unit_size_id,
    b.unit_size_code,
    b.status_id,
    b.status_code,
    b.used_for_counting,
    b.last_edit_comment,
    b.last_edit_by_user_id,
    b.last_edit_at,
    b.has_legal_unit,
    a.related_establishment_ids,
    a.excluded_establishment_ids,
    a.included_establishment_ids,
    a.related_legal_unit_ids,
    a.excluded_legal_unit_ids,
    a.included_legal_unit_ids,
    a.related_enterprise_ids,
    a.excluded_enterprise_ids,
    a.included_enterprise_ids,
    b.power_group_id,
    b.primary_legal_unit_id,
    a.stats_summary
   FROM power_group_basis b
     LEFT JOIN aggregation a ON b.power_group_id = a.power_group_id AND b.valid_from = a.valid_from AND b.valid_until = a.valid_until
  ORDER BY b.unit_type, b.unit_id, b.valid_from
;

CREATE VIEW public.statistical_unit_def
 WITH (security_invoker='on') AS
 WITH external_idents_agg AS (
         SELECT all_idents.unit_type,
            all_idents.unit_id,
            jsonb_object_agg(all_idents.type_code, all_idents.ident) AS external_idents
           FROM ( SELECT 'establishment'::statistical_unit_type AS unit_type,
                    ei.establishment_id AS unit_id,
                    eit.code AS type_code,
                    COALESCE(ei.ident, ei.idents::text::character varying) AS ident
                   FROM external_ident ei
                     JOIN external_ident_type eit ON ei.type_id = eit.id
                  WHERE ei.establishment_id IS NOT NULL
                UNION ALL
                 SELECT 'legal_unit'::statistical_unit_type AS statistical_unit_type,
                    ei.legal_unit_id,
                    eit.code,
                    COALESCE(ei.ident, ei.idents::text::character varying) AS "coalesce"
                   FROM external_ident ei
                     JOIN external_ident_type eit ON ei.type_id = eit.id
                  WHERE ei.legal_unit_id IS NOT NULL
                UNION ALL
                 SELECT 'enterprise'::statistical_unit_type AS statistical_unit_type,
                    ei.enterprise_id,
                    eit.code,
                    COALESCE(ei.ident, ei.idents::text::character varying) AS "coalesce"
                   FROM external_ident ei
                     JOIN external_ident_type eit ON ei.type_id = eit.id
                  WHERE ei.enterprise_id IS NOT NULL
                UNION ALL
                 SELECT 'power_group'::statistical_unit_type AS statistical_unit_type,
                    ei.power_group_id,
                    eit.code,
                    COALESCE(ei.ident, ei.idents::text::character varying) AS "coalesce"
                   FROM external_ident ei
                     JOIN external_ident_type eit ON ei.type_id = eit.id
                  WHERE ei.power_group_id IS NOT NULL) all_idents
          GROUP BY all_idents.unit_type, all_idents.unit_id
        ), tag_paths_agg AS (
         SELECT all_tags.unit_type,
            all_tags.unit_id,
            array_agg(all_tags.path ORDER BY all_tags.path) AS tag_paths
           FROM ( SELECT 'establishment'::statistical_unit_type AS unit_type,
                    tfu.establishment_id AS unit_id,
                    t.path
                   FROM tag_for_unit tfu
                     JOIN tag t ON tfu.tag_id = t.id
                  WHERE tfu.establishment_id IS NOT NULL
                UNION ALL
                 SELECT 'legal_unit'::statistical_unit_type AS statistical_unit_type,
                    tfu.legal_unit_id,
                    t.path
                   FROM tag_for_unit tfu
                     JOIN tag t ON tfu.tag_id = t.id
                  WHERE tfu.legal_unit_id IS NOT NULL
                UNION ALL
                 SELECT 'enterprise'::statistical_unit_type AS statistical_unit_type,
                    tfu.enterprise_id,
                    t.path
                   FROM tag_for_unit tfu
                     JOIN tag t ON tfu.tag_id = t.id
                  WHERE tfu.enterprise_id IS NOT NULL
                UNION ALL
                 SELECT 'power_group'::statistical_unit_type AS statistical_unit_type,
                    tfu.power_group_id,
                    t.path
                   FROM tag_for_unit tfu
                     JOIN tag t ON tfu.tag_id = t.id
                  WHERE tfu.power_group_id IS NOT NULL) all_tags
          GROUP BY all_tags.unit_type, all_tags.unit_id
        ), data AS (
         SELECT timeline_establishment.unit_type,
            timeline_establishment.unit_id,
            timeline_establishment.valid_from,
            timeline_establishment.valid_to,
            timeline_establishment.valid_until,
            timeline_establishment.name,
            timeline_establishment.birth_date,
            timeline_establishment.death_date,
            timeline_establishment.search,
            timeline_establishment.primary_activity_category_id,
            timeline_establishment.primary_activity_category_path,
            timeline_establishment.primary_activity_category_code,
            timeline_establishment.secondary_activity_category_id,
            timeline_establishment.secondary_activity_category_path,
            timeline_establishment.secondary_activity_category_code,
            timeline_establishment.activity_category_paths,
            timeline_establishment.sector_id,
            timeline_establishment.sector_path,
            timeline_establishment.sector_code,
            timeline_establishment.sector_name,
            timeline_establishment.data_source_ids,
            timeline_establishment.data_source_codes,
            timeline_establishment.legal_form_id,
            timeline_establishment.legal_form_code,
            timeline_establishment.legal_form_name,
            timeline_establishment.physical_address_part1,
            timeline_establishment.physical_address_part2,
            timeline_establishment.physical_address_part3,
            timeline_establishment.physical_postcode,
            timeline_establishment.physical_postplace,
            timeline_establishment.physical_region_id,
            timeline_establishment.physical_region_path,
            timeline_establishment.physical_region_code,
            timeline_establishment.physical_country_id,
            timeline_establishment.physical_country_iso_2,
            timeline_establishment.latitude,
            timeline_establishment.longitude,
            timeline_establishment.altitude,
            timeline_establishment.domestic,
            timeline_establishment.postal_address_part1,
            timeline_establishment.postal_address_part2,
            timeline_establishment.postal_address_part3,
            timeline_establishment.postal_postcode,
            timeline_establishment.postal_postplace,
            timeline_establishment.postal_region_id,
            timeline_establishment.postal_region_path,
            timeline_establishment.postal_region_code,
            timeline_establishment.postal_country_id,
            timeline_establishment.postal_country_iso_2,
            timeline_establishment.web_address,
            timeline_establishment.email_address,
            timeline_establishment.phone_number,
            timeline_establishment.landline,
            timeline_establishment.mobile_number,
            timeline_establishment.fax_number,
            timeline_establishment.unit_size_id,
            timeline_establishment.unit_size_code,
            timeline_establishment.status_id,
            timeline_establishment.status_code,
            timeline_establishment.used_for_counting,
            timeline_establishment.last_edit_comment,
            timeline_establishment.last_edit_by_user_id,
            timeline_establishment.last_edit_at,
            timeline_establishment.has_legal_unit,
            timeline_establishment.related_establishment_ids,
            timeline_establishment.excluded_establishment_ids,
            timeline_establishment.included_establishment_ids,
            timeline_establishment.related_legal_unit_ids,
            timeline_establishment.excluded_legal_unit_ids,
            timeline_establishment.included_legal_unit_ids,
            timeline_establishment.related_enterprise_ids,
            timeline_establishment.excluded_enterprise_ids,
            timeline_establishment.included_enterprise_ids,
            timeline_establishment.stats,
            timeline_establishment.stats_summary,
            NULL::integer AS primary_establishment_id,
            NULL::integer AS primary_legal_unit_id
           FROM timeline_establishment
        UNION ALL
         SELECT timeline_legal_unit.unit_type,
            timeline_legal_unit.unit_id,
            timeline_legal_unit.valid_from,
            timeline_legal_unit.valid_to,
            timeline_legal_unit.valid_until,
            timeline_legal_unit.name,
            timeline_legal_unit.birth_date,
            timeline_legal_unit.death_date,
            timeline_legal_unit.search,
            timeline_legal_unit.primary_activity_category_id,
            timeline_legal_unit.primary_activity_category_path,
            timeline_legal_unit.primary_activity_category_code,
            timeline_legal_unit.secondary_activity_category_id,
            timeline_legal_unit.secondary_activity_category_path,
            timeline_legal_unit.secondary_activity_category_code,
            timeline_legal_unit.activity_category_paths,
            timeline_legal_unit.sector_id,
            timeline_legal_unit.sector_path,
            timeline_legal_unit.sector_code,
            timeline_legal_unit.sector_name,
            timeline_legal_unit.data_source_ids,
            timeline_legal_unit.data_source_codes,
            timeline_legal_unit.legal_form_id,
            timeline_legal_unit.legal_form_code,
            timeline_legal_unit.legal_form_name,
            timeline_legal_unit.physical_address_part1,
            timeline_legal_unit.physical_address_part2,
            timeline_legal_unit.physical_address_part3,
            timeline_legal_unit.physical_postcode,
            timeline_legal_unit.physical_postplace,
            timeline_legal_unit.physical_region_id,
            timeline_legal_unit.physical_region_path,
            timeline_legal_unit.physical_region_code,
            timeline_legal_unit.physical_country_id,
            timeline_legal_unit.physical_country_iso_2,
            timeline_legal_unit.latitude,
            timeline_legal_unit.longitude,
            timeline_legal_unit.altitude,
            timeline_legal_unit.domestic,
            timeline_legal_unit.postal_address_part1,
            timeline_legal_unit.postal_address_part2,
            timeline_legal_unit.postal_address_part3,
            timeline_legal_unit.postal_postcode,
            timeline_legal_unit.postal_postplace,
            timeline_legal_unit.postal_region_id,
            timeline_legal_unit.postal_region_path,
            timeline_legal_unit.postal_region_code,
            timeline_legal_unit.postal_country_id,
            timeline_legal_unit.postal_country_iso_2,
            timeline_legal_unit.web_address,
            timeline_legal_unit.email_address,
            timeline_legal_unit.phone_number,
            timeline_legal_unit.landline,
            timeline_legal_unit.mobile_number,
            timeline_legal_unit.fax_number,
            timeline_legal_unit.unit_size_id,
            timeline_legal_unit.unit_size_code,
            timeline_legal_unit.status_id,
            timeline_legal_unit.status_code,
            timeline_legal_unit.used_for_counting,
            timeline_legal_unit.last_edit_comment,
            timeline_legal_unit.last_edit_by_user_id,
            timeline_legal_unit.last_edit_at,
            timeline_legal_unit.has_legal_unit,
            timeline_legal_unit.related_establishment_ids,
            timeline_legal_unit.excluded_establishment_ids,
            timeline_legal_unit.included_establishment_ids,
            timeline_legal_unit.related_legal_unit_ids,
            timeline_legal_unit.excluded_legal_unit_ids,
            timeline_legal_unit.included_legal_unit_ids,
            timeline_legal_unit.related_enterprise_ids,
            timeline_legal_unit.excluded_enterprise_ids,
            timeline_legal_unit.included_enterprise_ids,
            NULL::jsonb AS stats,
            timeline_legal_unit.stats_summary,
            NULL::integer AS primary_establishment_id,
            NULL::integer AS primary_legal_unit_id
           FROM timeline_legal_unit
        UNION ALL
         SELECT timeline_enterprise.unit_type,
            timeline_enterprise.unit_id,
            timeline_enterprise.valid_from,
            timeline_enterprise.valid_to,
            timeline_enterprise.valid_until,
            timeline_enterprise.name,
            timeline_enterprise.birth_date,
            timeline_enterprise.death_date,
            timeline_enterprise.search,
            timeline_enterprise.primary_activity_category_id,
            timeline_enterprise.primary_activity_category_path,
            timeline_enterprise.primary_activity_category_code,
            timeline_enterprise.secondary_activity_category_id,
            timeline_enterprise.secondary_activity_category_path,
            timeline_enterprise.secondary_activity_category_code,
            timeline_enterprise.activity_category_paths,
            timeline_enterprise.sector_id,
            timeline_enterprise.sector_path,
            timeline_enterprise.sector_code,
            timeline_enterprise.sector_name,
            timeline_enterprise.data_source_ids,
            timeline_enterprise.data_source_codes,
            timeline_enterprise.legal_form_id,
            timeline_enterprise.legal_form_code,
            timeline_enterprise.legal_form_name,
            timeline_enterprise.physical_address_part1,
            timeline_enterprise.physical_address_part2,
            timeline_enterprise.physical_address_part3,
            timeline_enterprise.physical_postcode,
            timeline_enterprise.physical_postplace,
            timeline_enterprise.physical_region_id,
            timeline_enterprise.physical_region_path,
            timeline_enterprise.physical_region_code,
            timeline_enterprise.physical_country_id,
            timeline_enterprise.physical_country_iso_2,
            timeline_enterprise.latitude,
            timeline_enterprise.longitude,
            timeline_enterprise.altitude,
            timeline_enterprise.domestic,
            timeline_enterprise.postal_address_part1,
            timeline_enterprise.postal_address_part2,
            timeline_enterprise.postal_address_part3,
            timeline_enterprise.postal_postcode,
            timeline_enterprise.postal_postplace,
            timeline_enterprise.postal_region_id,
            timeline_enterprise.postal_region_path,
            timeline_enterprise.postal_region_code,
            timeline_enterprise.postal_country_id,
            timeline_enterprise.postal_country_iso_2,
            timeline_enterprise.web_address,
            timeline_enterprise.email_address,
            timeline_enterprise.phone_number,
            timeline_enterprise.landline,
            timeline_enterprise.mobile_number,
            timeline_enterprise.fax_number,
            timeline_enterprise.unit_size_id,
            timeline_enterprise.unit_size_code,
            timeline_enterprise.status_id,
            timeline_enterprise.status_code,
            timeline_enterprise.used_for_counting,
            timeline_enterprise.last_edit_comment,
            timeline_enterprise.last_edit_by_user_id,
            timeline_enterprise.last_edit_at,
            timeline_enterprise.has_legal_unit,
            timeline_enterprise.related_establishment_ids,
            timeline_enterprise.excluded_establishment_ids,
            timeline_enterprise.included_establishment_ids,
            timeline_enterprise.related_legal_unit_ids,
            timeline_enterprise.excluded_legal_unit_ids,
            timeline_enterprise.included_legal_unit_ids,
            timeline_enterprise.related_enterprise_ids,
            timeline_enterprise.excluded_enterprise_ids,
            timeline_enterprise.included_enterprise_ids,
            NULL::jsonb AS stats,
            timeline_enterprise.stats_summary,
            timeline_enterprise.primary_establishment_id,
            timeline_enterprise.primary_legal_unit_id
           FROM timeline_enterprise
        UNION ALL
         SELECT timeline_power_group.unit_type,
            timeline_power_group.unit_id,
            timeline_power_group.valid_from,
            timeline_power_group.valid_to,
            timeline_power_group.valid_until,
            timeline_power_group.name,
            timeline_power_group.birth_date,
            timeline_power_group.death_date,
            timeline_power_group.search,
            timeline_power_group.primary_activity_category_id,
            timeline_power_group.primary_activity_category_path,
            timeline_power_group.primary_activity_category_code,
            timeline_power_group.secondary_activity_category_id,
            timeline_power_group.secondary_activity_category_path,
            timeline_power_group.secondary_activity_category_code,
            timeline_power_group.activity_category_paths,
            timeline_power_group.sector_id,
            timeline_power_group.sector_path,
            timeline_power_group.sector_code,
            timeline_power_group.sector_name,
            timeline_power_group.data_source_ids,
            timeline_power_group.data_source_codes,
            timeline_power_group.legal_form_id,
            timeline_power_group.legal_form_code,
            timeline_power_group.legal_form_name,
            timeline_power_group.physical_address_part1,
            timeline_power_group.physical_address_part2,
            timeline_power_group.physical_address_part3,
            timeline_power_group.physical_postcode,
            timeline_power_group.physical_postplace,
            timeline_power_group.physical_region_id,
            timeline_power_group.physical_region_path,
            timeline_power_group.physical_region_code,
            timeline_power_group.physical_country_id,
            timeline_power_group.physical_country_iso_2,
            timeline_power_group.latitude,
            timeline_power_group.longitude,
            timeline_power_group.altitude,
            timeline_power_group.domestic,
            timeline_power_group.postal_address_part1,
            timeline_power_group.postal_address_part2,
            timeline_power_group.postal_address_part3,
            timeline_power_group.postal_postcode,
            timeline_power_group.postal_postplace,
            timeline_power_group.postal_region_id,
            timeline_power_group.postal_region_path,
            timeline_power_group.postal_region_code,
            timeline_power_group.postal_country_id,
            timeline_power_group.postal_country_iso_2,
            timeline_power_group.web_address,
            timeline_power_group.email_address,
            timeline_power_group.phone_number,
            timeline_power_group.landline,
            timeline_power_group.mobile_number,
            timeline_power_group.fax_number,
            timeline_power_group.unit_size_id,
            timeline_power_group.unit_size_code,
            timeline_power_group.status_id,
            timeline_power_group.status_code,
            timeline_power_group.used_for_counting,
            timeline_power_group.last_edit_comment,
            timeline_power_group.last_edit_by_user_id,
            timeline_power_group.last_edit_at,
            timeline_power_group.has_legal_unit,
            timeline_power_group.related_establishment_ids,
            timeline_power_group.excluded_establishment_ids,
            timeline_power_group.included_establishment_ids,
            timeline_power_group.related_legal_unit_ids,
            timeline_power_group.excluded_legal_unit_ids,
            timeline_power_group.included_legal_unit_ids,
            timeline_power_group.related_enterprise_ids,
            timeline_power_group.excluded_enterprise_ids,
            timeline_power_group.included_enterprise_ids,
            NULL::jsonb AS stats,
            timeline_power_group.stats_summary,
            NULL::integer AS primary_establishment_id,
            timeline_power_group.primary_legal_unit_id
           FROM timeline_power_group
        )
 SELECT data.unit_type,
    data.unit_id,
    data.valid_from,
    data.valid_to,
    data.valid_until,
    COALESCE(eia1.external_idents, eia2.external_idents, eia3.external_idents, '{}'::jsonb) AS external_idents,
    data.name,
    data.birth_date,
    data.death_date,
    data.search,
    data.primary_activity_category_id,
    data.primary_activity_category_path,
    data.primary_activity_category_code,
    data.secondary_activity_category_id,
    data.secondary_activity_category_path,
    data.secondary_activity_category_code,
    data.activity_category_paths,
    data.sector_id,
    data.sector_path,
    data.sector_code,
    data.sector_name,
    data.data_source_ids,
    data.data_source_codes,
    data.legal_form_id,
    data.legal_form_code,
    data.legal_form_name,
    data.physical_address_part1,
    data.physical_address_part2,
    data.physical_address_part3,
    data.physical_postcode,
    data.physical_postplace,
    data.physical_region_id,
    data.physical_region_path,
    data.physical_region_code,
    data.physical_country_id,
    data.physical_country_iso_2,
    data.latitude,
    data.longitude,
    data.altitude,
    data.domestic,
    data.postal_address_part1,
    data.postal_address_part2,
    data.postal_address_part3,
    data.postal_postcode,
    data.postal_postplace,
    data.postal_region_id,
    data.postal_region_path,
    data.postal_region_code,
    data.postal_country_id,
    data.postal_country_iso_2,
    data.web_address,
    data.email_address,
    data.phone_number,
    data.landline,
    data.mobile_number,
    data.fax_number,
    data.unit_size_id,
    data.unit_size_code,
    data.status_id,
    data.status_code,
    data.used_for_counting,
    data.last_edit_comment,
    data.last_edit_by_user_id,
    data.last_edit_at,
    data.has_legal_unit,
    data.related_establishment_ids,
    data.excluded_establishment_ids,
    data.included_establishment_ids,
    data.related_legal_unit_ids,
    data.excluded_legal_unit_ids,
    data.included_legal_unit_ids,
    data.related_enterprise_ids,
    data.excluded_enterprise_ids,
    data.included_enterprise_ids,
    data.stats,
    data.stats_summary,
    array_length(data.included_establishment_ids, 1) AS included_establishment_count,
    array_length(data.included_legal_unit_ids, 1) AS included_legal_unit_count,
    array_length(data.included_enterprise_ids, 1) AS included_enterprise_count,
    COALESCE(tpa.tag_paths, ARRAY[]::ltree[]) AS tag_paths
   FROM data
     LEFT JOIN external_idents_agg eia1 ON eia1.unit_type = data.unit_type AND eia1.unit_id = data.unit_id
     LEFT JOIN external_idents_agg eia2 ON eia2.unit_type = 'establishment'::statistical_unit_type AND eia2.unit_id = data.primary_establishment_id
     LEFT JOIN external_idents_agg eia3 ON eia3.unit_type = 'legal_unit'::statistical_unit_type AND eia3.unit_id = data.primary_legal_unit_id
     LEFT JOIN tag_paths_agg tpa ON tpa.unit_type = data.unit_type AND tpa.unit_id = data.unit_id
;

CREATE TRIGGER region_upload_upsert INSTEAD OF INSERT ON public.region_upload FOR EACH ROW EXECUTE FUNCTION admin.region_upload_upsert();
COMMENT ON VIEW public.region_upload IS
  'Upload of regions by path, with name, and optionally latitude, longitude and altitude. Each row adds or changes one region; columns a row leaves out or empty keep what is stored, so a file of path and coordinate columns adds points to the regions already listed (admin.region_upload_upsert).';
COMMENT ON VIEW public.timeline_establishment_def IS 'Every timeline_establishment row, as computed now: timeline_establishment_def_for(NULL). The full refresh reads it in ranges of unit ids.';
COMMENT ON VIEW public.timeline_legal_unit_def IS 'Every timeline_legal_unit row, as computed now: timeline_legal_unit_def_for(NULL). The full refresh reads it in ranges of unit ids.';
GRANT SELECT, INSERT ON public.region_upload TO authenticated, regular_user, admin_user;
GRANT SELECT, INSERT ON public.timeline_establishment_def, public.timeline_legal_unit_def, public.timeline_enterprise_def, public.statistical_unit_def TO authenticated, regular_user, admin_user;
GRANT SELECT ON public.timeline_power_group_def TO authenticated, regular_user, admin_user;

END;
