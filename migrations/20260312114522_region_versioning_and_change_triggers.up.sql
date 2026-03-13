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

-- Code must also be unique per version (not globally — allows same region code across versions)
DROP INDEX IF EXISTS public.region_code_key;
CREATE UNIQUE INDEX region_code_version_key ON public.region(version_id, code) WHERE code IS NOT NULL;

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

-- Prevent inconsistent state: region_id and region_version_id must be both NULL or both non-NULL
ALTER TABLE public.location ADD CONSTRAINT location_region_version_consistency
    CHECK ((region_id IS NULL) = (region_version_id IS NULL));

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

-- The reset() function needs a region_version block in the 'getting-started'
-- scope, after both region and settings are deleted.
-- We use CREATE OR REPLACE to update the full function.

CREATE OR REPLACE FUNCTION public.reset(confirmed boolean, scope reset_scope)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $reset$
DECLARE
    result JSONB := '{}'::JSONB;
    changed JSONB;
    _activity_count bigint;
    _location_count bigint;
    _contact_count bigint;
    _person_for_unit_count bigint;
    _person_count bigint;
    _tag_for_unit_count bigint;
    _stat_for_unit_count bigint;
    _external_ident_count bigint;
    _legal_relationship_count bigint;
    _power_root_count bigint;
    _establishment_count bigint;
    _legal_unit_count bigint;
    _enterprise_count bigint;
    _power_group_count bigint;
    _image_count bigint;
    _unit_notes_count bigint;
