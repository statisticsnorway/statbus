-- Migration: Integrate power_group into the derive pipeline
-- Power groups get the same treatment as establishment, legal_unit, enterprise:
-- timepoints → timesegments → timeline → statistical_unit → reports → facets
--
-- Pipeline flow after this migration:
-- Import: power_group_link holistic step creates/updates power_group records
-- Analytics: collect_changes → derive_statistical_unit (EST/LU/EN/PG in single pass)
--         → flush_staging → derive_reports (history/facets for all unit types)

BEGIN;

-- ============================================================================
-- SECTION 1: DROP functions whose signatures change (new p_power_group_id_ranges param)
-- ============================================================================

DROP FUNCTION IF EXISTS public.timepoints_calculate(int4multirange, int4multirange, int4multirange);
DROP PROCEDURE IF EXISTS public.timepoints_refresh(int4multirange, int4multirange, int4multirange);
DROP PROCEDURE IF EXISTS public.timesegments_refresh(int4multirange, int4multirange, int4multirange);
DROP PROCEDURE IF EXISTS public.statistical_unit_refresh(int4multirange, int4multirange, int4multirange);
DROP FUNCTION IF EXISTS worker.enqueue_derive_statistical_unit(int4multirange, int4multirange, int4multirange, date, date, bigint);
-- Also drop the 7-param overload from 20260225135926 (CREATE OR REPLACE with extra param
-- created a second overload instead of replacing the 5-param version on master).
DROP FUNCTION IF EXISTS worker.derive_statistical_unit(int4multirange, int4multirange, int4multirange, date, date, bigint, bigint);
DROP FUNCTION IF EXISTS worker.derive_statistical_unit(int4multirange, int4multirange, int4multirange, date, date, bigint);
DROP FUNCTION IF EXISTS worker.derive_power_groups();
DROP FUNCTION IF EXISTS worker.enqueue_derive_power_groups();

-- ============================================================================
-- SECTION 2: New timeline_power_group infrastructure
-- ============================================================================

-- 2a. timeline_power_group_def view
-- Follows timeline_enterprise_def pattern: join timesegments with power_group,
-- aggregate member LU data via power_group_membership + timeline_legal_unit.
CREATE VIEW public.timeline_power_group_def WITH (security_invoker = on) AS
WITH aggregation AS (
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
    ) AS tpg
    LEFT JOIN LATERAL (
        SELECT tlu_inner.legal_unit_id, tlu_inner.enterprise_id,
               tlu_inner.data_source_ids, tlu_inner.data_source_codes,
               tlu_inner.related_establishment_ids, tlu_inner.excluded_establishment_ids, tlu_inner.included_establishment_ids,
               tlu_inner.used_for_counting, tlu_inner.stats_summary
        FROM public.power_group_membership AS pgm
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
        pgplu.physical_latitude, pgplu.physical_longitude, pgplu.physical_altitude,
        pgplu.domestic,
        pgplu.postal_address_part1, pgplu.postal_address_part2, pgplu.postal_address_part3,
        pgplu.postal_postcode, pgplu.postal_postplace,
        pgplu.postal_region_id, pgplu.postal_region_path, pgplu.postal_region_code,
        pgplu.postal_country_id, pgplu.postal_country_iso_2,
        pgplu.postal_latitude, pgplu.postal_longitude, pgplu.postal_altitude,
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
    ) AS tpg
    -- Primary member LU: the root of the hierarchy (power_level = 1)
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
               tlu_p.physical_latitude, tlu_p.physical_longitude, tlu_p.physical_altitude,
               tlu_p.domestic,
               tlu_p.postal_address_part1, tlu_p.postal_address_part2, tlu_p.postal_address_part3,
               tlu_p.postal_postcode, tlu_p.postal_postplace,
               tlu_p.postal_region_id, tlu_p.postal_region_path, tlu_p.postal_region_code,
               tlu_p.postal_country_id, tlu_p.postal_country_iso_2,
               tlu_p.postal_latitude, tlu_p.postal_longitude, tlu_p.postal_altitude,
               tlu_p.web_address, tlu_p.email_address, tlu_p.phone_number,
               tlu_p.landline, tlu_p.mobile_number, tlu_p.fax_number,
               tlu_p.unit_size_id, tlu_p.unit_size_code,
               tlu_p.status_id, tlu_p.status_code,
               tlu_p.last_edit_comment, tlu_p.last_edit_by_user_id, tlu_p.last_edit_at
        FROM public.power_group_membership AS pgm
        JOIN public.timeline_legal_unit AS tlu_p
            ON tlu_p.legal_unit_id = pgm.legal_unit_id
            AND from_until_overlaps(tpg.valid_from, tpg.valid_until, tlu_p.valid_from, tlu_p.valid_until)
        WHERE pgm.power_group_id = tpg.power_group_id
          AND pgm.power_level = 1
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
    b.physical_latitude, b.physical_longitude, b.physical_altitude, b.domestic,
    b.postal_address_part1, b.postal_address_part2, b.postal_address_part3, b.postal_postcode, b.postal_postplace,
    b.postal_region_id, b.postal_region_path, b.postal_region_code, b.postal_country_id, b.postal_country_iso_2,
    b.postal_latitude, b.postal_longitude, b.postal_altitude,
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

-- 2b. timeline_power_group table
CREATE TABLE public.timeline_power_group AS SELECT * FROM public.timeline_power_group_def WHERE FALSE;
ALTER TABLE public.timeline_power_group
    ADD PRIMARY KEY (unit_type, unit_id, valid_from),
    ALTER COLUMN unit_type SET NOT NULL,
    ALTER COLUMN unit_id SET NOT NULL,
    ALTER COLUMN valid_from SET NOT NULL,
    ALTER COLUMN valid_until SET NOT NULL;
CREATE INDEX idx_timeline_power_group_id ON public.timeline_power_group (power_group_id);
CREATE INDEX idx_timeline_power_group_valid ON public.timeline_power_group (valid_from, valid_until);

-- 2c. timeline_power_group_refresh procedure
CREATE PROCEDURE public.timeline_power_group_refresh(IN p_unit_id_ranges int4multirange DEFAULT NULL)
LANGUAGE plpgsql
AS $timeline_power_group_refresh$
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
        INSERT INTO public.timeline_power_group
        SELECT * FROM public.timeline_power_group_def WHERE unit_id = ANY(v_unit_ids);
    END IF;
END;
$timeline_power_group_refresh$;

-- ============================================================================
-- SECTION 3: Recreate functions with new p_power_group_id_ranges parameter
-- ============================================================================

-- 3a. timepoints_calculate - add pg_periods CTE
CREATE FUNCTION public.timepoints_calculate(
    p_establishment_id_ranges int4multirange,
    p_legal_unit_id_ranges int4multirange,
    p_enterprise_id_ranges int4multirange,
    p_power_group_id_ranges int4multirange DEFAULT NULL
)
RETURNS TABLE(unit_type statistical_unit_type, unit_id integer, timepoint date)
LANGUAGE plpgsql STABLE
AS $timepoints_calculate$
DECLARE
    v_es_ids INT[]; v_lu_ids INT[]; v_en_ids INT[]; v_pg_ids INT[];
BEGIN
    IF p_establishment_id_ranges IS NOT NULL THEN v_es_ids := public.int4multirange_to_array(p_establishment_id_ranges); END IF;
    IF p_legal_unit_id_ranges IS NOT NULL THEN v_lu_ids := public.int4multirange_to_array(p_legal_unit_id_ranges); END IF;
    IF p_enterprise_id_ranges IS NOT NULL THEN v_en_ids := public.int4multirange_to_array(p_enterprise_id_ranges); END IF;
    IF p_power_group_id_ranges IS NOT NULL THEN v_pg_ids := public.int4multirange_to_array(p_power_group_id_ranges); END IF;
    RETURN QUERY
    WITH es_periods AS (
        SELECT id AS src_unit_id, valid_from, valid_until FROM public.establishment WHERE v_es_ids IS NULL OR id = ANY(v_es_ids)
        UNION ALL SELECT establishment_id, valid_from, valid_until FROM public.activity WHERE v_es_ids IS NULL OR establishment_id = ANY(v_es_ids)
        UNION ALL SELECT establishment_id, valid_from, valid_until FROM public.location WHERE v_es_ids IS NULL OR establishment_id = ANY(v_es_ids)
        UNION ALL SELECT establishment_id, valid_from, valid_until FROM public.contact WHERE v_es_ids IS NULL OR establishment_id = ANY(v_es_ids)
        UNION ALL SELECT establishment_id, valid_from, valid_until FROM public.stat_for_unit WHERE v_es_ids IS NULL OR establishment_id = ANY(v_es_ids)
        UNION ALL SELECT establishment_id, valid_from, valid_until FROM public.person_for_unit WHERE v_es_ids IS NULL OR establishment_id = ANY(v_es_ids)
    ),
    lu_periods_base AS (
        SELECT id AS src_unit_id, valid_from, valid_until FROM public.legal_unit WHERE v_lu_ids IS NULL OR id = ANY(v_lu_ids)
        UNION ALL SELECT legal_unit_id, valid_from, valid_until FROM public.activity WHERE v_lu_ids IS NULL OR legal_unit_id = ANY(v_lu_ids)
        UNION ALL SELECT legal_unit_id, valid_from, valid_until FROM public.location WHERE v_lu_ids IS NULL OR legal_unit_id = ANY(v_lu_ids)
        UNION ALL SELECT legal_unit_id, valid_from, valid_until FROM public.contact WHERE v_lu_ids IS NULL OR legal_unit_id = ANY(v_lu_ids)
        UNION ALL SELECT legal_unit_id, valid_from, valid_until FROM public.stat_for_unit WHERE v_lu_ids IS NULL OR legal_unit_id = ANY(v_lu_ids)
        UNION ALL SELECT legal_unit_id, valid_from, valid_until FROM public.person_for_unit WHERE v_lu_ids IS NULL OR legal_unit_id = ANY(v_lu_ids)
    ),
    lu_periods_with_children AS (
        SELECT src_unit_id, valid_from, valid_until FROM lu_periods_base
        UNION ALL
        SELECT es.legal_unit_id, GREATEST(p.valid_from, es.valid_from), LEAST(p.valid_until, es.valid_until)
        FROM es_periods AS p JOIN public.establishment AS es ON p.src_unit_id = es.id
        WHERE (v_lu_ids IS NULL OR es.legal_unit_id = ANY(v_lu_ids)) AND from_until_overlaps(p.valid_from, p.valid_until, es.valid_from, es.valid_until)
    ),
    pg_periods AS (
        SELECT lr.power_group_id AS src_unit_id, lower(lr.valid_range) AS valid_from, upper(lr.valid_range) AS valid_until
        FROM public.legal_relationship AS lr
        WHERE lr.power_group_id IS NOT NULL AND (v_pg_ids IS NULL OR lr.power_group_id = ANY(v_pg_ids))
    ),
    all_periods (src_unit_type, src_unit_id, valid_from, valid_until) AS (
        SELECT 'establishment'::public.statistical_unit_type, e.id, GREATEST(p.valid_from, e.valid_from), LEAST(p.valid_until, e.valid_until)
        FROM es_periods p JOIN public.establishment e ON p.src_unit_id = e.id
        WHERE (v_es_ids IS NULL OR e.id = ANY(v_es_ids)) AND from_until_overlaps(p.valid_from, p.valid_until, e.valid_from, e.valid_until)
        UNION ALL
        SELECT 'legal_unit', l.id, GREATEST(p.valid_from, l.valid_from), LEAST(p.valid_until, l.valid_until)
        FROM lu_periods_with_children p JOIN public.legal_unit l ON p.src_unit_id = l.id
        WHERE (v_lu_ids IS NULL OR l.id = ANY(v_lu_ids)) AND from_until_overlaps(p.valid_from, p.valid_until, l.valid_from, l.valid_until)
        UNION ALL
        SELECT 'enterprise', lu.enterprise_id, GREATEST(p.valid_from, lu.valid_from), LEAST(p.valid_until, lu.valid_until)
        FROM lu_periods_with_children p JOIN public.legal_unit lu ON p.src_unit_id = lu.id
        WHERE (v_en_ids IS NULL OR lu.enterprise_id = ANY(v_en_ids)) AND from_until_overlaps(p.valid_from, p.valid_until, lu.valid_from, lu.valid_until)
        UNION ALL
        SELECT 'enterprise', es.enterprise_id, GREATEST(p.valid_from, es.valid_from), LEAST(p.valid_until, es.valid_until)
        FROM es_periods p JOIN public.establishment es ON p.src_unit_id = es.id
        WHERE es.enterprise_id IS NOT NULL AND (v_en_ids IS NULL OR es.enterprise_id = ANY(v_en_ids)) AND from_until_overlaps(p.valid_from, p.valid_until, es.valid_from, es.valid_until)
        UNION ALL
        SELECT 'power_group', pg.id, p.valid_from, p.valid_until
        FROM pg_periods p JOIN public.power_group pg ON p.src_unit_id = pg.id
        WHERE v_pg_ids IS NULL OR pg.id = ANY(v_pg_ids)
    ),
    unpivoted AS (
        SELECT p.src_unit_type, p.src_unit_id, p.valid_from AS timepoint FROM all_periods p WHERE p.valid_from < p.valid_until
        UNION
        SELECT p.src_unit_type, p.src_unit_id, p.valid_until AS timepoint FROM all_periods p WHERE p.valid_from < p.valid_until
    )
    SELECT DISTINCT up.src_unit_type, up.src_unit_id, up.timepoint FROM unpivoted up WHERE up.timepoint IS NOT NULL;
END;
$timepoints_calculate$;

