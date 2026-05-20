-- Migration: differentiate postal vs physical address validation under the two-tier rule.
--
-- Coupled changes (single commit):
--   1. import.analyse_location procedure:
--      a) Country source NULL + address present → default to settings.country_id (no longer
--         fatal). Defaulting is ALWAYS SILENT in both branches. Principle: regions exist only
--         in the domestic country, so a supplied region implies the country; when neither is
--         supplied, the country defaults to domestic and the actually-missing data is the
--         region. The warning lives on the field that is actually missing.
--      b) Country source supplied but invalid + address present → still fatal (both branches).
--      c) Foreign country resolved + region supplied → NEW fatal
--         `{"<branch>_region_code_raw": "Region can only be supplied for the domestic country."}`.
--         Takes precedence over the invalid-region-code soft warning. Symmetric.
--      d) Physical branch: keep `{"physical_region_code_raw": null}` soft warning when region
--         is NULL and country is (resolved or defaulted to) domestic. This is the only signal
--         the procedure emits about region/country missingness in this migration.
--      e) Postal branch: NO domestic-NULL-region warning. Postal addresses do not require a
--         region (the principle). With country defaulting also silent (per (a)), postal stays
--         fully silent for region/country handling.
--      f) Coordinate cast/range checks and `postal_location_has_coordinates_error` untouched.
--      g) The `v_default_country_id` fail-fast guard (no `settings.country_id` configured)
--         remains.
--
--   2. RLS policy `restricted_user_location_access` on public.location:
--      Tolerate NULL `location.region_id` (visible-by-default). Postal addresses with no
--      geographic anchor have nothing to restrict against; the prior policy silently locked
--      restricted users out of any postal-NULL-region row even on units they had access to.
--
--   3. GRANT INSERT, UPDATE, DELETE on public.region_access to admin_user.
--      Latent gap surfaced while writing the RLS test: the table had `FOR ALL TO admin_user
--      USING (true) WITH CHECK (true)` policy but no matching table-level grants, leaving
--      admins unable to manage user-region assignments despite the RLS policy clearance.

BEGIN;