BEGIN
    IF NOT confirmed THEN
        RAISE EXCEPTION 'Action not confirmed.';
    END IF;

    -- ================================================================
    -- Scope: 'units' (and all broader scopes)
    -- ================================================================

    CASE WHEN scope IN ('units', 'data', 'getting-started', 'all') THEN
        SELECT COUNT(*) FROM public.activity INTO _activity_count;
        SELECT COUNT(*) FROM public.location INTO _location_count;
        SELECT COUNT(*) FROM public.contact INTO _contact_count;
        SELECT COUNT(*) FROM public.person_for_unit INTO _person_for_unit_count;
        SELECT COUNT(*) FROM public.person INTO _person_count;
        SELECT COUNT(*) FROM public.tag_for_unit INTO _tag_for_unit_count;
        SELECT COUNT(*) FROM public.stat_for_unit INTO _stat_for_unit_count;
        SELECT COUNT(*) FROM public.external_ident INTO _external_ident_count;
        SELECT COUNT(*) FROM public.legal_relationship INTO _legal_relationship_count;
        SELECT COUNT(*) FROM public.power_root INTO _power_root_count;
        SELECT COUNT(*) FROM public.establishment INTO _establishment_count;
        SELECT COUNT(*) FROM public.legal_unit INTO _legal_unit_count;
        SELECT COUNT(*) FROM public.enterprise INTO _enterprise_count;
        SELECT COUNT(*) FROM public.power_group INTO _power_group_count;
        SELECT COUNT(*) FROM public.image INTO _image_count;
        SELECT COUNT(*) FROM public.unit_notes INTO _unit_notes_count;

        TRUNCATE
            public.activity,
            public.location,
            public.contact,
            public.stat_for_unit,
            public.external_ident,
            public.person_for_unit,
            public.person,
            public.tag_for_unit,
            public.unit_notes,
            public.legal_relationship,
            public.power_root,
            public.establishment,
            public.legal_unit,
            public.enterprise,
            public.power_group,
            public.image,
            public.timeline_establishment,
            public.timeline_legal_unit,
            public.timeline_enterprise,
            public.timeline_power_group,
            public.timepoints,
            public.timesegments,
            public.timesegments_years,
            public.statistical_unit,
            public.statistical_unit_facet,
            public.statistical_unit_facet_dirty_partitions,
            public.statistical_history,
            public.statistical_history_facet,
            public.statistical_history_facet_partitions;

        result := result
            || jsonb_build_object('activity', jsonb_build_object('deleted_count', _activity_count))
            || jsonb_build_object('location', jsonb_build_object('deleted_count', _location_count))
            || jsonb_build_object('contact', jsonb_build_object('deleted_count', _contact_count))
            || jsonb_build_object('person_for_unit', jsonb_build_object('deleted_count', _person_for_unit_count))
            || jsonb_build_object('person', jsonb_build_object('deleted_count', _person_count))
            || jsonb_build_object('tag_for_unit', jsonb_build_object('deleted_count', _tag_for_unit_count))
            || jsonb_build_object('stat_for_unit', jsonb_build_object('deleted_count', _stat_for_unit_count))
            || jsonb_build_object('external_ident', jsonb_build_object('deleted_count', _external_ident_count))
            || jsonb_build_object('legal_relationship', jsonb_build_object('deleted_count', _legal_relationship_count))
            || jsonb_build_object('power_root', jsonb_build_object('deleted_count', _power_root_count))
            || jsonb_build_object('establishment', jsonb_build_object('deleted_count', _establishment_count))
            || jsonb_build_object('legal_unit', jsonb_build_object('deleted_count', _legal_unit_count))
            || jsonb_build_object('enterprise', jsonb_build_object('deleted_count', _enterprise_count))
            || jsonb_build_object('power_group', jsonb_build_object('deleted_count', _power_group_count))
            || jsonb_build_object('image', jsonb_build_object('deleted_count', _image_count))
            || jsonb_build_object('unit_notes', jsonb_build_object('deleted_count', _unit_notes_count));
    ELSE END CASE;

    -- ================================================================
    -- Scope: 'data' (adds import cleanup)
    -- ================================================================

    CASE WHEN scope IN ('data', 'getting-started', 'all') THEN
        WITH deleted_import_job AS (
            DELETE FROM public.import_job WHERE id > 0 RETURNING *
        )
        SELECT jsonb_build_object(
            'import_job', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_import_job)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    -- ================================================================
    -- Scope: 'getting-started' (adds config/reference cleanup)
    -- ================================================================

    CASE WHEN scope IN ('getting-started', 'all') THEN
        -- Transient: delete custom definitions before data_source due to RESTRICT FK. See doc/data-model.md
        WITH deleted_import_definition AS (
            DELETE FROM public.import_definition WHERE custom RETURNING *
        )
        SELECT jsonb_build_object(
            'import_definition', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_import_definition)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_region AS (
            DELETE FROM public.region WHERE id > 0 RETURNING *
        )
        SELECT jsonb_build_object(
            'region', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_region)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_settings AS (
            DELETE FROM public.settings WHERE only_one_setting = TRUE RETURNING *
        )
        SELECT jsonb_build_object(
            'settings', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_settings)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    -- Fix 1: region_version cleanup (after region and settings are deleted)
    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_rv AS (
            DELETE FROM public.region_version WHERE custom RETURNING *
        ), changed_rv AS (
            UPDATE public.region_version SET enabled = TRUE
             WHERE NOT custom AND NOT enabled RETURNING *
        )
        SELECT jsonb_build_object('region_version', jsonb_build_object(
            'deleted_count', (SELECT COUNT(*) FROM deleted_rv),
            'changed_count', (SELECT COUNT(*) FROM changed_rv)
        )) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH activity_category_to_delete AS (
            SELECT to_delete.id AS id_to_delete
                 , replacement.id AS replacement_id
            FROM public.activity_category AS to_delete
            LEFT JOIN public.activity_category AS replacement
              ON to_delete.path = replacement.path
             AND NOT replacement.custom
            WHERE to_delete.custom
              AND to_delete.enabled
            ORDER BY to_delete.path
        ), updated_child AS (
            UPDATE public.activity_category AS child
               SET parent_id = to_delete.replacement_id
              FROM activity_category_to_delete AS to_delete
               WHERE to_delete.replacement_id IS NOT NULL
                 AND NOT child.custom
                 AND parent_id = to_delete.id_to_delete
            RETURNING *
        ), deleted_activity_category AS (
            DELETE FROM public.activity_category
             WHERE id in (SELECT id_to_delete FROM activity_category_to_delete)
            RETURNING *
        )
        SELECT jsonb_build_object(
            'deleted_count', (SELECT COUNT(*) FROM deleted_activity_category),
            'changed_children_count', (SELECT COUNT(*) FROM updated_child)
        ) INTO changed;

        WITH changed_activity_category AS (
            UPDATE public.activity_category
            SET enabled = TRUE
            WHERE NOT custom
              AND NOT enabled
            RETURNING *
        )
        SELECT changed || jsonb_build_object(
            'changed_count', (SELECT COUNT(*) FROM changed_activity_category)
        ) INTO changed;
        SELECT jsonb_build_object('activity_category', changed) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_sector AS (
            DELETE FROM public.sector WHERE custom RETURNING *
        ), changed_sector AS (
            UPDATE public.sector
               SET enabled = TRUE
             WHERE NOT custom
               AND NOT enabled
             RETURNING *
        )
        SELECT jsonb_build_object(
            'sector', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_sector),
                'changed_count', (SELECT COUNT(*) FROM changed_sector)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_legal_form AS (
            DELETE FROM public.legal_form WHERE custom RETURNING *
        ), changed_legal_form AS (
            UPDATE public.legal_form
               SET enabled = TRUE
             WHERE NOT custom
               AND NOT enabled
             RETURNING *
        )
        SELECT jsonb_build_object(
            'legal_form', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_legal_form),
                'changed_count', (SELECT COUNT(*) FROM changed_legal_form)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_unit_size AS (
            DELETE FROM public.unit_size WHERE custom RETURNING *
        ), changed_unit_size AS (
            UPDATE public.unit_size
               SET enabled = TRUE
             WHERE NOT custom
               AND NOT enabled
             RETURNING *
        )
        SELECT jsonb_build_object(
            'unit_size', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_unit_size),
                'changed_count', (SELECT COUNT(*) FROM changed_unit_size)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_data_source AS (
            DELETE FROM public.data_source WHERE custom RETURNING *
        ), changed_data_source AS (
            UPDATE public.data_source
               SET enabled = TRUE
             WHERE NOT custom
               AND NOT enabled
             RETURNING *
        )
        SELECT jsonb_build_object(
            'data_source', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_data_source),
                'changed_count', (SELECT COUNT(*) FROM changed_data_source)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_status AS (
            DELETE FROM public.status WHERE custom RETURNING *
        ), changed_status AS (
            UPDATE public.status
               SET enabled = TRUE
             WHERE NOT custom
               AND NOT enabled
             RETURNING *
        )
        SELECT jsonb_build_object(
            'status', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_status),
                'changed_count', (SELECT COUNT(*) FROM changed_status)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_foreign_participation AS (
            DELETE FROM public.foreign_participation WHERE custom RETURNING *
        ), changed_foreign_participation AS (
            UPDATE public.foreign_participation
               SET enabled = TRUE
             WHERE NOT custom
               AND NOT enabled
             RETURNING *
        )
        SELECT jsonb_build_object(
            'foreign_participation', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_foreign_participation),
                'changed_count', (SELECT COUNT(*) FROM changed_foreign_participation)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_legal_reorg_type AS (
            DELETE FROM public.legal_reorg_type WHERE custom RETURNING *
        ), changed_legal_reorg_type AS (
            UPDATE public.legal_reorg_type
               SET enabled = TRUE
             WHERE NOT custom
               AND NOT enabled
             RETURNING *
        )
        SELECT jsonb_build_object(
            'legal_reorg_type', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_legal_reorg_type),
                'changed_count', (SELECT COUNT(*) FROM changed_legal_reorg_type)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_power_group_type AS (
            DELETE FROM public.power_group_type WHERE custom RETURNING *
        ), changed_power_group_type AS (
            UPDATE public.power_group_type
               SET enabled = TRUE
             WHERE NOT custom
               AND NOT enabled
             RETURNING *
        )
        SELECT jsonb_build_object(
            'power_group_type', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_power_group_type),
                'changed_count', (SELECT COUNT(*) FROM changed_power_group_type)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_legal_rel_type AS (
            DELETE FROM public.legal_rel_type WHERE custom RETURNING *
        ), changed_legal_rel_type AS (
            UPDATE public.legal_rel_type
               SET enabled = TRUE
             WHERE NOT custom
               AND NOT enabled
             RETURNING *
        )
        SELECT jsonb_build_object(
            'legal_rel_type', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_legal_rel_type),
                'changed_count', (SELECT COUNT(*) FROM changed_legal_rel_type)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    -- ================================================================
    -- Scope: 'all' (adds configuration reset)
    -- ================================================================

    CASE WHEN scope IN ('all') THEN
        WITH deleted_tag AS (
            DELETE FROM public.tag WHERE custom RETURNING *
        ), changed_tag AS (
            UPDATE public.tag
               SET enabled = TRUE
             WHERE NOT custom
               AND NOT enabled
             RETURNING *
        )
        SELECT jsonb_build_object(
            'tag', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_tag),
                'changed_count', (SELECT COUNT(*) FROM changed_tag)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('all') THEN
        WITH deleted_stat_definition AS (
            DELETE FROM public.stat_definition WHERE true RETURNING *
        )
        SELECT jsonb_build_object(
            'stat_definition', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_stat_definition WHERE code NOT IN ('employees','turnover'))
            )
        ) INTO changed;
        result := result || changed;

        INSERT INTO public.stat_definition(code, type, frequency, name, description, priority, enabled)
        VALUES
            ('employees', 'int', 'yearly', 'Employees', 'The number of people receiving an official salary with government reporting.', 1, true),
            ('turnover', 'float', 'yearly', 'Turnover', 'The amount (Local Currency)', 2, true);
    ELSE END CASE;

    CASE WHEN scope IN ('all') THEN
        WITH deleted_external_ident_type AS (
            DELETE FROM public.external_ident_type WHERE true RETURNING *
        )
        SELECT jsonb_build_object(
            'external_ident_type', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_external_ident_type WHERE code NOT IN ('stat_ident','tax_ident'))
            )
        ) INTO changed;
        result := result || changed;

        INSERT INTO public.external_ident_type(code, name, priority, description, enabled)
        VALUES
            ('tax_ident', 'Tax Identifier', 1, 'Stable and country unique identifier used for tax reporting.', true),
            ('stat_ident', 'Statistical Identifier', 2, 'Stable identifier generated by Statbus', true);
    ELSE END CASE;

    RETURN result;
