BEGIN;

-- Reverse Migration C: Region versioning + change triggers

-- Drop region change-tracking triggers
DROP TRIGGER IF EXISTS b_region_ensure_collect ON public.region;
DROP TRIGGER IF EXISTS a_region_log_delete ON public.region;
DROP TRIGGER IF EXISTS a_region_log_update ON public.region;
DROP TRIGGER IF EXISTS a_region_log_insert ON public.region;
DROP FUNCTION IF EXISTS worker.log_region_change();

-- Drop activity_category_standard.lasts_to
ALTER TABLE public.activity_category_standard DROP COLUMN IF EXISTS lasts_to;

-- Drop settings dual FK constraints and columns
ALTER TABLE public.settings DROP CONSTRAINT IF EXISTS settings_activity_category_standard_enabled_fk;
ALTER TABLE public.settings DROP CONSTRAINT IF EXISTS settings_region_version_enabled_fk;
DROP INDEX IF EXISTS activity_category_standard_id_enabled_key;
DROP INDEX IF EXISTS region_version_id_enabled_key;
ALTER TABLE public.settings DROP COLUMN IF EXISTS required_to_be_enabled;
ALTER TABLE public.settings DROP COLUMN IF EXISTS region_version_id;

-- Drop location CHECK constraint for region version consistency
ALTER TABLE public.location DROP CONSTRAINT IF EXISTS location_region_version_consistency;

-- Drop location dual FK and version column
ALTER TABLE public.location DROP CONSTRAINT IF EXISTS location_region_dual_fk;
ALTER TABLE public.location DROP COLUMN IF EXISTS region_version_id;

-- Restore region: drop version-scoped indexes, restore global UNIQUE on path
DROP INDEX IF EXISTS region_id_version_id_key;
DROP INDEX IF EXISTS region_version_path_key;
DROP INDEX IF EXISTS region_code_version_key;
CREATE UNIQUE INDEX region_code_key ON public.region(code) WHERE code IS NOT NULL;
ALTER TABLE public.region ADD CONSTRAINT region_path_key UNIQUE (path);
ALTER TABLE public.region DROP COLUMN IF EXISTS version_id;

-- Drop region_version table (must be after all FKs removed)
DROP INDEX IF EXISTS region_version_enabled_lasts_to_key;
DROP TABLE IF EXISTS public.region_version;

-- Fix 4: Restore original region_upload_upsert (pre-versioning, uses ON CONFLICT (path))
CREATE OR REPLACE FUNCTION admin.region_upload_upsert()
 RETURNS trigger
 LANGUAGE plpgsql
AS $region_upload_upsert$
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
$region_upload_upsert$;

-- Restore original import.analyse_location (unscoped region lookups)
DO $do$
DECLARE
    v_funcdef TEXT;
    v_new_funcdef TEXT;
    v_func_oid OID;
BEGIN
    v_func_oid := 'import.analyse_location(integer,integer,text)'::regprocedure;
    v_funcdef := pg_get_functiondef(v_func_oid);

    -- Remove version-scoping from region lookups
    v_new_funcdef := replace(v_funcdef,
        'AND r.version_id = (SELECT region_version_id FROM public.settings LIMIT 1)',
        ''
    );

    IF v_new_funcdef IS DISTINCT FROM v_funcdef THEN
        v_new_funcdef := replace(v_new_funcdef, 'CREATE FUNCTION', 'CREATE OR REPLACE FUNCTION');
        v_new_funcdef := replace(v_new_funcdef, 'CREATE PROCEDURE', 'CREATE OR REPLACE PROCEDURE');
        EXECUTE v_new_funcdef;
        RAISE NOTICE 'Restored import.analyse_location with unscoped region lookups';
    END IF;
END;
$do$;

-- Restore original import.process_location (without region_version_id)
DO $do$
DECLARE
    v_funcdef TEXT;
    v_new_funcdef TEXT;
    v_func_oid OID;
BEGIN
    v_func_oid := 'import.process_location(integer,integer,text)'::regprocedure;
    v_funcdef := pg_get_functiondef(v_func_oid);

    -- Remove region_version_id from physical location
    v_new_funcdef := replace(v_funcdef,
        'dt.physical_region_id AS region_id, (SELECT r.version_id FROM public.region r WHERE r.id = dt.physical_region_id) AS region_version_id, dt.physical_country_id AS country_id,',
        'dt.physical_region_id AS region_id, dt.physical_country_id AS country_id,'
    );
    -- Remove region_version_id from postal location
    v_new_funcdef := replace(v_new_funcdef,
        'dt.postal_region_id AS region_id, (SELECT r.version_id FROM public.region r WHERE r.id = dt.postal_region_id) AS region_version_id, dt.postal_country_id AS country_id,',
        'dt.postal_region_id AS region_id, dt.postal_country_id AS country_id,'
    );

    IF v_new_funcdef IS DISTINCT FROM v_funcdef THEN
        v_new_funcdef := replace(v_new_funcdef, 'CREATE FUNCTION', 'CREATE OR REPLACE FUNCTION');
        v_new_funcdef := replace(v_new_funcdef, 'CREATE PROCEDURE', 'CREATE OR REPLACE PROCEDURE');
        EXECUTE v_new_funcdef;
        RAISE NOTICE 'Restored import.process_location without region_version_id';
    END IF;
END;
$do$;

-- Restore reset() to pre-Migration-C version (without region_version handling)
-- This is handled by the down migration for Migration B (20260312114521),
-- which contains the previous version of reset().

END;