-- ============================================================================
-- 1. import.analyse_location — postal/physical validation differentiation
-- ============================================================================

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
            'physical_latitude_raw', -- Error key for latitude issues
            'physical_longitude_raw', -- Error key for longitude issues
            'physical_altitude_raw' -- Error key for altitude issues
        ];
        v_warning_keys_to_clear_arr := ARRAY['physical_region_code_raw', 'physical_country_iso_2_raw', 'physical_latitude_raw', 'physical_longitude_raw', 'physical_altitude_raw'];
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
            (dt.physical_latitude_raw IS NOT NULL AND l.physical_latitude_error_msg IS NOT NULL) OR
            (dt.physical_longitude_raw IS NOT NULL AND l.physical_longitude_error_msg IS NOT NULL) OR
            (dt.physical_altitude_raw IS NOT NULL AND l.physical_altitude_error_msg IS NOT NULL)
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
            CASE WHEN dt.physical_latitude_raw IS NOT NULL AND l.physical_latitude_error_msg IS NOT NULL THEN jsonb_build_object('physical_latitude_raw', dt.physical_latitude_raw) ELSE '{}'::jsonb END ||
            CASE WHEN dt.physical_longitude_raw IS NOT NULL AND l.physical_longitude_error_msg IS NOT NULL THEN jsonb_build_object('physical_longitude_raw', dt.physical_longitude_raw) ELSE '{}'::jsonb END ||
            CASE WHEN dt.physical_altitude_raw IS NOT NULL AND l.physical_altitude_error_msg IS NOT NULL THEN jsonb_build_object('physical_altitude_raw', dt.physical_altitude_raw) ELSE '{}'::jsonb END
        $$, v_default_country_id, v_address_present_condition_sql);

        -- Coordinate error expressions for physical location
        v_coord_cast_error_json_expr_sql := $$
            jsonb_strip_nulls(
                jsonb_build_object('physical_latitude_raw', l.physical_latitude_error_msg) ||
                jsonb_build_object('physical_longitude_raw', l.physical_longitude_error_msg) ||
                jsonb_build_object('physical_altitude_raw', l.physical_altitude_error_msg)
            )
        $$;
        v_coord_range_error_json_expr_sql := $jsonb_expr$
            jsonb_strip_nulls(
                jsonb_build_object('physical_latitude_raw', CASE WHEN l.resolved_typed_physical_latitude IS NOT NULL AND (l.resolved_typed_physical_latitude < -90 OR l.resolved_typed_physical_latitude > 90) THEN format($$Value %1$s out of range. Expected -90 to 90.$$, l.resolved_typed_physical_latitude::TEXT /* %1$s */) ELSE NULL END) ||
                jsonb_build_object('physical_longitude_raw', CASE WHEN l.resolved_typed_physical_longitude IS NOT NULL AND (l.resolved_typed_physical_longitude < -180 OR l.resolved_typed_physical_longitude > 180) THEN format($$Value %1$s out of range. Expected -180 to 180.$$, l.resolved_typed_physical_longitude::TEXT /* %1$s */) ELSE NULL END) ||
                jsonb_build_object('physical_altitude_raw', CASE WHEN l.resolved_typed_physical_altitude IS NOT NULL AND l.resolved_typed_physical_altitude < 0 THEN format($$Value %1$s cannot be negative. Expected >= 0.$$, l.resolved_typed_physical_altitude::TEXT /* %1$s */) ELSE NULL END)
            )
        $jsonb_expr$;
        v_coord_invalid_value_json_expr_sql := $$
            jsonb_strip_nulls(
                jsonb_build_object('physical_latitude_raw', CASE WHEN (dt.physical_latitude_raw IS NOT NULL AND l.physical_latitude_error_msg IS NOT NULL) OR (l.resolved_typed_physical_latitude IS NOT NULL AND (l.resolved_typed_physical_latitude < -90 OR l.resolved_typed_physical_latitude > 90)) THEN dt.physical_latitude_raw ELSE NULL END) ||
                jsonb_build_object('physical_longitude_raw', CASE WHEN (dt.physical_longitude_raw IS NOT NULL AND l.physical_longitude_error_msg IS NOT NULL) OR (l.resolved_typed_physical_longitude IS NOT NULL AND (l.resolved_typed_physical_longitude < -180 OR l.resolved_typed_physical_longitude > 180)) THEN dt.physical_longitude_raw ELSE NULL END) ||
                jsonb_build_object('physical_altitude_raw', CASE WHEN (dt.physical_altitude_raw IS NOT NULL AND l.physical_altitude_error_msg IS NOT NULL) OR (l.resolved_typed_physical_altitude IS NOT NULL AND l.resolved_typed_physical_altitude < 0) THEN dt.physical_altitude_raw ELSE NULL END)
            )
        $$;
        v_any_coord_error_condition_sql := $$
            (l.physical_latitude_error_msg IS NOT NULL) OR (l.resolved_typed_physical_latitude IS NOT NULL AND (l.resolved_typed_physical_latitude < -90 OR l.resolved_typed_physical_latitude > 90)) OR
            (l.physical_longitude_error_msg IS NOT NULL) OR (l.resolved_typed_physical_longitude IS NOT NULL AND (l.resolved_typed_physical_longitude < -180 OR l.resolved_typed_physical_longitude > 180)) OR
            (l.physical_altitude_error_msg IS NOT NULL) OR (l.resolved_typed_physical_altitude IS NOT NULL AND l.resolved_typed_physical_altitude < 0)
        $$;

    ELSIF p_step_code = 'postal_location' THEN
        v_error_keys_to_clear_arr := ARRAY[
            'postal_region_code_raw',
            'postal_country_iso_2_raw',
            'postal_latitude_raw', -- Error key for latitude issues
            'postal_longitude_raw', -- Error key for longitude issues
            'postal_altitude_raw', -- Error key for altitude issues
            'postal_location_has_coordinates_error' -- Specific error for postal having coords, keep this one
        ];
        v_warning_keys_to_clear_arr := ARRAY['postal_region_code_raw', 'postal_country_iso_2_raw', 'postal_latitude_raw', 'postal_longitude_raw', 'postal_altitude_raw'];
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
            (dt.postal_country_iso_2_raw IS NOT NULL AND l.resolved_postal_country_id IS NULL AND NOT (%2$s)) OR
            (dt.postal_latitude_raw IS NOT NULL AND l.postal_latitude_error_msg IS NOT NULL) OR
            (dt.postal_longitude_raw IS NOT NULL AND l.postal_longitude_error_msg IS NOT NULL) OR
            (dt.postal_altitude_raw IS NOT NULL AND l.postal_altitude_error_msg IS NOT NULL)
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
            CASE WHEN dt.postal_country_iso_2_raw IS NOT NULL AND l.resolved_postal_country_id IS NULL THEN jsonb_build_object('postal_country_iso_2_raw', dt.postal_country_iso_2_raw) ELSE '{}'::jsonb END ||
            CASE WHEN dt.postal_latitude_raw IS NOT NULL AND l.postal_latitude_error_msg IS NOT NULL THEN jsonb_build_object('postal_latitude_raw', dt.postal_latitude_raw) ELSE '{}'::jsonb END ||
            CASE WHEN dt.postal_longitude_raw IS NOT NULL AND l.postal_longitude_error_msg IS NOT NULL THEN jsonb_build_object('postal_longitude_raw', dt.postal_longitude_raw) ELSE '{}'::jsonb END ||
            CASE WHEN dt.postal_altitude_raw IS NOT NULL AND l.postal_altitude_error_msg IS NOT NULL THEN jsonb_build_object('postal_altitude_raw', dt.postal_altitude_raw) ELSE '{}'::jsonb END
        $$, v_default_country_id, v_address_present_condition_sql);

        -- Coordinate error expressions for postal location
        v_coord_cast_error_json_expr_sql := $$
            jsonb_strip_nulls(
                jsonb_build_object('postal_latitude_raw', l.postal_latitude_error_msg) ||
                jsonb_build_object('postal_longitude_raw', l.postal_longitude_error_msg) ||
                jsonb_build_object('postal_altitude_raw', l.postal_altitude_error_msg)
            )
        $$;
        -- Range errors are not applicable here as the primary error is their presence.
        v_coord_range_error_json_expr_sql := $$'{}'::jsonb$$; -- Use SQL literal for empty JSONB.
        v_postal_coord_present_error_json_expr_sql := $$
            jsonb_build_object('postal_location_has_coordinates_error', -- This is a general error, not tied to a specific input coord column.
                CASE WHEN l.resolved_typed_postal_latitude IS NOT NULL OR l.resolved_typed_postal_longitude IS NOT NULL OR l.resolved_typed_postal_altitude IS NOT NULL
                THEN 'Postal locations cannot have coordinates (latitude, longitude, altitude).'
                ELSE NULL END
            )
        $$;
        v_coord_invalid_value_json_expr_sql := $$
            jsonb_strip_nulls(
                jsonb_build_object('postal_latitude_raw', CASE WHEN dt.postal_latitude_raw IS NOT NULL AND (l.postal_latitude_error_msg IS NOT NULL OR l.resolved_typed_postal_latitude IS NOT NULL) THEN dt.postal_latitude_raw ELSE NULL END) || -- Log if provided, regardless of cast success for this error type
                jsonb_build_object('postal_longitude_raw', CASE WHEN dt.postal_longitude_raw IS NOT NULL AND (l.postal_longitude_error_msg IS NOT NULL OR l.resolved_typed_postal_longitude IS NOT NULL) THEN dt.postal_longitude_raw ELSE NULL END) ||
                jsonb_build_object('postal_altitude_raw', CASE WHEN dt.postal_altitude_raw IS NOT NULL AND (l.postal_altitude_error_msg IS NOT NULL OR l.resolved_typed_postal_altitude IS NOT NULL) THEN dt.postal_altitude_raw ELSE NULL END)
            )
        $$;
        v_any_coord_error_condition_sql := $$
            (l.postal_latitude_error_msg IS NOT NULL) OR
            (l.postal_longitude_error_msg IS NOT NULL) OR
            (l.postal_altitude_error_msg IS NOT NULL) OR
            (l.resolved_typed_postal_latitude IS NOT NULL OR l.resolved_typed_postal_longitude IS NOT NULL OR l.resolved_typed_postal_altitude IS NOT NULL) -- This covers the "postal has coords" error
        $$;

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
            dt.physical_latitude_raw, dt.physical_longitude_raw, dt.physical_altitude_raw,
            dt.postal_latitude_raw, dt.postal_longitude_raw, dt.postal_altitude_raw
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
        SELECT physical_latitude_raw AS num_string, 'NUMERIC(9,6)' AS num_type FROM t_batch_data WHERE NULLIF(physical_latitude_raw, '') IS NOT NULL
        UNION SELECT physical_longitude_raw AS num_string, 'NUMERIC(9,6)' AS num_type FROM t_batch_data WHERE NULLIF(physical_longitude_raw, '') IS NOT NULL
        UNION SELECT physical_altitude_raw AS num_string, 'NUMERIC(6,1)' AS num_type FROM t_batch_data WHERE NULLIF(physical_altitude_raw, '') IS NOT NULL
        UNION SELECT postal_latitude_raw AS num_string, 'NUMERIC(9,6)' AS num_type FROM t_batch_data WHERE NULLIF(postal_latitude_raw, '') IS NOT NULL
        UNION SELECT postal_longitude_raw AS num_string, 'NUMERIC(9,6)' AS num_type FROM t_batch_data WHERE NULLIF(postal_longitude_raw, '') IS NOT NULL
        UNION SELECT postal_altitude_raw AS num_string, 'NUMERIC(6,1)' AS num_type FROM t_batch_data WHERE NULLIF(postal_altitude_raw, '') IS NOT NULL
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
                phys_lat.p_value as resolved_typed_physical_latitude,
                phys_lat.p_error_message as physical_latitude_error_msg,
                phys_lon.p_value as resolved_typed_physical_longitude,
                phys_lon.p_error_message as physical_longitude_error_msg,
                phys_alt.p_value as resolved_typed_physical_altitude,
                phys_alt.p_error_message as physical_altitude_error_msg,
                post_lat.p_value as resolved_typed_postal_latitude,
                post_lat.p_error_message as postal_latitude_error_msg,
                post_lon.p_value as resolved_typed_postal_longitude,
                post_lon.p_error_message as postal_longitude_error_msg,
                post_alt.p_value as resolved_typed_postal_altitude,
                post_alt.p_error_message as postal_altitude_error_msg
            FROM t_batch_data bd
            LEFT JOIN t_resolved_codes phys_c ON bd.physical_country_iso_2_raw = phys_c.code AND phys_c.type = 'country'
            LEFT JOIN t_resolved_codes post_c ON bd.postal_country_iso_2_raw = post_c.code AND post_c.type = 'country'
            LEFT JOIN t_resolved_numerics phys_lat ON bd.physical_latitude_raw = phys_lat.num_string AND phys_lat.num_type = 'NUMERIC(9,6)'
            LEFT JOIN t_resolved_numerics phys_lon ON bd.physical_longitude_raw = phys_lon.num_string AND phys_lon.num_type = 'NUMERIC(9,6)'
            LEFT JOIN t_resolved_numerics phys_alt ON bd.physical_altitude_raw = phys_alt.num_string AND phys_alt.num_type = 'NUMERIC(6,1)'
            LEFT JOIN t_resolved_numerics post_lat ON bd.postal_latitude_raw = post_lat.num_string AND post_lat.num_type = 'NUMERIC(9,6)'
            LEFT JOIN t_resolved_numerics post_lon ON bd.postal_longitude_raw = post_lon.num_string AND post_lon.num_type = 'NUMERIC(6,1)'
            LEFT JOIN t_resolved_numerics post_alt ON bd.postal_altitude_raw = post_alt.num_string AND post_alt.num_type = 'NUMERIC(6,1)'
        )
        UPDATE public.%1$I dt SET
            physical_address_part1 = NULLIF(dt.physical_address_part1_raw, ''),
            physical_address_part2 = NULLIF(dt.physical_address_part2_raw, ''),
            physical_address_part3 = NULLIF(dt.physical_address_part3_raw, ''),
            physical_postcode = NULLIF(dt.physical_postcode_raw, ''),
            physical_postplace = NULLIF(dt.physical_postplace_raw, ''),
            physical_region_id = l.resolved_physical_region_id,
            physical_country_id = %15$s,
            physical_latitude = l.resolved_typed_physical_latitude,
            physical_longitude = l.resolved_typed_physical_longitude,
            physical_altitude = l.resolved_typed_physical_altitude,
            postal_address_part1 = NULLIF(dt.postal_address_part1_raw, ''),
            postal_address_part2 = NULLIF(dt.postal_address_part2_raw, ''),
            postal_address_part3 = NULLIF(dt.postal_address_part3_raw, ''),
            postal_postcode = NULLIF(dt.postal_postcode_raw, ''),
            postal_postplace = NULLIF(dt.postal_postplace_raw, ''),
            postal_region_id = l.resolved_postal_region_id,
            postal_country_id = %16$s,
            postal_latitude = l.resolved_typed_postal_latitude,
            postal_longitude = l.resolved_typed_postal_longitude,
            postal_altitude = l.resolved_typed_postal_altitude,
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
$procedure$;