END;
$reset$;

-- ============================================================================
-- 9. Update import.analyse_location for version-scoped region lookups
-- ============================================================================

-- The region lookup in analyse_location uses `SELECT r.id FROM public.region r WHERE r.code = X`
-- which is ambiguous with multiple versions. Scope to settings version.
-- We use the DO-block dynamic replacement approach (same as Migration D section 11)
-- to surgically replace just the region lookup subqueries.

DO $do$
DECLARE
    v_funcdef TEXT;
    v_new_funcdef TEXT;
    v_func_oid OID;
BEGIN
    v_func_oid := 'import.analyse_location(integer,integer,text)'::regprocedure;
    v_funcdef := pg_get_functiondef(v_func_oid);

    -- Replace unscoped region lookups with version-scoped ones
    -- The original: (SELECT r.id FROM public.region r WHERE r.code = bd.physical_region_code_raw)
    -- The new: (SELECT r.id FROM public.region r WHERE r.code = bd.physical_region_code_raw AND r.version_id = (SELECT region_version_id FROM public.settings LIMIT 1))
    v_new_funcdef := replace(v_funcdef,
        '(SELECT r.id FROM public.region r WHERE r.code = bd.physical_region_code_raw)',
        '(SELECT r.id FROM public.region r WHERE r.code = bd.physical_region_code_raw AND r.version_id = (SELECT region_version_id FROM public.settings LIMIT 1))'
    );
    v_new_funcdef := replace(v_new_funcdef,
        '(SELECT r.id FROM public.region r WHERE r.code = bd.postal_region_code_raw)',
        '(SELECT r.id FROM public.region r WHERE r.code = bd.postal_region_code_raw AND r.version_id = (SELECT region_version_id FROM public.settings LIMIT 1))'
    );

    IF v_new_funcdef IS DISTINCT FROM v_funcdef THEN
        v_new_funcdef := replace(v_new_funcdef, 'CREATE FUNCTION', 'CREATE OR REPLACE FUNCTION');
        v_new_funcdef := replace(v_new_funcdef, 'CREATE PROCEDURE', 'CREATE OR REPLACE PROCEDURE');
        EXECUTE v_new_funcdef;
        RAISE NOTICE 'Updated import.analyse_location with version-scoped region lookups';
    ELSE
        RAISE WARNING 'import.analyse_location: expected region lookup patterns not found';
    END IF;