-- 3b. timepoints_refresh - add power_group partial delete
CREATE PROCEDURE public.timepoints_refresh(
    IN p_establishment_id_ranges int4multirange DEFAULT NULL,
    IN p_legal_unit_id_ranges int4multirange DEFAULT NULL,
    IN p_enterprise_id_ranges int4multirange DEFAULT NULL,
    IN p_power_group_id_ranges int4multirange DEFAULT NULL
)
LANGUAGE plpgsql
AS $timepoints_refresh$
DECLARE
    rec RECORD;
    v_en_batch INT[]; v_lu_batch INT[]; v_es_batch INT[];
    v_batch_size INT := 32768;
    v_total_enterprises INT; v_processed_count INT := 0; v_batch_num INT := 0;
    v_batch_start_time timestamptz; v_batch_duration_ms numeric; v_batch_speed numeric;
    v_is_partial_refresh BOOLEAN;
    v_establishment_ids INT[]; v_legal_unit_ids INT[]; v_enterprise_ids INT[]; v_power_group_ids INT[];
BEGIN
    v_is_partial_refresh := (p_establishment_id_ranges IS NOT NULL
                            OR p_legal_unit_id_ranges IS NOT NULL
                            OR p_enterprise_id_ranges IS NOT NULL
                            OR p_power_group_id_ranges IS NOT NULL);
    IF NOT v_is_partial_refresh THEN
        ANALYZE public.establishment, public.legal_unit, public.enterprise, public.activity, public.location, public.contact, public.stat_for_unit, public.person_for_unit;
        CREATE TEMP TABLE timepoints_new (LIKE public.timepoints) ON COMMIT DROP;
        SELECT count(*) INTO v_total_enterprises FROM public.enterprise;
        RAISE DEBUG 'Starting full timepoints refresh for % enterprises in batches of %...', v_total_enterprises, v_batch_size;
        FOR rec IN SELECT id FROM public.enterprise LOOP
            v_en_batch := array_append(v_en_batch, rec.id);
            IF array_length(v_en_batch, 1) >= v_batch_size THEN
                v_batch_start_time := clock_timestamp();
                v_processed_count := v_processed_count + array_length(v_en_batch, 1);
                v_batch_num := v_batch_num + 1;
                v_lu_batch := ARRAY(SELECT id FROM public.legal_unit WHERE enterprise_id = ANY(v_en_batch));
                v_es_batch := ARRAY(SELECT id FROM public.establishment WHERE legal_unit_id = ANY(v_lu_batch) UNION SELECT id FROM public.establishment WHERE enterprise_id = ANY(v_en_batch));
                INSERT INTO timepoints_new SELECT * FROM public.timepoints_calculate(public.array_to_int4multirange(v_es_batch), public.array_to_int4multirange(v_lu_batch), public.array_to_int4multirange(v_en_batch)) ON CONFLICT DO NOTHING;
                v_batch_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_batch_start_time))) * 1000;
                v_batch_speed := v_batch_size / (v_batch_duration_ms / 1000.0);
                RAISE DEBUG 'Timepoints batch %/% done. (% units, % ms, % units/s)', v_batch_num, ceil(v_total_enterprises::decimal / v_batch_size), v_batch_size, round(v_batch_duration_ms), round(v_batch_speed);
                v_en_batch := '{}';
            END IF;
        END LOOP;
        IF array_length(v_en_batch, 1) > 0 THEN
            v_batch_start_time := clock_timestamp();
            v_batch_num := v_batch_num + 1;
            v_lu_batch := ARRAY(SELECT id FROM public.legal_unit WHERE enterprise_id = ANY(v_en_batch));
            v_es_batch := ARRAY(SELECT id FROM public.establishment WHERE legal_unit_id = ANY(v_lu_batch) UNION SELECT id FROM public.establishment WHERE enterprise_id = ANY(v_en_batch));
            INSERT INTO timepoints_new SELECT * FROM public.timepoints_calculate(public.array_to_int4multirange(v_es_batch), public.array_to_int4multirange(v_lu_batch), public.array_to_int4multirange(v_en_batch)) ON CONFLICT DO NOTHING;
            v_batch_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_batch_start_time))) * 1000;
            v_batch_speed := array_length(v_en_batch, 1) / (v_batch_duration_ms / 1000.0);
            RAISE DEBUG 'Timepoints final batch done. (% units, % ms, % units/s)', array_length(v_en_batch, 1), round(v_batch_duration_ms), round(v_batch_speed);
        END IF;
        -- Full refresh for power groups (separate pass, not in enterprise batches)
        INSERT INTO timepoints_new SELECT * FROM public.timepoints_calculate(NULL, NULL, NULL, NULL) WHERE unit_type = 'power_group' ON CONFLICT DO NOTHING;
        RAISE DEBUG 'Populated staging table, now swapping data...';
        TRUNCATE public.timepoints;
        INSERT INTO public.timepoints SELECT DISTINCT * FROM timepoints_new;
        RAISE DEBUG 'Full timepoints refresh complete.';
        ANALYZE public.timepoints;
    ELSE
        RAISE DEBUG 'Starting partial timepoints refresh...';
        IF p_establishment_id_ranges IS NOT NULL THEN
            v_establishment_ids := public.int4multirange_to_array(p_establishment_id_ranges);
            DELETE FROM public.timepoints WHERE unit_type = 'establishment' AND unit_id = ANY(v_establishment_ids);
        END IF;
        IF p_legal_unit_id_ranges IS NOT NULL THEN
            v_legal_unit_ids := public.int4multirange_to_array(p_legal_unit_id_ranges);
            DELETE FROM public.timepoints WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_legal_unit_ids);
        END IF;
        IF p_enterprise_id_ranges IS NOT NULL THEN
            v_enterprise_ids := public.int4multirange_to_array(p_enterprise_id_ranges);
            DELETE FROM public.timepoints WHERE unit_type = 'enterprise' AND unit_id = ANY(v_enterprise_ids);
        END IF;
        IF p_power_group_id_ranges IS NOT NULL THEN
            v_power_group_ids := public.int4multirange_to_array(p_power_group_id_ranges);
            DELETE FROM public.timepoints WHERE unit_type = 'power_group' AND unit_id = ANY(v_power_group_ids);
        END IF;
        INSERT INTO public.timepoints SELECT * FROM public.timepoints_calculate(p_establishment_id_ranges, p_legal_unit_id_ranges, p_enterprise_id_ranges, p_power_group_id_ranges) ON CONFLICT DO NOTHING;
        RAISE DEBUG 'Partial timepoints refresh complete.';
    END IF;
END;
$timepoints_refresh$;

-- 3c. timesegments_refresh - add power_group partial refresh
CREATE PROCEDURE public.timesegments_refresh(
    IN p_establishment_id_ranges int4multirange DEFAULT NULL,
    IN p_legal_unit_id_ranges int4multirange DEFAULT NULL,
    IN p_enterprise_id_ranges int4multirange DEFAULT NULL,
    IN p_power_group_id_ranges int4multirange DEFAULT NULL
)
LANGUAGE plpgsql
AS $timesegments_refresh$
DECLARE
    v_is_partial_refresh BOOLEAN;
    v_establishment_ids INT[]; v_legal_unit_ids INT[]; v_enterprise_ids INT[]; v_power_group_ids INT[];
BEGIN
    v_is_partial_refresh := (p_establishment_id_ranges IS NOT NULL
                            OR p_legal_unit_id_ranges IS NOT NULL
                            OR p_enterprise_id_ranges IS NOT NULL
                            OR p_power_group_id_ranges IS NOT NULL);
    IF NOT v_is_partial_refresh THEN
        ANALYZE public.timepoints;
        DELETE FROM public.timesegments;
        INSERT INTO public.timesegments SELECT * FROM public.timesegments_def;
        ANALYZE public.timesegments;
    ELSE
        IF p_establishment_id_ranges IS NOT NULL THEN
            v_establishment_ids := public.int4multirange_to_array(p_establishment_id_ranges);
            DELETE FROM public.timesegments WHERE unit_type = 'establishment' AND unit_id = ANY(v_establishment_ids);
            INSERT INTO public.timesegments SELECT * FROM public.timesegments_def WHERE unit_type = 'establishment' AND unit_id = ANY(v_establishment_ids);
        END IF;
        IF p_legal_unit_id_ranges IS NOT NULL THEN
            v_legal_unit_ids := public.int4multirange_to_array(p_legal_unit_id_ranges);
            DELETE FROM public.timesegments WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_legal_unit_ids);
            INSERT INTO public.timesegments SELECT * FROM public.timesegments_def WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_legal_unit_ids);
        END IF;
        IF p_enterprise_id_ranges IS NOT NULL THEN
            v_enterprise_ids := public.int4multirange_to_array(p_enterprise_id_ranges);
            DELETE FROM public.timesegments WHERE unit_type = 'enterprise' AND unit_id = ANY(v_enterprise_ids);
            INSERT INTO public.timesegments SELECT * FROM public.timesegments_def WHERE unit_type = 'enterprise' AND unit_id = ANY(v_enterprise_ids);
        END IF;
        IF p_power_group_id_ranges IS NOT NULL THEN
            v_power_group_ids := public.int4multirange_to_array(p_power_group_id_ranges);
            DELETE FROM public.timesegments WHERE unit_type = 'power_group' AND unit_id = ANY(v_power_group_ids);
            INSERT INTO public.timesegments SELECT * FROM public.timesegments_def WHERE unit_type = 'power_group' AND unit_id = ANY(v_power_group_ids);
        END IF;
    END IF;
END;
$timesegments_refresh$;

-- ============================================================================
-- SECTION 4: enqueue_derive_statistical_unit + enqueue_derive_power_groups
-- ============================================================================