-- ============================================================================
-- 2. RLS policy: tolerate NULL location.region_id (visible-by-default)
-- ============================================================================
--
-- A postal address with no geographic anchor has nothing to restrict against. Restricted
-- users already have unit-level access; hiding location rows from them because they have
-- no region_id leaks the unit's address management out of their view. The previous policy
-- silently denied access in this case — fixed below by treating NULL region as visible.

DROP POLICY restricted_user_location_access ON public.location;
CREATE POLICY restricted_user_location_access ON public.location FOR ALL TO restricted_user
USING (location.region_id IS NULL
       OR EXISTS (SELECT 1 FROM public.region_access AS ra
                  WHERE ra.user_id = auth.uid() AND ra.region_id = location.region_id))
WITH CHECK (location.region_id IS NULL
            OR EXISTS (SELECT 1 FROM public.region_access AS ra
                       WHERE ra.user_id = auth.uid() AND ra.region_id = location.region_id));

-- ============================================================================
-- 3. region_access: grant management privileges to admin_user
-- ============================================================================
--
-- The table had `CREATE POLICY ... FOR ALL TO admin_user USING(true) WITH CHECK(true)`
-- from migration 20240216000000, but no matching table-level GRANT — admin's INSERT/
-- UPDATE/DELETE were rejected with `permission denied for table region_access` despite
-- the policy clearance. Surfaced while writing test 323.

