BEGIN;

-- ============================================================================
-- Migration C: Region versioning + change triggers
--
-- Region codes change over time (e.g. Norway 2020→2024 reform/reversal).
-- Without versioning, uploading new regions breaks FK constraints and path
-- uniqueness. This migration adds:
--   1. region_version table (version catalog)
--   2. version_id on region (path unique per version)
--   3. region_version_id on location (dual FK to region)
--   4. region_version_id on settings (active version, must be enabled)
--   5. lasts_to on activity_category_standard (forward-compat for ACS versioning)
--   6. Region change trigger for worker pipeline
-- ============================================================================

-- ============================================================================
-- 1. region_version table
-- ============================================================================
CREATE TABLE public.region_version (
    id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code TEXT UNIQUE NOT NULL,           -- 'v2020', 'v2024'
    name TEXT NOT NULL,
    description TEXT,
    lasts_to DATE,                       -- Inclusive end date. NULL = currently active.
    enabled BOOLEAN NOT NULL DEFAULT true,
    custom BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT statement_timestamp(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT statement_timestamp()
);

-- Only one enabled version can be "current" (lasts_to IS NULL).
-- Multiple enabled versions with future lasts_to dates are fine.
CREATE UNIQUE INDEX region_version_enabled_lasts_to_key
    ON public.region_version (lasts_to) NULLS NOT DISTINCT WHERE enabled;

-- RLS and grants (same pattern as other classification tables)
SELECT admin.add_rls_regular_user_can_read('public.region_version'::regclass);

-- ============================================================================
-- 2. region gets version_id
-- ============================================================================

-- Seed initial version before adding NOT NULL column
INSERT INTO public.region_version (code, name, description, lasts_to, enabled, custom)
VALUES ('initial', 'Initial regions', 'Seed version for pre-existing regions', NULL, true, false);

-- Add column as nullable first, backfill, then set NOT NULL
ALTER TABLE public.region ADD COLUMN version_id INTEGER REFERENCES public.region_version(id);
UPDATE public.region SET version_id = (SELECT id FROM public.region_version WHERE code = 'initial');
ALTER TABLE public.region ALTER COLUMN version_id SET NOT NULL;

-- Path must be unique within a version (replaces the old global UNIQUE on path)
ALTER TABLE public.region DROP CONSTRAINT region_path_key;
CREATE UNIQUE INDEX region_version_path_key ON public.region(version_id, path);

-- Support dual FK from location: (id, version_id) must be unique
CREATE UNIQUE INDEX region_id_version_id_key ON public.region(id, version_id);

-- ============================================================================
-- 3. location gets dual FK to region
-- ============================================================================

-- Add region_version_id, backfill from region table
ALTER TABLE public.location ADD COLUMN region_version_id INTEGER REFERENCES public.region_version(id);
UPDATE public.location AS l
   SET region_version_id = r.version_id
  FROM public.region AS r
 WHERE l.region_id = r.id
   AND l.region_id IS NOT NULL;

-- Dual FK: location's (region_id, region_version_id) must reference region's (id, version_id).
-- This ensures location always points to a region in the correct version.
ALTER TABLE public.location ADD CONSTRAINT location_region_dual_fk
    FOREIGN KEY (region_id, region_version_id) REFERENCES public.region(id, version_id);

-- ============================================================================
-- 4. settings gets region_version_id with enabled enforcement
-- ============================================================================

ALTER TABLE public.settings ADD COLUMN region_version_id INTEGER
    REFERENCES public.region_version(id);
UPDATE public.settings
   SET region_version_id = (SELECT id FROM public.region_version WHERE code = 'initial');
ALTER TABLE public.settings ALTER COLUMN region_version_id SET NOT NULL;

-- GENERATED column: always TRUE. Used as FK target to enforce "enabled" on referenced rows.
ALTER TABLE public.settings ADD COLUMN required_to_be_enabled BOOLEAN
    GENERATED ALWAYS AS (true) STORED;

-- Unique indexes on target tables to support dual FK enforcement
CREATE UNIQUE INDEX region_version_id_enabled_key ON public.region_version(id, enabled);
CREATE UNIQUE INDEX activity_category_standard_id_enabled_key ON public.activity_category_standard(id, enabled);

-- Dual FKs: settings can only reference enabled versions/standards
ALTER TABLE public.settings ADD CONSTRAINT settings_region_version_enabled_fk
    FOREIGN KEY (region_version_id, required_to_be_enabled)
    REFERENCES public.region_version(id, enabled);

ALTER TABLE public.settings ADD CONSTRAINT settings_activity_category_standard_enabled_fk
    FOREIGN KEY (activity_category_standard_id, required_to_be_enabled)
    REFERENCES public.activity_category_standard(id, enabled);

-- ============================================================================
-- 5. activity_category_standard gets lasts_to (forward compatibility)
-- ============================================================================

ALTER TABLE public.activity_category_standard ADD COLUMN lasts_to DATE;

-- Note: Unlike region_version, multiple standards can be "current" simultaneously
-- (e.g. ISIC v4 and NACE v2.1), so no UNIQUE constraint on lasts_to here.

-- ============================================================================
-- 6. Region change trigger for worker pipeline
-- ============================================================================

-- When region metadata changes (name, coordinates), find affected units
-- by JOINing through location to find establishments and legal units.
CREATE OR REPLACE FUNCTION worker.log_region_change()
RETURNS trigger
LANGUAGE plpgsql
AS $log_region_change$
DECLARE
    v_est_ids int4multirange;
    v_lu_ids int4multirange;
    v_valid_ranges datemultirange;
    v_source TEXT;
BEGIN
    -- Build source query based on operation
    CASE TG_OP
        WHEN 'INSERT' THEN v_source := 'new_rows';
        WHEN 'DELETE' THEN v_source := 'old_rows';
        WHEN 'UPDATE' THEN v_source := 'old_rows UNION ALL SELECT * FROM new_rows';
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
        format('SELECT * FROM %s', v_source)
    ) INTO v_est_ids, v_lu_ids, v_valid_ranges;

    IF v_est_ids != '{}'::int4multirange
       OR v_lu_ids != '{}'::int4multirange THEN
        INSERT INTO worker.base_change_log (establishment_ids, legal_unit_ids, enterprise_ids, power_group_ids, valid_ranges)
        VALUES (v_est_ids, v_lu_ids, '{}'::int4multirange, '{}'::int4multirange, v_valid_ranges);
    END IF;

    RETURN NULL;