END;
$do$;

-- ============================================================================
-- 10. Update import.process_location to set region_version_id
-- ============================================================================

-- The process_location procedure creates temp views over the data table that
-- select region_id but not region_version_id. We need to add region_version_id
-- so that location rows get the correct version.
-- We use the same DO-block dynamic replacement approach.

DO $do$
DECLARE
    v_funcdef TEXT;
    v_new_funcdef TEXT;
    v_func_oid OID;
BEGIN
    v_func_oid := 'import.process_location(integer,integer,text)'::regprocedure;
    v_funcdef := pg_get_functiondef(v_func_oid);

    -- Add region_version_id derived from region_id for physical location
    v_new_funcdef := replace(v_funcdef,
        'dt.physical_region_id AS region_id, dt.physical_country_id AS country_id,',
        'dt.physical_region_id AS region_id, (SELECT r.version_id FROM public.region r WHERE r.id = dt.physical_region_id) AS region_version_id, dt.physical_country_id AS country_id,'
    );

    -- Add region_version_id derived from region_id for postal location
    v_new_funcdef := replace(v_new_funcdef,
        'dt.postal_region_id AS region_id, dt.postal_country_id AS country_id,',
        'dt.postal_region_id AS region_id, (SELECT r.version_id FROM public.region r WHERE r.id = dt.postal_region_id) AS region_version_id, dt.postal_country_id AS country_id,'
    );

    IF v_new_funcdef IS DISTINCT FROM v_funcdef THEN
        v_new_funcdef := replace(v_new_funcdef, 'CREATE FUNCTION', 'CREATE OR REPLACE FUNCTION');
        v_new_funcdef := replace(v_new_funcdef, 'CREATE PROCEDURE', 'CREATE OR REPLACE PROCEDURE');
        EXECUTE v_new_funcdef;
        RAISE NOTICE 'Updated import.process_location with region_version_id';
    ELSE
        RAISE WARNING 'import.process_location: expected region_id patterns not found';
    END IF;
END;
$do$;

END;