GRANT SELECT, INSERT, UPDATE, DELETE ON public.region_access TO admin_user;

-- ============================================================================
-- 4. location: grant write privileges to restricted_user
-- ============================================================================
--
-- Same gap as #3: `restricted_user_location_access` is `FOR ALL TO restricted_user`
-- (now also visible-by-default for NULL region — see #2), but restricted_user had no
-- table-level INSERT/UPDATE/DELETE grants, so the policy's write clearance was a no-op.
-- Surfaced while writing test 323 as `permission denied for table location` on the
-- UPDATE write probe. The policy's WITH CHECK clause (region_id IS NULL OR EXISTS …)
-- still enforces the geographic restriction at row-write time.

GRANT SELECT, INSERT, UPDATE, DELETE ON public.location TO restricted_user;

-- ============================================================================
-- 5. activity: grant write privileges to restricted_user
-- ============================================================================
--
-- Same gap as #3/#4: `restricted_user_activity_access` (migration 20240606000000) is
-- `FOR ALL TO restricted_user USING (EXISTS activity_category_access …)` but
-- restricted_user had no table-level INSERT/UPDATE/DELETE grants on activity.
-- Surfaced while extending test 323 with activity-side scenarios.

GRANT SELECT, INSERT, UPDATE, DELETE ON public.activity TO restricted_user;

-- ============================================================================
-- 6. activity_category_access: grant management privileges to admin_user
-- ============================================================================
--
-- Same gap as #3: `activity_category_access_admin_policy` (migration 20240113000000)
-- is `FOR ALL TO admin_user USING(true) WITH CHECK(true)` but the table has no
-- table-level GRANT to admin_user — admin's INSERT/UPDATE/DELETE was rejected with
-- `permission denied for table activity_category_access` despite the policy clearance.

GRANT SELECT, INSERT, UPDATE, DELETE ON public.activity_category_access TO admin_user;

-- ============================================================================
-- 7. import_job: defensive GRANT SELECT to notify_reader (already granted by
--    migration 20250814110000; re-asserting here per the operator audit so the
--    grant survives any future re-creation of the table)
-- ============================================================================

GRANT SELECT ON public.import_job TO notify_reader;

-- ============================================================================
-- 8. COMMENT ON ROLE — durable schema documentation for the role graph
-- ============================================================================
--
-- The six roles below carry the security model. Comments here make read-vs-write
-- semantics explicit so a future contributor knows what each role can do without
-- spelunking the policy graph.

-- IMPORTANT model note for the comments below: the statbus role chain is
-- admin_user → regular_user → restricted_user → external_user. None of those
-- roles inherits from `authenticated`. Instead, `user_create()` grants every
-- user-email role membership in `authenticated` IN PARALLEL with their statbus
-- role. So policies on `authenticated` apply to every user, while policies on
-- a statbus role apply only to users granted that tier.
COMMENT ON ROLE admin_user IS
'Top of the statbus role chain (admin → regular → restricted → external). Granted to user-email roles by user_create(). Combined with each user''s parallel authenticated membership, gives full read+write on all public tables via the *_admin_user_manage FOR ALL policies; manages user role assignments, region_access, and activity_category_access.';

COMMENT ON ROLE regular_user IS
'Middle statbus tier (admin → regular → restricted → external). Granted to user-email roles by user_create(). With the parallel authenticated membership, has full read+write on public tables via the *_regular_user_manage FOR ALL policies. Differs from admin_user by lacking role-management privileges (cannot grant/revoke).';

COMMENT ON ROLE restricted_user IS
'Lower statbus tier (admin → regular → restricted → external). Does NOT inherit authenticated; user-email roles are granted authenticated separately by user_create(). Effective access: reads come from the *_authenticated_read policies (FOR SELECT TO authenticated USING true) — broad. Writes are gated per-row by restricted_user_*_access FOR ALL policies: region_access controls location writes (NULL region_id visible-by-default after this RC); activity_category_access controls activity writes. The two grant tables are independent — region_access does NOT gate activity writes.';

COMMENT ON ROLE authenticated IS
'Granted directly to every user-email role by user_create() in parallel with the statbus role. The *_authenticated_read FOR SELECT … USING (true) policies on most public tables apply to anyone holding this membership — i.e. every logged-in user regardless of statbus tier. Not a parent of admin_user / regular_user / restricted_user / external_user in pg_auth_members; users hold both memberships independently.';

COMMENT ON ROLE external_user IS
'Bottom of the statbus role chain (admin → regular → restricted → external). User-email roles assigned external_user are also granted authenticated by user_create(), so they get the *_authenticated_read SELECT policies. No external_user-specific write policies exist today — effectively read-only via the authenticated tier. Reserved for narrow integrations; expanded RLS pending.';

COMMENT ON ROLE anon IS
'Unauthenticated PostgREST role. No authenticated membership and no table-level policies. Reaches the database only via the auth endpoints (login / refresh / etc.) that explicitly grant EXECUTE on auth functions.';

COMMIT;