-- 4a. enqueue_derive_statistical_unit - add p_power_group_id_ranges
CREATE FUNCTION worker.enqueue_derive_statistical_unit(
    p_establishment_id_ranges int4multirange DEFAULT NULL,
    p_legal_unit_id_ranges int4multirange DEFAULT NULL,
    p_enterprise_id_ranges int4multirange DEFAULT NULL,
    p_power_group_id_ranges int4multirange DEFAULT NULL,
    p_valid_from date DEFAULT NULL,
    p_valid_until date DEFAULT NULL,
    p_round_priority_base bigint DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
AS $enqueue_derive_statistical_unit$
DECLARE
  v_task_id BIGINT;
  v_payload JSONB;
  v_priority BIGINT;
  v_establishment_id_ranges int4multirange := COALESCE(p_establishment_id_ranges, '{}'::int4multirange);
  v_legal_unit_id_ranges int4multirange := COALESCE(p_legal_unit_id_ranges, '{}'::int4multirange);
  v_enterprise_id_ranges int4multirange := COALESCE(p_enterprise_id_ranges, '{}'::int4multirange);
  v_power_group_id_ranges int4multirange := COALESCE(p_power_group_id_ranges, '{}'::int4multirange);
  v_valid_from DATE := COALESCE(p_valid_from, '-infinity'::DATE);
  v_valid_until DATE := COALESCE(p_valid_until, 'infinity'::DATE);
BEGIN
  v_priority := COALESCE(p_round_priority_base, nextval('public.worker_task_priority_seq'));
  v_payload := jsonb_build_object(
    'command', 'derive_statistical_unit',
    'establishment_id_ranges', v_establishment_id_ranges,
    'legal_unit_id_ranges', v_legal_unit_id_ranges,
    'enterprise_id_ranges', v_enterprise_id_ranges,
    'power_group_id_ranges', v_power_group_id_ranges,
    'valid_from', v_valid_from,
    'valid_until', v_valid_until,
    'round_priority_base', v_priority
  );
  INSERT INTO worker.tasks AS t (command, payload, priority)
  VALUES ('derive_statistical_unit', v_payload, v_priority)
  ON CONFLICT (command)
  WHERE command = 'derive_statistical_unit' AND state = 'pending'::worker.task_state
  DO UPDATE SET
    payload = jsonb_build_object(
      'command', 'derive_statistical_unit',
      'establishment_id_ranges', (t.payload->>'establishment_id_ranges')::int4multirange + (EXCLUDED.payload->>'establishment_id_ranges')::int4multirange,
      'legal_unit_id_ranges', (t.payload->>'legal_unit_id_ranges')::int4multirange + (EXCLUDED.payload->>'legal_unit_id_ranges')::int4multirange,
      'enterprise_id_ranges', (t.payload->>'enterprise_id_ranges')::int4multirange + (EXCLUDED.payload->>'enterprise_id_ranges')::int4multirange,
      'power_group_id_ranges', (t.payload->>'power_group_id_ranges')::int4multirange + (EXCLUDED.payload->>'power_group_id_ranges')::int4multirange,
      'valid_from', LEAST((t.payload->>'valid_from')::date, (EXCLUDED.payload->>'valid_from')::date),
      'valid_until', GREATEST((t.payload->>'valid_until')::date, (EXCLUDED.payload->>'valid_until')::date),
      'round_priority_base', LEAST((t.payload->>'round_priority_base')::bigint, (EXCLUDED.payload->>'round_priority_base')::bigint)
    ),
    state = 'pending'::worker.task_state,
    priority = LEAST(t.priority, EXCLUDED.priority),
    processed_at = NULL, error = NULL
  RETURNING id INTO v_task_id;
  PERFORM pg_notify('worker_tasks', 'analytics');
  RETURN v_task_id;
END;
$enqueue_derive_statistical_unit$;

-- 4b. enqueue_derive_power_groups - add round_priority_base + valid dates
CREATE FUNCTION worker.enqueue_derive_power_groups(
    p_round_priority_base bigint DEFAULT NULL,
    p_valid_from date DEFAULT NULL,
    p_valid_until date DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $enqueue_derive_power_groups$
DECLARE
    _task_id BIGINT;
    _priority BIGINT;
    _payload JSONB;
BEGIN
    _priority := COALESCE(p_round_priority_base, nextval('public.worker_task_priority_seq'));
    _payload := jsonb_build_object(
        'command', 'derive_power_groups',
        'round_priority_base', _priority,
        'valid_from', COALESCE(p_valid_from, '-infinity'::date),
        'valid_until', COALESCE(p_valid_until, 'infinity'::date)
    );
    INSERT INTO worker.tasks AS t (command, payload, priority)
    VALUES ('derive_power_groups', _payload, _priority)
    ON CONFLICT (command)
    WHERE command = 'derive_power_groups' AND state = 'pending'::worker.task_state
    DO UPDATE SET
        payload = jsonb_build_object(
            'command', 'derive_power_groups',
            'round_priority_base', LEAST((t.payload->>'round_priority_base')::bigint, (EXCLUDED.payload->>'round_priority_base')::bigint),
            'valid_from', LEAST((t.payload->>'valid_from')::date, (EXCLUDED.payload->>'valid_from')::date),
            'valid_until', GREATEST((t.payload->>'valid_until')::date, (EXCLUDED.payload->>'valid_until')::date)
        ),
        state = 'pending'::worker.task_state,
        priority = LEAST(t.priority, EXCLUDED.priority),
        processed_at = NULL, error = NULL
    RETURNING id INTO _task_id;
    PERFORM pg_notify('worker_tasks', 'analytics');
    RETURN _task_id;
END;
$enqueue_derive_power_groups$;

-- ============================================================================
-- SECTION 5: derive_statistical_unit (function + procedure)
-- ============================================================================

-- 5a. derive_statistical_unit function - single pass for all unit types (EST/LU/EN/PG)
-- Power group records are now created during import (power_group_link step),
-- so the pipeline only needs to derive statistical_unit views — no two-pass needed.
CREATE FUNCTION worker.derive_statistical_unit(
    p_establishment_id_ranges int4multirange DEFAULT NULL,
    p_legal_unit_id_ranges int4multirange DEFAULT NULL,
    p_enterprise_id_ranges int4multirange DEFAULT NULL,
    p_power_group_id_ranges int4multirange DEFAULT NULL,
    p_valid_from date DEFAULT NULL,
    p_valid_until date DEFAULT NULL,
    p_task_id bigint DEFAULT NULL,
    p_round_priority_base bigint DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
AS $derive_statistical_unit$
DECLARE
    v_batch RECORD;
    v_establishment_ids INT[];
    v_legal_unit_ids INT[];
    v_enterprise_ids INT[];
    v_power_group_ids INT[];
    v_batch_count INT := 0;
    v_is_full_refresh BOOLEAN;
    v_child_priority BIGINT;
    v_orphan_enterprise_ids INT[];
    v_orphan_legal_unit_ids INT[];
    v_orphan_establishment_ids INT[];
    v_orphan_power_group_ids INT[];
    -- Unit count accumulators for pipeline progress
    v_enterprise_count INT := 0;
    v_legal_unit_count INT := 0;
    v_establishment_count INT := 0;
    v_power_group_count INT := 0;
BEGIN
    v_is_full_refresh := (p_establishment_id_ranges IS NULL
                         AND p_legal_unit_id_ranges IS NULL
                         AND p_enterprise_id_ranges IS NULL
                         AND p_power_group_id_ranges IS NULL);

    -- Priority for children: use round base if available, otherwise nextval
    v_child_priority := COALESCE(p_round_priority_base, nextval('public.worker_task_priority_seq'));

    IF v_is_full_refresh THEN
        -- Full refresh: spawn batch children (no orphan cleanup needed - covers everything)
        -- No dirty partition tracking needed: full refresh recomputes all partitions
        FOR v_batch IN SELECT * FROM public.get_closed_group_batches(p_target_batch_size := 1000)
        LOOP
            -- Accumulate unit counts
            v_enterprise_count := v_enterprise_count + COALESCE(array_length(v_batch.enterprise_ids, 1), 0);
            v_legal_unit_count := v_legal_unit_count + COALESCE(array_length(v_batch.legal_unit_ids, 1), 0);
            v_establishment_count := v_establishment_count + COALESCE(array_length(v_batch.establishment_ids, 1), 0);

            PERFORM worker.spawn(
                p_command := 'statistical_unit_refresh_batch',
                p_payload := jsonb_build_object(
                    'command', 'statistical_unit_refresh_batch',
                    'batch_seq', v_batch.batch_seq,
                    'enterprise_ids', v_batch.enterprise_ids,
                    'legal_unit_ids', v_batch.legal_unit_ids,
                    'establishment_ids', v_batch.establishment_ids,
                    'valid_from', p_valid_from,
                    'valid_until', p_valid_until
                ),
                p_parent_id := p_task_id,
                p_priority := v_child_priority
            );
            v_batch_count := v_batch_count + 1;
        END LOOP;

        -- Spawn a separate batch for all power groups (not in enterprise connectivity graph)
        v_power_group_count := (SELECT COUNT(*)::int FROM public.power_group);
        IF v_power_group_count > 0 THEN
            PERFORM worker.spawn(
                p_command := 'statistical_unit_refresh_batch',
                p_payload := jsonb_build_object(
                    'command', 'statistical_unit_refresh_batch',
                    'batch_seq', v_batch_count + 1,
                    'power_group_ids', (SELECT COALESCE(array_agg(id), '{}') FROM public.power_group),
                    'valid_from', p_valid_from,
                    'valid_until', p_valid_until
                ),
                p_parent_id := p_task_id,
                p_priority := v_child_priority
            );
            v_batch_count := v_batch_count + 1;
        END IF;
    ELSE
        -- Partial refresh: convert multiranges to arrays
        v_establishment_ids := ARRAY(SELECT generate_series(lower(r), upper(r)-1) FROM unnest(COALESCE(p_establishment_id_ranges, '{}'::int4multirange)) AS t(r));
        v_legal_unit_ids := ARRAY(SELECT generate_series(lower(r), upper(r)-1) FROM unnest(COALESCE(p_legal_unit_id_ranges, '{}'::int4multirange)) AS t(r));
        v_enterprise_ids := ARRAY(SELECT generate_series(lower(r), upper(r)-1) FROM unnest(COALESCE(p_enterprise_id_ranges, '{}'::int4multirange)) AS t(r));
        v_power_group_ids := ARRAY(SELECT generate_series(lower(r), upper(r)-1) FROM unnest(COALESCE(p_power_group_id_ranges, '{}'::int4multirange)) AS t(r));

        -- ORPHAN CLEANUP: Handle deleted entities BEFORE batching
        IF COALESCE(array_length(v_enterprise_ids, 1), 0) > 0 THEN
            v_orphan_enterprise_ids := ARRAY(SELECT id FROM unnest(v_enterprise_ids) AS id EXCEPT SELECT e.id FROM public.enterprise AS e WHERE e.id = ANY(v_enterprise_ids));
            IF COALESCE(array_length(v_orphan_enterprise_ids, 1), 0) > 0 THEN
                RAISE DEBUG 'derive_statistical_unit: Cleaning up % orphan enterprise IDs', array_length(v_orphan_enterprise_ids, 1);
                DELETE FROM public.timepoints WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.timeline_enterprise WHERE enterprise_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
            END IF;
        END IF;
        IF COALESCE(array_length(v_legal_unit_ids, 1), 0) > 0 THEN
            v_orphan_legal_unit_ids := ARRAY(SELECT id FROM unnest(v_legal_unit_ids) AS id EXCEPT SELECT lu.id FROM public.legal_unit AS lu WHERE lu.id = ANY(v_legal_unit_ids));
            IF COALESCE(array_length(v_orphan_legal_unit_ids, 1), 0) > 0 THEN
                RAISE DEBUG 'derive_statistical_unit: Cleaning up % orphan legal_unit IDs', array_length(v_orphan_legal_unit_ids, 1);
                DELETE FROM public.timepoints WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.timeline_legal_unit WHERE legal_unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
            END IF;
        END IF;
        IF COALESCE(array_length(v_establishment_ids, 1), 0) > 0 THEN
            v_orphan_establishment_ids := ARRAY(SELECT id FROM unnest(v_establishment_ids) AS id EXCEPT SELECT es.id FROM public.establishment AS es WHERE es.id = ANY(v_establishment_ids));
            IF COALESCE(array_length(v_orphan_establishment_ids, 1), 0) > 0 THEN
                RAISE DEBUG 'derive_statistical_unit: Cleaning up % orphan establishment IDs', array_length(v_orphan_establishment_ids, 1);
                DELETE FROM public.timepoints WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.timeline_establishment WHERE establishment_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
            END IF;
        END IF;
        IF COALESCE(array_length(v_power_group_ids, 1), 0) > 0 THEN
            v_orphan_power_group_ids := ARRAY(SELECT id FROM unnest(v_power_group_ids) AS id EXCEPT SELECT pg.id FROM public.power_group AS pg WHERE pg.id = ANY(v_power_group_ids));
            IF COALESCE(array_length(v_orphan_power_group_ids, 1), 0) > 0 THEN
                RAISE DEBUG 'derive_statistical_unit: Cleaning up % orphan power_group IDs', array_length(v_orphan_power_group_ids, 1);
                DELETE FROM public.timepoints WHERE unit_type = 'power_group' AND unit_id = ANY(v_orphan_power_group_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'power_group' AND unit_id = ANY(v_orphan_power_group_ids);
                DELETE FROM public.timeline_power_group WHERE power_group_id = ANY(v_orphan_power_group_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'power_group' AND unit_id = ANY(v_orphan_power_group_ids);
            END IF;
        END IF;

        -- BATCHING: EST/LU/EN use closed-group batches
        IF COALESCE(array_length(v_establishment_ids, 1), 0) > 0
           OR COALESCE(array_length(v_legal_unit_ids, 1), 0) > 0
           OR COALESCE(array_length(v_enterprise_ids, 1), 0) > 0 THEN
            IF to_regclass('pg_temp._batches') IS NOT NULL THEN DROP TABLE _batches; END IF;
            CREATE TEMP TABLE _batches ON COMMIT DROP AS
            SELECT * FROM public.get_closed_group_batches(
                p_target_batch_size := 1000,
                p_establishment_ids := NULLIF(v_establishment_ids, '{}'),
                p_legal_unit_ids := NULLIF(v_legal_unit_ids, '{}'),
                p_enterprise_ids := NULLIF(v_enterprise_ids, '{}')
            );
            -- Dirty partition tracking
            INSERT INTO public.statistical_unit_facet_dirty_partitions (partition_seq)
            SELECT DISTINCT public.report_partition_seq(t.unit_type, t.unit_id, (SELECT analytics_partition_count FROM public.settings))
            FROM (
                SELECT 'enterprise'::text AS unit_type, unnest(b.enterprise_ids) AS unit_id FROM _batches AS b
                UNION ALL SELECT 'legal_unit', unnest(b.legal_unit_ids) FROM _batches AS b
                UNION ALL SELECT 'establishment', unnest(b.establishment_ids) FROM _batches AS b
            ) AS t WHERE t.unit_id IS NOT NULL
            ON CONFLICT DO NOTHING;
            RAISE DEBUG 'derive_statistical_unit: Tracked dirty facet partitions for closed group across % batches', (SELECT count(*) FROM _batches);

            -- Spawn batch children and accumulate unit counts
            FOR v_batch IN SELECT * FROM _batches LOOP
                v_enterprise_count := v_enterprise_count + COALESCE(array_length(v_batch.enterprise_ids, 1), 0);
                v_legal_unit_count := v_legal_unit_count + COALESCE(array_length(v_batch.legal_unit_ids, 1), 0);
                v_establishment_count := v_establishment_count + COALESCE(array_length(v_batch.establishment_ids, 1), 0);

                PERFORM worker.spawn(
                    p_command := 'statistical_unit_refresh_batch',
                    p_payload := jsonb_build_object(
                        'command', 'statistical_unit_refresh_batch',
                        'batch_seq', v_batch.batch_seq,
                        'enterprise_ids', v_batch.enterprise_ids,
                        'legal_unit_ids', v_batch.legal_unit_ids,
                        'establishment_ids', v_batch.establishment_ids,
                        'valid_from', p_valid_from,
                        'valid_until', p_valid_until
                    ),
                    p_parent_id := p_task_id,
                    p_priority := v_child_priority
                );
                v_batch_count := v_batch_count + 1;
            END LOOP;
        END IF;

        -- PG batch: single batch with all affected power_group IDs (always, not conditional on two-pass)
        IF COALESCE(array_length(v_power_group_ids, 1), 0) > 0 THEN
            v_power_group_count := array_length(v_power_group_ids, 1);

            -- Dirty partition tracking for PG
            INSERT INTO public.statistical_unit_facet_dirty_partitions (partition_seq)
            SELECT DISTINCT public.report_partition_seq('power_group', pg_id, (SELECT analytics_partition_count FROM public.settings))
            FROM unnest(v_power_group_ids) AS pg_id
            ON CONFLICT DO NOTHING;

            PERFORM worker.spawn(
                p_command := 'statistical_unit_refresh_batch',
                p_payload := jsonb_build_object(
                    'command', 'statistical_unit_refresh_batch',
                    'batch_seq', v_batch_count + 1,
                    'power_group_ids', v_power_group_ids,
                    'valid_from', p_valid_from,
                    'valid_until', p_valid_until
                ),
                p_parent_id := p_task_id,
                p_priority := v_child_priority
            );
            v_batch_count := v_batch_count + 1;
        END IF;
    END IF;

    RAISE DEBUG 'derive_statistical_unit: Spawned % batch children with parent_id %, counts: es=%, lu=%, en=%, pg=%',
        v_batch_count, p_task_id, v_establishment_count, v_legal_unit_count, v_enterprise_count, v_power_group_count;

    -- Create/update Phase 1 row with unit counts
    INSERT INTO worker.pipeline_progress
        (phase, step, total, completed,
         affected_establishment_count, affected_legal_unit_count, affected_enterprise_count,
         affected_power_group_count, updated_at)
    VALUES
        ('is_deriving_statistical_units', 'derive_statistical_unit', 0, 0,
         v_establishment_count, v_legal_unit_count, v_enterprise_count,
         v_power_group_count, clock_timestamp())
    ON CONFLICT (phase) DO UPDATE SET
        affected_establishment_count = EXCLUDED.affected_establishment_count,
        affected_legal_unit_count = EXCLUDED.affected_legal_unit_count,
        affected_enterprise_count = EXCLUDED.affected_enterprise_count,
        affected_power_group_count = EXCLUDED.affected_power_group_count,
        updated_at = EXCLUDED.updated_at;

    -- Pre-create Phase 2 row with counts (pending, visible to user before phase 2 starts)
    INSERT INTO worker.pipeline_progress
        (phase, step, total, completed,
         affected_establishment_count, affected_legal_unit_count, affected_enterprise_count,
         affected_power_group_count, updated_at)
    VALUES
        ('is_deriving_reports', NULL, 0, 0,
         v_establishment_count, v_legal_unit_count, v_enterprise_count,
         v_power_group_count, clock_timestamp())
    ON CONFLICT (phase) DO UPDATE SET
        affected_establishment_count = EXCLUDED.affected_establishment_count,
        affected_legal_unit_count = EXCLUDED.affected_legal_unit_count,
        affected_enterprise_count = EXCLUDED.affected_enterprise_count,
        affected_power_group_count = EXCLUDED.affected_power_group_count,
        updated_at = EXCLUDED.updated_at;

    -- Refresh derived data (used flags)
    PERFORM public.activity_category_used_derive();
    PERFORM public.region_used_derive();
    PERFORM public.sector_used_derive();
    PERFORM public.data_source_used_derive();
    PERFORM public.legal_form_used_derive();
    PERFORM public.country_used_derive();

    -- Pipeline routing: always flush then reports (no more derive_power_groups in pipeline)
    PERFORM worker.enqueue_statistical_unit_flush_staging(
        p_round_priority_base := p_round_priority_base
    );
    RAISE DEBUG 'derive_statistical_unit: Enqueued flush_staging task';
    PERFORM worker.enqueue_derive_reports(
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until,
        p_round_priority_base := p_round_priority_base
    );
    RAISE DEBUG 'derive_statistical_unit: Enqueued derive_reports';
END;
$derive_statistical_unit$;

-- 5b. derive_statistical_unit procedure wrapper - extract PG + round_priority_base from payload
CREATE OR REPLACE PROCEDURE worker.derive_statistical_unit(IN payload jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_establishment_id_ranges int4multirange = (payload->>'establishment_id_ranges')::int4multirange;
    v_legal_unit_id_ranges int4multirange = (payload->>'legal_unit_id_ranges')::int4multirange;
    v_enterprise_id_ranges int4multirange = (payload->>'enterprise_id_ranges')::int4multirange;
    v_power_group_id_ranges int4multirange = (payload->>'power_group_id_ranges')::int4multirange;
    v_valid_from date = (payload->>'valid_from')::date;
    v_valid_until date = (payload->>'valid_until')::date;
    v_round_priority_base bigint = (payload->>'round_priority_base')::bigint;
    v_task_id BIGINT;
BEGIN
    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY processed_at DESC NULLS LAST, id DESC
    LIMIT 1;
    PERFORM worker.derive_statistical_unit(
        p_establishment_id_ranges := v_establishment_id_ranges,
        p_legal_unit_id_ranges := v_legal_unit_id_ranges,
        p_enterprise_id_ranges := v_enterprise_id_ranges,
        p_power_group_id_ranges := v_power_group_id_ranges,
        p_valid_from := v_valid_from,
        p_valid_until := v_valid_until,
        p_task_id := v_task_id,
        p_round_priority_base := v_round_priority_base
    );
END;
$procedure$;

-- ============================================================================
-- SECTION 6: statistical_unit_refresh_batch - add power_group handling
-- ============================================================================

CREATE OR REPLACE PROCEDURE worker.statistical_unit_refresh_batch(IN payload jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_batch_seq INT := (payload->>'batch_seq')::INT;
    v_enterprise_ids INT[];
    v_legal_unit_ids INT[];
    v_establishment_ids INT[];
    v_power_group_ids INT[];
    v_enterprise_id_ranges int4multirange;
    v_legal_unit_id_ranges int4multirange;
    v_establishment_id_ranges int4multirange;
    v_power_group_id_ranges int4multirange;
BEGIN
    IF jsonb_typeof(payload->'enterprise_ids') = 'array' THEN
        SELECT array_agg(value::INT) INTO v_enterprise_ids FROM jsonb_array_elements_text(payload->'enterprise_ids') AS value;
    END IF;
    IF jsonb_typeof(payload->'legal_unit_ids') = 'array' THEN
        SELECT array_agg(value::INT) INTO v_legal_unit_ids FROM jsonb_array_elements_text(payload->'legal_unit_ids') AS value;
    END IF;
    IF jsonb_typeof(payload->'establishment_ids') = 'array' THEN
        SELECT array_agg(value::INT) INTO v_establishment_ids FROM jsonb_array_elements_text(payload->'establishment_ids') AS value;
    END IF;
    IF jsonb_typeof(payload->'power_group_ids') = 'array' THEN
        SELECT array_agg(value::INT) INTO v_power_group_ids FROM jsonb_array_elements_text(payload->'power_group_ids') AS value;
    END IF;

    v_enterprise_id_ranges := public.array_to_int4multirange(v_enterprise_ids);
    v_legal_unit_id_ranges := public.array_to_int4multirange(v_legal_unit_ids);
    v_establishment_id_ranges := public.array_to_int4multirange(v_establishment_ids);
    v_power_group_id_ranges := public.array_to_int4multirange(v_power_group_ids);

    RAISE DEBUG 'Processing batch % with % enterprises, % legal_units, % establishments, % power_groups',
        v_batch_seq,
        COALESCE(array_length(v_enterprise_ids, 1), 0),
        COALESCE(array_length(v_legal_unit_ids, 1), 0),
        COALESCE(array_length(v_establishment_ids, 1), 0),
        COALESCE(array_length(v_power_group_ids, 1), 0);

    -- IMPORTANT: Use COALESCE to pass empty multirange instead of NULL (NULL = full refresh)
    CALL public.timepoints_refresh(
        p_establishment_id_ranges => COALESCE(v_establishment_id_ranges, '{}'::int4multirange),
        p_legal_unit_id_ranges => COALESCE(v_legal_unit_id_ranges, '{}'::int4multirange),
        p_enterprise_id_ranges => COALESCE(v_enterprise_id_ranges, '{}'::int4multirange),
        p_power_group_id_ranges => COALESCE(v_power_group_id_ranges, '{}'::int4multirange)
    );
    CALL public.timesegments_refresh(
        p_establishment_id_ranges => COALESCE(v_establishment_id_ranges, '{}'::int4multirange),
        p_legal_unit_id_ranges => COALESCE(v_legal_unit_id_ranges, '{}'::int4multirange),
        p_enterprise_id_ranges => COALESCE(v_enterprise_id_ranges, '{}'::int4multirange),
        p_power_group_id_ranges => COALESCE(v_power_group_id_ranges, '{}'::int4multirange)
    );
    CALL public.timesegments_years_refresh_concurrent();

    -- Timeline refreshes: skip when no IDs for that unit type
    IF v_establishment_id_ranges IS NOT NULL THEN
        CALL public.timeline_establishment_refresh(p_unit_id_ranges => v_establishment_id_ranges);
    END IF;
    IF v_legal_unit_id_ranges IS NOT NULL THEN
        CALL public.timeline_legal_unit_refresh(p_unit_id_ranges => v_legal_unit_id_ranges);
    END IF;
    IF v_enterprise_id_ranges IS NOT NULL THEN
        CALL public.timeline_enterprise_refresh(p_unit_id_ranges => v_enterprise_id_ranges);
    END IF;
    IF v_power_group_id_ranges IS NOT NULL THEN
        CALL public.timeline_power_group_refresh(p_unit_id_ranges => v_power_group_id_ranges);
    END IF;

    CALL public.statistical_unit_refresh(
        p_establishment_id_ranges => COALESCE(v_establishment_id_ranges, '{}'::int4multirange),
        p_legal_unit_id_ranges => COALESCE(v_legal_unit_id_ranges, '{}'::int4multirange),
        p_enterprise_id_ranges => COALESCE(v_enterprise_id_ranges, '{}'::int4multirange),
        p_power_group_id_ranges => COALESCE(v_power_group_id_ranges, '{}'::int4multirange)
    );
END;
$procedure$;

-- ============================================================================
-- SECTION 7: derive_power_groups - enqueue PG statistical_unit pass at end
-- ============================================================================

CREATE FUNCTION worker.derive_power_groups(
    p_round_priority_base bigint DEFAULT NULL,
    p_valid_from date DEFAULT NULL,
    p_valid_until date DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, worker, pg_temp
AS $derive_power_groups$
DECLARE
    _cluster RECORD;
    _power_group power_group;
    _created_count integer := 0;
    _updated_count integer := 0;
    _linked_count integer := 0;
    _row_count integer;
    _current_user_id integer;
    _affected_pg_ids int4multirange := '{}'::int4multirange;
BEGIN
    RAISE DEBUG '[derive_power_groups] Starting power group derivation';

    -- Disable triggers to prevent re-enqueue loop when we update legal_relationship.power_group_id
    ALTER TABLE public.legal_relationship DISABLE TRIGGER a_legal_relationship_log_insert;
    ALTER TABLE public.legal_relationship DISABLE TRIGGER a_legal_relationship_log_update;
    ALTER TABLE public.legal_relationship DISABLE TRIGGER a_legal_relationship_log_delete;

    SELECT id INTO _current_user_id FROM auth.user WHERE email = session_user OR session_user = 'postgres';
    IF _current_user_id IS NULL THEN
        SELECT id INTO _current_user_id FROM auth.user WHERE role_id = (SELECT id FROM auth.role WHERE name = 'super_user') LIMIT 1;
    END IF;
    IF _current_user_id IS NULL THEN
        RAISE EXCEPTION 'No user found for power group derivation';
    END IF;

    FOR _cluster IN SELECT DISTINCT root_legal_unit_id FROM public.legal_relationship_cluster
    LOOP
        SELECT pg.* INTO _power_group
        FROM public.power_group AS pg
        JOIN public.legal_relationship AS lr ON lr.power_group_id = pg.id
        JOIN public.legal_relationship_cluster AS lrc ON lrc.legal_relationship_id = lr.id
        WHERE lrc.root_legal_unit_id = _cluster.root_legal_unit_id
        LIMIT 1;

        IF NOT FOUND THEN
            INSERT INTO public.power_group (edit_by_user_id) VALUES (_current_user_id) RETURNING * INTO _power_group;
            _created_count := _created_count + 1;
            RAISE DEBUG '[derive_power_groups] Created power_group % for root LU %', _power_group.ident, _cluster.root_legal_unit_id;
        ELSE
            _updated_count := _updated_count + 1;
        END IF;

        -- Track affected power_group IDs for the PG statistical_unit pass
        _affected_pg_ids := _affected_pg_ids + int4range(_power_group.id, _power_group.id, '[]')::int4multirange;

        UPDATE public.legal_relationship AS lr
        SET power_group_id = _power_group.id
        FROM public.legal_relationship_cluster AS lrc
        WHERE lr.id = lrc.legal_relationship_id
          AND lrc.root_legal_unit_id = _cluster.root_legal_unit_id
          AND (lr.power_group_id IS DISTINCT FROM _power_group.id);
        GET DIAGNOSTICS _row_count = ROW_COUNT;
        _linked_count := _linked_count + _row_count;
    END LOOP;

    -- Handle cluster merges
    WITH cluster_sizes AS (
        SELECT lr.power_group_id, COUNT(*) AS rel_count
        FROM public.legal_relationship AS lr WHERE lr.power_group_id IS NOT NULL GROUP BY lr.power_group_id
    ),
    merge_candidates AS (
        SELECT DISTINCT lrc.root_legal_unit_id, lr.power_group_id AS current_pg_id, cs.rel_count
        FROM public.legal_relationship_cluster AS lrc
        JOIN public.legal_relationship AS lr ON lr.id = lrc.legal_relationship_id
        JOIN cluster_sizes AS cs ON cs.power_group_id = lr.power_group_id
        WHERE lr.power_group_id IS NOT NULL
    ),
    clusters_with_multiple_pgs AS (
        SELECT root_legal_unit_id, array_agg(current_pg_id ORDER BY rel_count DESC, current_pg_id) AS pg_ids
        FROM merge_candidates GROUP BY root_legal_unit_id HAVING COUNT(DISTINCT current_pg_id) > 1
    )
    UPDATE public.legal_relationship AS lr
    SET power_group_id = cwmp.pg_ids[1]
    FROM public.legal_relationship_cluster AS lrc
    JOIN clusters_with_multiple_pgs AS cwmp ON cwmp.root_legal_unit_id = lrc.root_legal_unit_id
    WHERE lr.id = lrc.legal_relationship_id AND lr.power_group_id != cwmp.pg_ids[1];
    GET DIAGNOSTICS _row_count = ROW_COUNT;
    IF _row_count > 0 THEN RAISE DEBUG '[derive_power_groups] Merged % relationships into surviving power groups', _row_count; END IF;

    -- Clear power_group_id from non-primary-influencer relationships
    UPDATE public.legal_relationship AS lr SET power_group_id = NULL
    WHERE lr.power_group_id IS NOT NULL AND lr.primary_influencer_only IS NOT TRUE;
    GET DIAGNOSTICS _row_count = ROW_COUNT;
    IF _row_count > 0 THEN RAISE DEBUG '[derive_power_groups] Cleared power_group from % non-primary-influencer relationships', _row_count; END IF;

    RAISE DEBUG '[derive_power_groups] Completed: created=%, updated=%, linked=%', _created_count, _updated_count, _linked_count;

    -- Re-enable triggers
    ALTER TABLE public.legal_relationship ENABLE TRIGGER a_legal_relationship_log_insert;
    ALTER TABLE public.legal_relationship ENABLE TRIGGER a_legal_relationship_log_update;
    ALTER TABLE public.legal_relationship ENABLE TRIGGER a_legal_relationship_log_delete;

    -- Enqueue derive_statistical_unit for affected power groups (PG pass)
    IF _affected_pg_ids != '{}'::int4multirange THEN
        PERFORM worker.enqueue_derive_statistical_unit(
            p_power_group_id_ranges := _affected_pg_ids,
            p_valid_from := p_valid_from,
            p_valid_until := p_valid_until,
            p_round_priority_base := p_round_priority_base
        );
        RAISE DEBUG '[derive_power_groups] Enqueued derive_statistical_unit for % power groups', _affected_pg_ids;
    ELSE
        -- No power groups affected: flush staging then derive_reports
        PERFORM worker.enqueue_statistical_unit_flush_staging(
            p_round_priority_base := p_round_priority_base
        );
        PERFORM worker.enqueue_derive_reports(
            p_valid_from := p_valid_from,
            p_valid_until := p_valid_until,
            p_round_priority_base := p_round_priority_base
        );
        RAISE DEBUG '[derive_power_groups] No power groups affected, enqueued flush_staging + derive_reports';
    END IF;
END;
$derive_power_groups$;

-- derive_power_groups procedure wrapper - extract params from payload
CREATE OR REPLACE PROCEDURE worker.derive_power_groups(payload JSONB)
SECURITY DEFINER
SET search_path = public, worker, pg_temp
LANGUAGE plpgsql
AS $procedure$
BEGIN
    PERFORM worker.derive_power_groups(
        p_round_priority_base := (payload->>'round_priority_base')::bigint,
        p_valid_from := (payload->>'valid_from')::date,
        p_valid_until := (payload->>'valid_until')::date
    );
END;
$procedure$;

-- ============================================================================
-- SECTION 8: statistical_unit_refresh - add power_group handling
-- ============================================================================

CREATE PROCEDURE public.statistical_unit_refresh(
    IN p_establishment_id_ranges int4multirange DEFAULT NULL,
    IN p_legal_unit_id_ranges int4multirange DEFAULT NULL,
    IN p_enterprise_id_ranges int4multirange DEFAULT NULL,
    IN p_power_group_id_ranges int4multirange DEFAULT NULL
)
LANGUAGE plpgsql
AS $statistical_unit_refresh$
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
        physical_latitude, physical_longitude, physical_altitude, domestic,
        postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace,
        postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2,
        postal_latitude, postal_longitude, postal_altitude,
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

        TRUNCATE public.statistical_unit;
        EXECUTE format('INSERT INTO public.statistical_unit (%s) SELECT %s FROM statistical_unit_new', v_col_list, v_col_list);
        ANALYZE public.statistical_unit;
    ELSE
        -- Partial refresh: Write to staging table
        IF p_establishment_id_ranges IS NOT NULL THEN
            DELETE FROM public.statistical_unit_staging WHERE unit_type = 'establishment' AND unit_id <@ p_establishment_id_ranges;
            EXECUTE format('INSERT INTO public.statistical_unit_staging (%s) SELECT %s FROM import.get_statistical_unit_data_partial(%L, %L::int4multirange)', v_col_list, v_col_list, 'establishment', p_establishment_id_ranges::text);
        END IF;
        IF p_legal_unit_id_ranges IS NOT NULL THEN
            DELETE FROM public.statistical_unit_staging WHERE unit_type = 'legal_unit' AND unit_id <@ p_legal_unit_id_ranges;
            EXECUTE format('INSERT INTO public.statistical_unit_staging (%s) SELECT %s FROM import.get_statistical_unit_data_partial(%L, %L::int4multirange)', v_col_list, v_col_list, 'legal_unit', p_legal_unit_id_ranges::text);
        END IF;
        IF p_enterprise_id_ranges IS NOT NULL THEN
            DELETE FROM public.statistical_unit_staging WHERE unit_type = 'enterprise' AND unit_id <@ p_enterprise_id_ranges;
            EXECUTE format('INSERT INTO public.statistical_unit_staging (%s) SELECT %s FROM import.get_statistical_unit_data_partial(%L, %L::int4multirange)', v_col_list, v_col_list, 'enterprise', p_enterprise_id_ranges::text);
        END IF;
        IF p_power_group_id_ranges IS NOT NULL THEN
            DELETE FROM public.statistical_unit_staging WHERE unit_type = 'power_group' AND unit_id <@ p_power_group_id_ranges;
            EXECUTE format('INSERT INTO public.statistical_unit_staging (%s) SELECT %s FROM import.get_statistical_unit_data_partial(%L, %L::int4multirange)', v_col_list, v_col_list, 'power_group', p_power_group_id_ranges::text);
        END IF;
    END IF;
END;
$statistical_unit_refresh$;

-- ============================================================================
-- SECTION 9: statistical_unit_def view - add power_group UNION branch
-- ============================================================================

CREATE OR REPLACE VIEW public.statistical_unit_def WITH (security_invoker = on) AS
WITH external_idents_agg AS (
    SELECT all_idents.unit_type, all_idents.unit_id,
           jsonb_object_agg(all_idents.type_code, all_idents.ident) AS external_idents
    FROM (
        SELECT 'establishment'::statistical_unit_type AS unit_type, ei.establishment_id AS unit_id, eit.code AS type_code, COALESCE(ei.ident, ei.idents::text::character varying) AS ident FROM external_ident ei JOIN external_ident_type eit ON ei.type_id = eit.id WHERE ei.establishment_id IS NOT NULL
        UNION ALL
        SELECT 'legal_unit', ei.legal_unit_id, eit.code, COALESCE(ei.ident, ei.idents::text::character varying) FROM external_ident ei JOIN external_ident_type eit ON ei.type_id = eit.id WHERE ei.legal_unit_id IS NOT NULL
        UNION ALL
        SELECT 'enterprise', ei.enterprise_id, eit.code, COALESCE(ei.ident, ei.idents::text::character varying) FROM external_ident ei JOIN external_ident_type eit ON ei.type_id = eit.id WHERE ei.enterprise_id IS NOT NULL
        UNION ALL
        SELECT 'power_group', ei.power_group_id, eit.code, COALESCE(ei.ident, ei.idents::text::character varying) FROM external_ident ei JOIN external_ident_type eit ON ei.type_id = eit.id WHERE ei.power_group_id IS NOT NULL
    ) all_idents
    GROUP BY all_idents.unit_type, all_idents.unit_id
),
tag_paths_agg AS (
    SELECT all_tags.unit_type, all_tags.unit_id,
           array_agg(all_tags.path ORDER BY all_tags.path) AS tag_paths
    FROM (
        SELECT 'establishment'::statistical_unit_type AS unit_type, tfu.establishment_id AS unit_id, t.path FROM tag_for_unit tfu JOIN tag t ON tfu.tag_id = t.id WHERE tfu.establishment_id IS NOT NULL
        UNION ALL
        SELECT 'legal_unit', tfu.legal_unit_id, t.path FROM tag_for_unit tfu JOIN tag t ON tfu.tag_id = t.id WHERE tfu.legal_unit_id IS NOT NULL
        UNION ALL
        SELECT 'enterprise', tfu.enterprise_id, t.path FROM tag_for_unit tfu JOIN tag t ON tfu.tag_id = t.id WHERE tfu.enterprise_id IS NOT NULL
        UNION ALL
        SELECT 'power_group', tfu.power_group_id, t.path FROM tag_for_unit tfu JOIN tag t ON tfu.tag_id = t.id WHERE tfu.power_group_id IS NOT NULL
    ) all_tags
    GROUP BY all_tags.unit_type, all_tags.unit_id
),
data AS (
    SELECT unit_type, unit_id, valid_from, valid_to, valid_until, name, birth_date, death_date, search,
        primary_activity_category_id, primary_activity_category_path, primary_activity_category_code,
        secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code,
        activity_category_paths, sector_id, sector_path, sector_code, sector_name,
        data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name,
        physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace,
        physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2,
        physical_latitude, physical_longitude, physical_altitude, domestic,
        postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace,
        postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2,
        postal_latitude, postal_longitude, postal_altitude,
        web_address, email_address, phone_number, landline, mobile_number, fax_number,
        unit_size_id, unit_size_code, status_id, status_code, used_for_counting,
        last_edit_comment, last_edit_by_user_id, last_edit_at, has_legal_unit,
        related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
        related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
        related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
        stats, stats_summary,
        NULL::integer AS primary_establishment_id, NULL::integer AS primary_legal_unit_id
    FROM timeline_establishment
    UNION ALL
    SELECT unit_type, unit_id, valid_from, valid_to, valid_until, name, birth_date, death_date, search,
        primary_activity_category_id, primary_activity_category_path, primary_activity_category_code,
        secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code,
        activity_category_paths, sector_id, sector_path, sector_code, sector_name,
        data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name,
        physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace,
        physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2,
        physical_latitude, physical_longitude, physical_altitude, domestic,
        postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace,
        postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2,
        postal_latitude, postal_longitude, postal_altitude,
        web_address, email_address, phone_number, landline, mobile_number, fax_number,
        unit_size_id, unit_size_code, status_id, status_code, used_for_counting,
        last_edit_comment, last_edit_by_user_id, last_edit_at, has_legal_unit,
        related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
        related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
        related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
        NULL::jsonb AS stats, stats_summary,
        NULL::integer AS primary_establishment_id, NULL::integer AS primary_legal_unit_id
    FROM timeline_legal_unit
    UNION ALL
    SELECT unit_type, unit_id, valid_from, valid_to, valid_until, name, birth_date, death_date, search,
        primary_activity_category_id, primary_activity_category_path, primary_activity_category_code,
        secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code,
        activity_category_paths, sector_id, sector_path, sector_code, sector_name,
        data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name,
        physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace,
        physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2,
        physical_latitude, physical_longitude, physical_altitude, domestic,
        postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace,
        postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2,
        postal_latitude, postal_longitude, postal_altitude,
        web_address, email_address, phone_number, landline, mobile_number, fax_number,
        unit_size_id, unit_size_code, status_id, status_code, used_for_counting,
        last_edit_comment, last_edit_by_user_id, last_edit_at, has_legal_unit,
        related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
        related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
        related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
        NULL::jsonb AS stats, stats_summary,
        primary_establishment_id, primary_legal_unit_id
    FROM timeline_enterprise
    UNION ALL
    -- Power group branch (new)
    SELECT unit_type, unit_id, valid_from, valid_to, valid_until, name, birth_date, death_date, search,
        primary_activity_category_id, primary_activity_category_path, primary_activity_category_code,
        secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code,
        activity_category_paths, sector_id, sector_path, sector_code, sector_name,
        data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name,
        physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace,
        physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2,
        physical_latitude, physical_longitude, physical_altitude, domestic,
        postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace,
        postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2,
        postal_latitude, postal_longitude, postal_altitude,
        web_address, email_address, phone_number, landline, mobile_number, fax_number,
        unit_size_id, unit_size_code, status_id, status_code, used_for_counting,
        last_edit_comment, last_edit_by_user_id, last_edit_at, has_legal_unit,
        related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
        related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
        related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
        NULL::jsonb AS stats, stats_summary,
        NULL::integer AS primary_establishment_id, primary_legal_unit_id
    FROM timeline_power_group
)
SELECT data.unit_type, data.unit_id, data.valid_from, data.valid_to, data.valid_until,
    COALESCE(eia1.external_idents, eia2.external_idents, eia3.external_idents, '{}'::jsonb) AS external_idents,
    data.name, data.birth_date, data.death_date, data.search,
    data.primary_activity_category_id, data.primary_activity_category_path, data.primary_activity_category_code,
    data.secondary_activity_category_id, data.secondary_activity_category_path, data.secondary_activity_category_code,
    data.activity_category_paths, data.sector_id, data.sector_path, data.sector_code, data.sector_name,
    data.data_source_ids, data.data_source_codes, data.legal_form_id, data.legal_form_code, data.legal_form_name,
    data.physical_address_part1, data.physical_address_part2, data.physical_address_part3, data.physical_postcode, data.physical_postplace,
    data.physical_region_id, data.physical_region_path, data.physical_region_code, data.physical_country_id, data.physical_country_iso_2,
    data.physical_latitude, data.physical_longitude, data.physical_altitude, data.domestic,
    data.postal_address_part1, data.postal_address_part2, data.postal_address_part3, data.postal_postcode, data.postal_postplace,
    data.postal_region_id, data.postal_region_path, data.postal_region_code, data.postal_country_id, data.postal_country_iso_2,
    data.postal_latitude, data.postal_longitude, data.postal_altitude,
    data.web_address, data.email_address, data.phone_number, data.landline, data.mobile_number, data.fax_number,
    data.unit_size_id, data.unit_size_code, data.status_id, data.status_code, data.used_for_counting,
    data.last_edit_comment, data.last_edit_by_user_id, data.last_edit_at, data.has_legal_unit,
    data.related_establishment_ids, data.excluded_establishment_ids, data.included_establishment_ids,
    data.related_legal_unit_ids, data.excluded_legal_unit_ids, data.included_legal_unit_ids,
    data.related_enterprise_ids, data.excluded_enterprise_ids, data.included_enterprise_ids,
    data.stats, data.stats_summary,
    array_length(data.included_establishment_ids, 1) AS included_establishment_count,
    array_length(data.included_legal_unit_ids, 1) AS included_legal_unit_count,
    array_length(data.included_enterprise_ids, 1) AS included_enterprise_count,
    COALESCE(tpa.tag_paths, ARRAY[]::ltree[]) AS tag_paths
FROM data
LEFT JOIN external_idents_agg eia1 ON eia1.unit_type = data.unit_type AND eia1.unit_id = data.unit_id
LEFT JOIN external_idents_agg eia2 ON eia2.unit_type = 'establishment'::statistical_unit_type AND eia2.unit_id = data.primary_establishment_id
LEFT JOIN external_idents_agg eia3 ON eia3.unit_type = 'legal_unit'::statistical_unit_type AND eia3.unit_id = data.primary_legal_unit_id
LEFT JOIN tag_paths_agg tpa ON tpa.unit_type = data.unit_type AND tpa.unit_id = data.unit_id;

-- ============================================================================
-- SECTION 10: log_base_change - handle legal_relationship
-- ============================================================================

CREATE OR REPLACE FUNCTION worker.log_base_change()
RETURNS trigger
LANGUAGE plpgsql
AS $log_base_change$
DECLARE
    v_columns TEXT;
    v_has_valid_range BOOLEAN;
    v_source TEXT;
    v_est_ids int4multirange;
    v_lu_ids int4multirange;
    v_ent_ids int4multirange;
    v_valid_range datemultirange;
BEGIN
    CASE TG_TABLE_NAME
        WHEN 'establishment' THEN
            v_columns := 'id AS est_id, legal_unit_id AS lu_id, enterprise_id AS ent_id';
            v_has_valid_range := TRUE;
        WHEN 'legal_unit' THEN
            v_columns := 'NULL::INT AS est_id, id AS lu_id, enterprise_id AS ent_id';
            v_has_valid_range := TRUE;
        WHEN 'enterprise' THEN
            v_columns := 'NULL::INT AS est_id, NULL::INT AS lu_id, id AS ent_id';
            v_has_valid_range := FALSE;
        WHEN 'activity', 'location', 'contact', 'stat_for_unit' THEN
            v_columns := 'establishment_id AS est_id, legal_unit_id AS lu_id, NULL::INT AS ent_id';
            v_has_valid_range := TRUE;
        WHEN 'external_ident' THEN
            v_columns := 'establishment_id AS est_id, legal_unit_id AS lu_id, enterprise_id AS ent_id';
            v_has_valid_range := FALSE;
        WHEN 'legal_relationship' THEN
            -- Special: two LU references per row, capture both influencing and influenced
            v_columns := 'NULL::INT AS est_id, influencing_id AS lu_id, NULL::INT AS ent_id';
            v_has_valid_range := TRUE;
        ELSE
            RAISE EXCEPTION 'log_base_change: unsupported table %', TG_TABLE_NAME;
    END CASE;

    IF v_has_valid_range THEN
        v_columns := v_columns || ', valid_range';
    ELSE
        v_columns := v_columns || ', NULL::daterange AS valid_range';
    END IF;

    CASE TG_OP
        WHEN 'INSERT' THEN v_source := format('SELECT %s FROM new_rows', v_columns);
        WHEN 'DELETE' THEN v_source := format('SELECT %s FROM old_rows', v_columns);
        WHEN 'UPDATE' THEN v_source := format('SELECT %s FROM old_rows UNION ALL SELECT %s FROM new_rows', v_columns, v_columns);
        ELSE RAISE EXCEPTION 'log_base_change: unsupported operation %', TG_OP;
    END CASE;

    -- For legal_relationship, also capture the influenced_id
    IF TG_TABLE_NAME = 'legal_relationship' THEN
        CASE TG_OP
            WHEN 'INSERT' THEN v_source := v_source || ' UNION ALL SELECT NULL::INT, influenced_id, NULL::INT, valid_range FROM new_rows';
            WHEN 'DELETE' THEN v_source := v_source || ' UNION ALL SELECT NULL::INT, influenced_id, NULL::INT, valid_range FROM old_rows';
            WHEN 'UPDATE' THEN v_source := v_source || ' UNION ALL SELECT NULL::INT, influenced_id, NULL::INT, valid_range FROM old_rows UNION ALL SELECT NULL::INT, influenced_id, NULL::INT, valid_range FROM new_rows';
        END CASE;
    END IF;

    EXECUTE format(
        'SELECT COALESCE(range_agg(int4range(est_id, est_id, %1$L)) FILTER (WHERE est_id IS NOT NULL), %2$L::int4multirange),
                COALESCE(range_agg(int4range(lu_id, lu_id, %1$L)) FILTER (WHERE lu_id IS NOT NULL), %2$L::int4multirange),
                COALESCE(range_agg(int4range(ent_id, ent_id, %1$L)) FILTER (WHERE ent_id IS NOT NULL), %2$L::int4multirange),
                COALESCE(range_agg(valid_range) FILTER (WHERE valid_range IS NOT NULL), %3$L::datemultirange)
         FROM (%s) AS mapped',
        '[]', '{}', '{}', v_source
    ) INTO v_est_ids, v_lu_ids, v_ent_ids, v_valid_range;

    IF v_est_ids != '{}'::int4multirange OR v_lu_ids != '{}'::int4multirange OR v_ent_ids != '{}'::int4multirange THEN
        INSERT INTO worker.base_change_log (establishment_ids, legal_unit_ids, enterprise_ids, edited_by_valid_range)
        VALUES (v_est_ids, v_lu_ids, v_ent_ids, v_valid_range);
    END IF;

    RETURN NULL;
END;
$log_base_change$;

-- ============================================================================
-- SECTION 11: Trigger changes - replace legal_relationship trigger
-- ============================================================================

-- Drop old trigger that directly enqueued derive_power_groups
DROP TRIGGER IF EXISTS legal_relationship_derive_power_groups_trigger ON public.legal_relationship;
DROP FUNCTION IF EXISTS public.legal_relationship_queue_derive_power_groups();

-- Add log_base_change triggers on legal_relationship (same pattern as other tables)
-- Each event needs its own trigger because transition tables can't span multiple events.
CREATE TRIGGER a_legal_relationship_log_insert
AFTER INSERT ON public.legal_relationship
REFERENCING NEW TABLE AS new_rows
FOR EACH STATEMENT EXECUTE FUNCTION worker.log_base_change();

CREATE TRIGGER a_legal_relationship_log_update
AFTER UPDATE ON public.legal_relationship
REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows
FOR EACH STATEMENT EXECUTE FUNCTION worker.log_base_change();

CREATE TRIGGER a_legal_relationship_log_delete
AFTER DELETE ON public.legal_relationship
REFERENCING OLD TABLE AS old_rows
FOR EACH STATEMENT EXECUTE FUNCTION worker.log_base_change();

-- ============================================================================
-- SECTION 12: get_statistical_unit_data_partial - add power_group branch
-- ============================================================================

CREATE OR REPLACE FUNCTION import.get_statistical_unit_data_partial(p_unit_type statistical_unit_type, p_id_ranges int4multirange)
RETURNS SETOF statistical_unit
LANGUAGE plpgsql STABLE
AS $get_statistical_unit_data_partial$
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
            t.physical_latitude, t.physical_longitude, t.physical_altitude, t.domestic,
            t.postal_address_part1, t.postal_address_part2, t.postal_address_part3, t.postal_postcode, t.postal_postplace,
            t.postal_region_id, t.postal_region_path, t.postal_region_code, t.postal_country_id, t.postal_country_iso_2,
            t.postal_latitude, t.postal_longitude, t.postal_altitude,
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
            public.report_partition_seq(t.unit_type, t.unit_id, (SELECT analytics_partition_count FROM public.settings)) AS report_partition_seq
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
            t.physical_latitude, t.physical_longitude, t.physical_altitude, t.domestic,
            t.postal_address_part1, t.postal_address_part2, t.postal_address_part3, t.postal_postcode, t.postal_postplace,
            t.postal_region_id, t.postal_region_path, t.postal_region_code, t.postal_country_id, t.postal_country_iso_2,
            t.postal_latitude, t.postal_longitude, t.postal_altitude,
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
            public.report_partition_seq(t.unit_type, t.unit_id, (SELECT analytics_partition_count FROM public.settings)) AS report_partition_seq
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
            t.physical_latitude, t.physical_longitude, t.physical_altitude, t.domestic,
            t.postal_address_part1, t.postal_address_part2, t.postal_address_part3, t.postal_postcode, t.postal_postplace,
            t.postal_region_id, t.postal_region_path, t.postal_region_code, t.postal_country_id, t.postal_country_iso_2,
            t.postal_latitude, t.postal_longitude, t.postal_altitude,
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
            public.report_partition_seq(t.unit_type, t.unit_id, (SELECT analytics_partition_count FROM public.settings)) AS report_partition_seq
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
            t.physical_latitude, t.physical_longitude, t.physical_altitude, t.domestic,
            t.postal_address_part1, t.postal_address_part2, t.postal_address_part3, t.postal_postcode, t.postal_postplace,
            t.postal_region_id, t.postal_region_path, t.postal_region_code, t.postal_country_id, t.postal_country_iso_2,
            t.postal_latitude, t.postal_longitude, t.postal_altitude,
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
            public.report_partition_seq(t.unit_type, t.unit_id, (SELECT analytics_partition_count FROM public.settings)) AS report_partition_seq
        FROM public.timeline_power_group t
        LEFT JOIN LATERAL (SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents FROM public.external_ident ei JOIN public.external_ident_type eit ON ei.type_id = eit.id WHERE ei.power_group_id = t.power_group_id) eia1 ON true
        LEFT JOIN LATERAL (SELECT array_agg(tag.path ORDER BY tag.path) AS tag_paths FROM public.tag_for_unit tfu JOIN public.tag ON tfu.tag_id = tag.id WHERE tfu.power_group_id = t.power_group_id) tpa ON true
        WHERE t.unit_id = ANY(v_ids);
    END IF;
END;
$get_statistical_unit_data_partial$;

-- ============================================================================
-- SECTION 13: pipeline_progress — add affected_power_group_count + set phase
-- ============================================================================

-- Add power_group count column to pipeline_progress
ALTER TABLE worker.pipeline_progress ADD COLUMN affected_power_group_count INT DEFAULT NULL;

-- Set phase on derive_power_groups command (step within Phase 1)
UPDATE worker.command_registry
SET phase = 'is_deriving_statistical_units'
WHERE command = 'derive_power_groups';

-- Update notify_start to also reset affected_power_group_count
CREATE OR REPLACE PROCEDURE worker.notify_is_deriving_statistical_units_start()
LANGUAGE plpgsql
AS $procedure$
BEGIN
  INSERT INTO worker.pipeline_progress (phase, step, total, completed, updated_at)
  VALUES ('is_deriving_statistical_units', 'derive_statistical_unit', 0, 0, clock_timestamp())
  ON CONFLICT (phase) DO UPDATE SET
    step = EXCLUDED.step, total = 0, completed = 0,
    affected_establishment_count = NULL, affected_legal_unit_count = NULL,
    affected_enterprise_count = NULL, affected_power_group_count = NULL,
    updated_at = clock_timestamp();

  PERFORM pg_notify('worker_status', json_build_object('type', 'is_deriving_statistical_units', 'status', true)::text);
END;
$procedure$;

-- Update is_deriving_statistical_units to include power_group count
CREATE OR REPLACE FUNCTION public.is_deriving_statistical_units()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  SELECT jsonb_build_object(
    'active', pp.phase IS NOT NULL,
    'step', pp.step,
    'total', COALESCE(pp.total, 0),
    'completed', COALESCE(pp.completed, 0),
    'affected_establishment_count', pp.affected_establishment_count,
    'affected_legal_unit_count', pp.affected_legal_unit_count,
    'affected_enterprise_count', pp.affected_enterprise_count,
    'affected_power_group_count', pp.affected_power_group_count
  )
  FROM (SELECT NULL) AS dummy
  LEFT JOIN worker.pipeline_progress AS pp ON pp.phase = 'is_deriving_statistical_units';
$function$;

-- Update is_deriving_reports to include power_group count
CREATE OR REPLACE FUNCTION public.is_deriving_reports()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  SELECT jsonb_build_object(
    'active', pp.phase IS NOT NULL,
    'step', pp.step,
    'total', COALESCE(pp.total, 0),
    'completed', COALESCE(pp.completed, 0),
    'affected_establishment_count', pp.affected_establishment_count,
    'affected_legal_unit_count', pp.affected_legal_unit_count,
    'affected_enterprise_count', pp.affected_enterprise_count,
    'affected_power_group_count', pp.affected_power_group_count
  )
  FROM (SELECT NULL) AS dummy
  LEFT JOIN worker.pipeline_progress AS pp ON pp.phase = 'is_deriving_reports';
$function$;

-- Update pipeline_progress_on_child_completed to include power_group count in notification
CREATE OR REPLACE PROCEDURE worker.pipeline_progress_on_child_completed(
    IN p_phase worker.pipeline_phase,
    IN p_parent_task_id BIGINT
)
LANGUAGE plpgsql
AS $pipeline_progress_on_child_completed$
BEGIN
    UPDATE worker.pipeline_progress
    SET completed = completed + 1,
        updated_at = clock_timestamp()
    WHERE phase = p_phase;

    PERFORM pg_notify('worker_status',
        json_build_object(
            'type', 'pipeline_progress',
            'phases', COALESCE(
                (SELECT json_agg(json_build_object(
                    'phase', pp.phase, 'step', pp.step,
                    'total', pp.total, 'completed', pp.completed,
                    'affected_establishment_count', pp.affected_establishment_count,
                    'affected_legal_unit_count', pp.affected_legal_unit_count,
                    'affected_enterprise_count', pp.affected_enterprise_count,
                    'affected_power_group_count', pp.affected_power_group_count
                )) FROM worker.pipeline_progress AS pp),
                '[]'::json
            )
        )::text
    );
END;
$pipeline_progress_on_child_completed$;

-- ============================================================================
-- SECTION 14: collect_changes — compute PG IDs from legal_relationship
-- ============================================================================

-- collect_changes now looks up affected power_group IDs from legal_relationship
-- based on the LU IDs found in base_change_log, and passes them to
-- enqueue_derive_statistical_unit. No more derive_power_groups in the pipeline.
CREATE OR REPLACE PROCEDURE worker.command_collect_changes(IN p_payload jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'worker', 'pg_temp'
AS $command_collect_changes$
DECLARE
    v_row RECORD;
    v_est_ids int4multirange := '{}'::int4multirange;
    v_lu_ids int4multirange := '{}'::int4multirange;
    v_ent_ids int4multirange := '{}'::int4multirange;
    v_pg_ids int4multirange := '{}'::int4multirange;
    v_valid_range datemultirange := '{}'::datemultirange;
    v_valid_from DATE;
    v_valid_until DATE;
    v_round_priority_base BIGINT;
BEGIN
    -- Atomically drain all committed rows, merging multiranges.
    FOR v_row IN DELETE FROM worker.base_change_log RETURNING * LOOP
        v_est_ids := v_est_ids + v_row.establishment_ids;
        v_lu_ids := v_lu_ids + v_row.legal_unit_ids;
        v_ent_ids := v_ent_ids + v_row.enterprise_ids;
        v_valid_range := v_valid_range + v_row.edited_by_valid_range;
    END LOOP;

    -- Clear crash recovery flag
    UPDATE worker.base_change_log_has_pending SET has_pending = FALSE;

    -- If any changes exist, enqueue derive
    IF v_est_ids != '{}'::int4multirange
       OR v_lu_ids != '{}'::int4multirange
       OR v_ent_ids != '{}'::int4multirange THEN

        -- ROUND PRIORITY: Read own priority as the round base.
        SELECT priority INTO v_round_priority_base
        FROM worker.tasks
        WHERE state = 'processing' AND worker_pid = pg_backend_pid()
        ORDER BY id DESC LIMIT 1;

        -- Compute affected power group IDs from legal_relationship using containment operator
        SELECT COALESCE(
            range_agg(int4range(lr.power_group_id, lr.power_group_id, '[]')),
            '{}'::int4multirange
        )
        INTO v_pg_ids
        FROM public.legal_relationship AS lr
        WHERE lr.power_group_id IS NOT NULL
          AND (v_lu_ids @> lr.influencing_id OR v_lu_ids @> lr.influenced_id);

        -- If date range is empty, look up actual valid ranges from affected units
        IF v_valid_range = '{}'::datemultirange THEN
            SELECT COALESCE(range_agg(vr)::datemultirange, '{}'::datemultirange)
            INTO v_valid_range
            FROM (
                SELECT valid_range AS vr FROM public.establishment AS est
                  WHERE v_est_ids @> est.id
                UNION ALL
                SELECT valid_range AS vr FROM public.legal_unit AS lu
                  WHERE v_lu_ids @> lu.id
            ) AS units;
        END IF;

        -- Extract date bounds for enqueue_derive interface
        v_valid_from := lower(v_valid_range);
        v_valid_until := upper(v_valid_range);

        PERFORM worker.enqueue_derive_statistical_unit(
            p_establishment_id_ranges := v_est_ids,
            p_legal_unit_id_ranges := v_lu_ids,
            p_enterprise_id_ranges := v_ent_ids,
            p_power_group_id_ranges := v_pg_ids,
            p_valid_from := v_valid_from,
            p_valid_until := v_valid_until,
            p_round_priority_base := v_round_priority_base
        );
    END IF;
END;
$command_collect_changes$;

-- ============================================================================
-- SECTION 15: Import system — holistic process support + power_group_link step
-- ============================================================================

-- 15a. import_job_process_batch: skip holistic steps (they run once after all batches)
CREATE OR REPLACE PROCEDURE admin.import_job_process_batch(IN job import_job, IN p_batch_seq integer)
LANGUAGE plpgsql
AS $import_job_process_batch$
DECLARE
    targets JSONB;
    target_rec RECORD;
    proc_to_call REGPROC;
    error_message TEXT;
    v_should_disable_triggers BOOLEAN;
BEGIN
    RAISE DEBUG '[Job %] Processing batch_seq % through all process steps.', job.id, p_batch_seq;
    targets := job.definition_snapshot->'import_step_list';

    -- Check if the batch contains any operations that are not simple inserts.
    EXECUTE format(
        'SELECT EXISTS(SELECT 1 FROM public.%I dt WHERE dt.batch_seq = $1 AND dt.operation IS DISTINCT FROM %L)',
        job.data_table_name,
        'insert'
    )
    INTO v_should_disable_triggers
    USING p_batch_seq;

    IF v_should_disable_triggers THEN
        RAISE DEBUG '[Job %] Batch contains updates/replaces. Disabling FK triggers.', job.id;
        CALL admin.disable_temporal_triggers();
    ELSE
        RAISE DEBUG '[Job %] Batch is insert-only. Skipping trigger disable/enable.', job.id;
    END IF;

    FOR target_rec IN SELECT * FROM jsonb_populate_recordset(NULL::public.import_step, targets) ORDER BY priority
    LOOP
        -- Skip holistic steps — they run once after all batches, not per-batch
        IF COALESCE(target_rec.is_holistic, false) THEN
            CONTINUE;
        END IF;

        proc_to_call := target_rec.process_procedure;
        IF proc_to_call IS NULL THEN
            CONTINUE;
        END IF;

        RAISE DEBUG '[Job %] Batch processing: Calling % for step %', job.id, proc_to_call, target_rec.code;

        -- Since this is one transaction, any error will roll back the entire batch.
        EXECUTE format('CALL %s($1, $2, $3)', proc_to_call) USING job.id, p_batch_seq, target_rec.code;
    END LOOP;

    -- Re-enable triggers if they were disabled.
    IF v_should_disable_triggers THEN
        RAISE DEBUG '[Job %] Re-enabling FK triggers.', job.id;
        CALL admin.enable_temporal_triggers();
    END IF;

    RAISE DEBUG '[Job %] Batch processing complete.', job.id;
END;
$import_job_process_batch$;

-- 15b. import_job_processing_phase: after all batches, run holistic process steps
CREATE OR REPLACE FUNCTION admin.import_job_processing_phase(job import_job)
RETURNS boolean
LANGUAGE plpgsql
AS $import_job_processing_phase$
DECLARE
    v_current_batch INTEGER;
    v_max_batch INTEGER;
    v_rows_processed INTEGER;
    error_message TEXT;
    error_context TEXT;
    v_holistic_step RECORD;
    v_proc_to_call REGPROC;
    v_targets JSONB;
BEGIN
    -- Get the current batch to process (smallest batch_seq that still has unprocessed rows)
    EXECUTE format($$
        SELECT MIN(batch_seq), MAX(batch_seq)
        FROM public.%1$I
        WHERE batch_seq IS NOT NULL AND state = 'processing'
    $$, job.data_table_name) INTO v_current_batch, v_max_batch;

    IF v_current_batch IS NOT NULL THEN
        RAISE DEBUG '[Job %] Processing batch % of % (max).', job.id, v_current_batch, v_max_batch;

        BEGIN
            CALL admin.import_job_process_batch(job, v_current_batch);

            -- Mark all rows in the batch that are not in an error state as 'processed'.
            EXECUTE format($$
                UPDATE public.%1$I
                SET state = 'processed'
                WHERE batch_seq = %2$L AND state != 'error'
            $$, job.data_table_name, v_current_batch);
            GET DIAGNOSTICS v_rows_processed = ROW_COUNT;

            RAISE DEBUG '[Job %] Batch % successfully processed. Marked % non-error rows as processed.',
                job.id, v_current_batch, v_rows_processed;

            -- Increment imported_rows counter directly instead of doing a full table scan.
            UPDATE public.import_job SET imported_rows = imported_rows + v_rows_processed WHERE id = job.id;

        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT,
                                  error_context = PG_EXCEPTION_CONTEXT;
            RAISE WARNING '[Job %] Error processing batch %: %. Context: %. Marking batch rows as error and failing job.',
                job.id, v_current_batch, error_message, error_context;

            EXECUTE format($$
                UPDATE public.%1$I
                SET state = 'error', errors = COALESCE(errors, '{}'::jsonb) || %2$L
                WHERE batch_seq = %3$L
            $$, job.data_table_name,
                jsonb_build_object('process_batch_error', error_message, 'context', error_context),
                v_current_batch);

            UPDATE public.import_job
            SET error = jsonb_build_object('error_in_processing_batch', error_message, 'context', error_context)::TEXT,
                state = 'failed'
            WHERE id = job.id;

            RETURN FALSE; -- On error, do not reschedule.
        END;

        RETURN TRUE; -- Batch work was done.
    END IF;

    -- All batches done. Now run holistic process steps (if any).
    -- Two-stage pattern: discovery then execution (same as analysis phase).

    -- Stage 1: Discovery — find next holistic process step that has work
    v_targets := job.definition_snapshot->'import_step_list';

    -- Check if we have a current holistic step in progress (via current_step_code)
    IF job.current_step_code IS NOT NULL THEN
        -- Stage 2: Execution — run the holistic step
        SELECT * INTO v_holistic_step
        FROM jsonb_populate_recordset(NULL::public.import_step, v_targets)
        WHERE code = job.current_step_code;

        IF FOUND AND v_holistic_step.process_procedure IS NOT NULL THEN
            RAISE DEBUG '[Job %] Executing holistic process step: %', job.id, v_holistic_step.code;

            BEGIN
                v_proc_to_call := v_holistic_step.process_procedure;
                -- Holistic steps receive NULL batch_seq
                EXECUTE format('CALL %s($1, $2, $3)', v_proc_to_call) USING job.id, NULL::integer, v_holistic_step.code;
            EXCEPTION WHEN OTHERS THEN
                GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT,
                                      error_context = PG_EXCEPTION_CONTEXT;
                RAISE WARNING '[Job %] Error in holistic process step %: %. Context: %.',
                    job.id, v_holistic_step.code, error_message, error_context;
                UPDATE public.import_job
                SET error = jsonb_build_object('error_in_holistic_process', error_message, 'step', v_holistic_step.code, 'context', error_context)::TEXT,
                    state = 'failed'
                WHERE id = job.id;
                RETURN FALSE;
            END;
        END IF;

        -- Clear current step code but KEEP current_step_priority so next discovery
        -- starts after this step's priority (prevents infinite re-discovery loop).
        UPDATE public.import_job
        SET current_step_code = NULL
        WHERE id = job.id;
        RETURN TRUE;
    END IF;

    -- Stage 1: Find the next holistic process step (by priority)
    SELECT * INTO v_holistic_step
    FROM jsonb_populate_recordset(NULL::public.import_step, v_targets)
    WHERE COALESCE(is_holistic, false) = true
      AND process_procedure IS NOT NULL
      AND priority > COALESCE(job.current_step_priority, 0)
    ORDER BY priority
    LIMIT 1;

    IF FOUND THEN
        -- Set current step, return TRUE (commit fast, then execute next turn)
        UPDATE public.import_job
        SET current_step_code = v_holistic_step.code,
            current_step_priority = v_holistic_step.priority
        WHERE id = job.id;
        RAISE DEBUG '[Job %] Discovered holistic process step: % (priority %)', job.id, v_holistic_step.code, v_holistic_step.priority;
        RETURN TRUE;
    END IF;

    -- No more holistic steps. Processing phase complete.
    -- Clear priority tracker so it's fresh for next job.
    UPDATE public.import_job
    SET current_step_priority = NULL
    WHERE id = job.id;
    RAISE DEBUG '[Job %] No more batches or holistic steps. Phase complete.', job.id;
    RETURN FALSE;
END;
$import_job_processing_phase$;

-- 15c. analyse_power_group_link: holistic analyse (receives p_batch_seq = NULL)
-- Computes power group clusters from the combined graph of existing + new relationships,
-- then populates power_group_id and cluster_root_legal_unit_id on data table rows.
CREATE OR REPLACE PROCEDURE import.analyse_power_group_link(
    IN p_job_id integer,
    IN p_batch_seq integer,
    IN p_step_code text
)
LANGUAGE plpgsql
AS $analyse_power_group_link$
DECLARE
    v_job public.import_job;
    v_definition public.import_definition;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_step_priority INT;
BEGIN
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;

    SELECT * INTO v_definition
    FROM jsonb_populate_record(NULL::public.import_definition, v_job.definition_snapshot->'import_definition');

    -- Only run for legal_relationship mode
    IF v_definition.mode != 'legal_relationship' THEN
        RAISE DEBUG '[Job %] analyse_power_group_link: Skipping, mode is %', p_job_id, v_definition.mode;
        -- Advance last_completed_priority for all rows
        SELECT * INTO v_step
        FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list')
        WHERE code = p_step_code;
        EXECUTE format($$
            UPDATE public.%I SET last_completed_priority = %L WHERE last_completed_priority < %L
        $$, v_data_table_name, v_step.priority, v_step.priority);
        RETURN;
    END IF;

    SELECT * INTO v_step
    FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list')
    WHERE code = p_step_code;
    v_step_priority := v_step.priority;

    RAISE DEBUG '[Job %] analyse_power_group_link: Computing power group clusters (holistic)', p_job_id;

    -- Build complete relationship graph: UNION of existing base table rows + new rows from data table.
    -- Then compute clusters using recursive CTE (same algorithm as legal_unit_power_hierarchy).
    -- Finally, find/assign power_group_id for each cluster and populate data table rows.
    EXECUTE format($sql$
        WITH RECURSIVE
        -- Combined graph: existing relationships + new ones from import data table
        all_relationships AS (
            -- Existing relationships from base table
            SELECT lr.influencing_id, lr.influenced_id, lr.valid_range, lr.power_group_id
            FROM public.legal_relationship AS lr
            WHERE lr.primary_influencer_only IS TRUE
            UNION ALL
            -- New relationships from data table (where action = 'use')
            SELECT dt.influencing_id, dt.influenced_id,
                   daterange(dt.valid_from, dt.valid_until) AS valid_range,
                   NULL::integer AS power_group_id
            FROM public.%1$I AS dt
            JOIN public.legal_rel_type AS lrt ON lrt.id = dt.type_id
            WHERE dt.action = 'use' AND lrt.primary_influencer_only IS TRUE
        ),
        -- Compute hierarchy: find root legal units and traverse down
        hierarchy AS (
            -- Root legal units: have controlling children but no controlling parent
            SELECT
                lu.id AS legal_unit_id,
                lu.valid_range,
                lu.id AS root_legal_unit_id,
                1 AS power_level,
                ARRAY[lu.id] AS path,
                FALSE AS is_cycle
            FROM public.legal_unit AS lu
            WHERE EXISTS (
                SELECT 1 FROM all_relationships AS ar
                WHERE ar.influencing_id = lu.id AND ar.valid_range && lu.valid_range
            )
            AND NOT EXISTS (
                SELECT 1 FROM all_relationships AS ar
                WHERE ar.influenced_id = lu.id AND ar.valid_range && lu.valid_range
            )
            UNION ALL
            SELECT
                ar.influenced_id AS legal_unit_id,
                influenced_lu.valid_range * ar.valid_range * h.valid_range AS valid_range,
                h.root_legal_unit_id,
                h.power_level + 1 AS power_level,
                h.path || ar.influenced_id AS path,
                ar.influenced_id = ANY(h.path) AS is_cycle
            FROM hierarchy AS h
            JOIN all_relationships AS ar
                ON ar.influencing_id = h.legal_unit_id
                AND ar.valid_range && h.valid_range
            JOIN public.legal_unit AS influenced_lu
                ON influenced_lu.id = ar.influenced_id
                AND influenced_lu.valid_range && ar.valid_range
            WHERE NOT h.is_cycle AND h.power_level < 100
        ),
        -- Distinct clusters by root
        clusters AS (
            SELECT DISTINCT root_legal_unit_id FROM hierarchy WHERE NOT is_cycle
        ),
        -- Find existing power_group for each cluster (via legal_relationship base table)
        cluster_pg AS (
            SELECT c.root_legal_unit_id,
                   (SELECT lr.power_group_id
                    FROM public.legal_relationship AS lr
                    JOIN hierarchy AS h ON (lr.influencing_id = h.legal_unit_id OR lr.influenced_id = h.legal_unit_id)
                        AND lr.valid_range && h.valid_range
                    WHERE h.root_legal_unit_id = c.root_legal_unit_id
                      AND lr.power_group_id IS NOT NULL
                    LIMIT 1) AS existing_power_group_id
            FROM clusters AS c
        ),
        -- Map each data table row to its cluster root
        row_clusters AS (
            SELECT dt.row_id,
                   h.root_legal_unit_id
            FROM public.%1$I AS dt
            JOIN public.legal_rel_type AS lrt ON lrt.id = dt.type_id
            JOIN hierarchy AS h ON (dt.influencing_id = h.legal_unit_id OR dt.influenced_id = h.legal_unit_id)
            WHERE dt.action = 'use' AND lrt.primary_influencer_only IS TRUE
        )
        UPDATE public.%1$I AS dt
        SET cluster_root_legal_unit_id = rc.root_legal_unit_id,
            power_group_id = cpg.existing_power_group_id
        FROM row_clusters AS rc
        JOIN cluster_pg AS cpg ON cpg.root_legal_unit_id = rc.root_legal_unit_id
        WHERE dt.row_id = rc.row_id
    $sql$, v_data_table_name);

    -- Advance last_completed_priority for all rows
    EXECUTE format($$
        UPDATE public.%I SET last_completed_priority = %L WHERE last_completed_priority < %L
    $$, v_data_table_name, v_step_priority, v_step_priority);

    RAISE DEBUG '[Job %] analyse_power_group_link: Complete', p_job_id;
END;
$analyse_power_group_link$;

-- 15g. process_power_group_link: holistic process (receives p_batch_seq = NULL)
-- Creates/updates power_group records and sets power_group_id on legal_relationship base table rows.
CREATE OR REPLACE PROCEDURE import.process_power_group_link(
    IN p_job_id integer,
    IN p_batch_seq integer,
    IN p_step_code text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'import', 'worker', 'pg_temp'
AS $process_power_group_link$
DECLARE
    v_job public.import_job;
    v_definition public.import_definition;
    v_data_table_name TEXT;
    _cluster RECORD;
    _power_group public.power_group;
    _created_count integer := 0;
    _updated_count integer := 0;
    _linked_count integer := 0;
    _row_count integer;
    _current_user_id integer;
BEGIN
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;

    SELECT * INTO v_definition
    FROM jsonb_populate_record(NULL::public.import_definition, v_job.definition_snapshot->'import_definition');

    -- Only run for legal_relationship mode
    IF v_definition.mode != 'legal_relationship' THEN
        RAISE DEBUG '[Job %] process_power_group_link: Skipping, mode is %', p_job_id, v_definition.mode;
        RETURN;
    END IF;

    RAISE DEBUG '[Job %] process_power_group_link: Creating/updating power groups (holistic)', p_job_id;

    -- Disable log_base_change triggers to prevent re-enqueue loop
    -- (power_group_id UPDATEs should be silent — only actual relationship changes trigger derive)
    ALTER TABLE public.legal_relationship DISABLE TRIGGER a_legal_relationship_log_insert;
    ALTER TABLE public.legal_relationship DISABLE TRIGGER a_legal_relationship_log_update;
    ALTER TABLE public.legal_relationship DISABLE TRIGGER a_legal_relationship_log_delete;

    -- Find current user for power_group creation
    SELECT id INTO _current_user_id FROM auth.user WHERE email = session_user OR session_user = 'postgres';
    IF _current_user_id IS NULL THEN
        SELECT id INTO _current_user_id FROM auth.user WHERE role_id = (SELECT id FROM auth.role WHERE name = 'super_user') LIMIT 1;
    END IF;
    IF _current_user_id IS NULL THEN
        RAISE EXCEPTION 'No user found for power group creation';
    END IF;

    -- Use legal_relationship_cluster view (now includes newly committed rows from process_legal_relationship)
    FOR _cluster IN SELECT DISTINCT root_legal_unit_id FROM public.legal_relationship_cluster
    LOOP
        -- Find existing power_group for this cluster
        SELECT pg.* INTO _power_group
        FROM public.power_group AS pg
        JOIN public.legal_relationship AS lr ON lr.power_group_id = pg.id
        JOIN public.legal_relationship_cluster AS lrc ON lrc.legal_relationship_id = lr.id
        WHERE lrc.root_legal_unit_id = _cluster.root_legal_unit_id
        LIMIT 1;

        IF NOT FOUND THEN
            INSERT INTO public.power_group (edit_by_user_id) VALUES (_current_user_id) RETURNING * INTO _power_group;
            _created_count := _created_count + 1;
            RAISE DEBUG '[Job %] process_power_group_link: Created power_group % for root LU %',
                p_job_id, _power_group.ident, _cluster.root_legal_unit_id;
        ELSE
            _updated_count := _updated_count + 1;
        END IF;

        -- Set power_group_id on all legal_relationships in this cluster
        UPDATE public.legal_relationship AS lr
        SET power_group_id = _power_group.id
        FROM public.legal_relationship_cluster AS lrc
        WHERE lr.id = lrc.legal_relationship_id
          AND lrc.root_legal_unit_id = _cluster.root_legal_unit_id
          AND (lr.power_group_id IS DISTINCT FROM _power_group.id);
        GET DIAGNOSTICS _row_count = ROW_COUNT;
        _linked_count := _linked_count + _row_count;
    END LOOP;

    -- Handle cluster merges (multiple power_groups pointing to same cluster)
    WITH cluster_sizes AS (
        SELECT lr.power_group_id, COUNT(*) AS rel_count
        FROM public.legal_relationship AS lr WHERE lr.power_group_id IS NOT NULL GROUP BY lr.power_group_id
    ),
    merge_candidates AS (
        SELECT DISTINCT lrc.root_legal_unit_id, lr.power_group_id AS current_pg_id, cs.rel_count
        FROM public.legal_relationship_cluster AS lrc
        JOIN public.legal_relationship AS lr ON lr.id = lrc.legal_relationship_id
        JOIN cluster_sizes AS cs ON cs.power_group_id = lr.power_group_id
        WHERE lr.power_group_id IS NOT NULL
    ),
    clusters_with_multiple_pgs AS (
        SELECT root_legal_unit_id, array_agg(current_pg_id ORDER BY rel_count DESC, current_pg_id) AS pg_ids
        FROM merge_candidates GROUP BY root_legal_unit_id HAVING COUNT(DISTINCT current_pg_id) > 1
    )
    UPDATE public.legal_relationship AS lr
    SET power_group_id = cwmp.pg_ids[1]
    FROM public.legal_relationship_cluster AS lrc
    JOIN clusters_with_multiple_pgs AS cwmp ON cwmp.root_legal_unit_id = lrc.root_legal_unit_id
    WHERE lr.id = lrc.legal_relationship_id AND lr.power_group_id != cwmp.pg_ids[1];
    GET DIAGNOSTICS _row_count = ROW_COUNT;
    IF _row_count > 0 THEN
        RAISE DEBUG '[Job %] process_power_group_link: Merged % relationships into surviving power groups', p_job_id, _row_count;
    END IF;

    -- Clear power_group_id from non-primary-influencer relationships
    UPDATE public.legal_relationship AS lr SET power_group_id = NULL
    WHERE lr.power_group_id IS NOT NULL AND lr.primary_influencer_only IS NOT TRUE;
    GET DIAGNOSTICS _row_count = ROW_COUNT;
    IF _row_count > 0 THEN
        RAISE DEBUG '[Job %] process_power_group_link: Cleared power_group from % non-primary-influencer relationships', p_job_id, _row_count;
    END IF;

    RAISE DEBUG '[Job %] process_power_group_link: Completed: created=%, updated=%, linked=%',
        p_job_id, _created_count, _updated_count, _linked_count;

    -- Re-enable triggers
    ALTER TABLE public.legal_relationship ENABLE TRIGGER a_legal_relationship_log_insert;
    ALTER TABLE public.legal_relationship ENABLE TRIGGER a_legal_relationship_log_update;
    ALTER TABLE public.legal_relationship ENABLE TRIGGER a_legal_relationship_log_delete;
END;
$process_power_group_link$;

-- 15e. Register power_group_link import step (procedures must exist before ::regproc cast)
INSERT INTO public.import_step (code, name, priority, analyse_procedure, process_procedure, is_holistic)
VALUES ('power_group_link', 'Link to Power Group', 21,
        'import.analyse_power_group_link'::regproc,
        'import.process_power_group_link'::regproc, true)
ON CONFLICT (code) DO UPDATE SET
    name = EXCLUDED.name,
    priority = EXCLUDED.priority,
    analyse_procedure = EXCLUDED.analyse_procedure,
    process_procedure = EXCLUDED.process_procedure,
    is_holistic = EXCLUDED.is_holistic;

-- 15f. Register data columns for power_group_link
INSERT INTO public.import_data_column (step_id, column_name, column_type, purpose, is_nullable, default_value, is_uniquely_identifying)
SELECT s.id, col.column_name, col.column_type, col.purpose, col.is_nullable, col.default_value, col.is_uniquely_identifying
FROM public.import_step AS s
CROSS JOIN (VALUES
    ('power_group_id',             'INTEGER', 'internal'::import_data_column_purpose, true, NULL::text, false),
    ('cluster_root_legal_unit_id', 'INTEGER', 'internal'::import_data_column_purpose, true, NULL::text, false)
) AS col(column_name, column_type, purpose, is_nullable, default_value, is_uniquely_identifying)
WHERE s.code = 'power_group_link'
ON CONFLICT DO NOTHING;

-- 15g. Add power_group_link step to legal_relationship import definitions
INSERT INTO public.import_definition_step (definition_id, step_id)
SELECT id.definition_id, s.id
FROM public.import_step AS s
CROSS JOIN (
    SELECT id AS definition_id FROM public.import_definition WHERE mode = 'legal_relationship'
) AS id
WHERE s.code = 'power_group_link'
ON CONFLICT DO NOTHING;

-- ============================================================================
-- SECTION 16: Remove derive_power_groups from pipeline
-- ============================================================================

-- Remove derive_power_groups phase assignment (it's no longer a pipeline step)
UPDATE worker.command_registry
SET phase = NULL, after_procedure = NULL
WHERE command = 'derive_power_groups';

-- ============================================================================
-- SECTION 17: Grants
-- ============================================================================

GRANT SELECT ON public.timeline_power_group TO authenticated, regular_user, admin_user;
GRANT SELECT ON public.timeline_power_group_def TO authenticated, regular_user, admin_user;

-- Re-grant SELECT on statistical_unit_def (dropped and recreated in this migration)
GRANT SELECT ON public.statistical_unit_def TO authenticated, regular_user, admin_user;

-- Add RLS to timeline_power_group (same as other timeline tables)
SELECT admin.add_rls_regular_user_can_read('public.timeline_power_group');

END;