END;
$log_region_change$;

-- Region change-tracking triggers (same pattern as other base tables)
CREATE TRIGGER a_region_log_insert
AFTER INSERT ON public.region
REFERENCING NEW TABLE AS new_rows
FOR EACH STATEMENT EXECUTE FUNCTION worker.log_region_change();

CREATE TRIGGER a_region_log_update
AFTER UPDATE ON public.region
REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows
FOR EACH STATEMENT EXECUTE FUNCTION worker.log_region_change();

CREATE TRIGGER a_region_log_delete
AFTER DELETE ON public.region
REFERENCING OLD TABLE AS old_rows
FOR EACH STATEMENT EXECUTE FUNCTION worker.log_region_change();

CREATE TRIGGER b_region_ensure_collect
AFTER INSERT OR DELETE OR UPDATE ON public.region
FOR EACH STATEMENT EXECUTE FUNCTION worker.ensure_collect_changes();

-- ============================================================================
-- 7. Update region_upload_upsert to use version-scoped uniqueness
-- ============================================================================

-- The old function used ON CONFLICT (path) which relied on the global UNIQUE(path).
-- Now path is unique per version: UNIQUE(version_id, path). The upsert must look up
-- the current region_version_id from settings and include it in INSERT + ON CONFLICT.
CREATE OR REPLACE FUNCTION admin.region_upload_upsert()
 RETURNS trigger
 LANGUAGE plpgsql
AS $region_upload_upsert$
DECLARE
    new_jsonb JSONB := to_jsonb(NEW);
    maybe_parent_id int := NULL;
    v_version_id int;
    row RECORD;
    new_typed RECORD;
    fields_with_error JSONB := '{}'::jsonb;
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
        VALUES (new_typed.path, maybe_parent_id, NEW.name, new_typed.center_latitude, new_typed.center_longitude, new_typed.center_altitude, v_version_id)
        ON CONFLICT (version_id, path)
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

-- ============================================================================
-- 8. Update reset() to handle region_version
-- ============================================================================

-- region_version must be deleted AFTER region (FK dependency) and AFTER settings
-- (settings.region_version_id FK). The existing reset() deletes regions in
-- 'getting-started' scope and settings separately. We add region_version cleanup
-- in the same scope, after both region and settings are deleted.
-- We also need to update the region delete to handle the version FK.

END;
