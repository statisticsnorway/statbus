```sql
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
                FROM pgm_temp AS pgm
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
    END IF;
END;
$procedure$
```
