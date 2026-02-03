-- Down Migration 20260203170139: optimize_get_statistical_unit_data_partial_array_filtering
--
-- Restore original <@ multirange filtering (slower but original behavior)

BEGIN;

CREATE OR REPLACE FUNCTION import.get_statistical_unit_data_partial(p_unit_type statistical_unit_type, p_id_ranges int4multirange)
 RETURNS SETOF statistical_unit
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
    IF p_unit_type = 'establishment' THEN
        RETURN QUERY
        SELECT
            t.unit_type,
            t.unit_id,
            t.valid_from,
            t.valid_to,
            t.valid_until,
            -- external_idents (LATERAL)
            COALESCE(eia1.external_idents, '{}'::jsonb) AS external_idents,
            t.name,
            t.birth_date,
            t.death_date,
            t.search,
            t.primary_activity_category_id,
            t.primary_activity_category_path,
            t.primary_activity_category_code,
            t.secondary_activity_category_id,
            t.secondary_activity_category_path,
            t.secondary_activity_category_code,
            t.activity_category_paths,
            t.sector_id,
            t.sector_path,
            t.sector_code,
            t.sector_name,
            t.data_source_ids,
            t.data_source_codes,
            t.legal_form_id,
            t.legal_form_code,
            t.legal_form_name,
            t.physical_address_part1,
            t.physical_address_part2,
            t.physical_address_part3,
            t.physical_postcode,
            t.physical_postplace,
            t.physical_region_id,
            t.physical_region_path,
            t.physical_region_code,
            t.physical_country_id,
            t.physical_country_iso_2,
            t.physical_latitude,
            t.physical_longitude,
            t.physical_altitude,
            t.domestic,
            t.postal_address_part1,
            t.postal_address_part2,
            t.postal_address_part3,
            t.postal_postcode,
            t.postal_postplace,
            t.postal_region_id,
            t.postal_region_path,
            t.postal_region_code,
            t.postal_country_id,
            t.postal_country_iso_2,
            t.postal_latitude,
            t.postal_longitude,
            t.postal_altitude,
            t.web_address,
            t.email_address,
            t.phone_number,
            t.landline,
            t.mobile_number,
            t.fax_number,
            t.unit_size_id,
            t.unit_size_code,
            t.status_id,
            t.status_code,
            t.used_for_counting,
            t.last_edit_comment,
            t.last_edit_by_user_id,
            t.last_edit_at,
            t.invalid_codes,
            t.has_legal_unit,
            t.related_establishment_ids,
            t.excluded_establishment_ids,
            t.included_establishment_ids,
            t.related_legal_unit_ids,
            t.excluded_legal_unit_ids,
            t.included_legal_unit_ids,
            t.related_enterprise_ids,
            t.excluded_enterprise_ids,
            t.included_enterprise_ids,
            t.stats,
            t.stats_summary,
            array_length(t.included_establishment_ids, 1) AS included_establishment_count,
            array_length(t.included_legal_unit_ids, 1) AS included_legal_unit_count,
            array_length(t.included_enterprise_ids, 1) AS included_enterprise_count,
            COALESCE(tpa.tag_paths, ARRAY[]::public.ltree[]) AS tag_paths
        FROM public.timeline_establishment t
        LEFT JOIN LATERAL (
            SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents
            FROM public.external_ident ei
            JOIN public.external_ident_type eit ON ei.type_id = eit.id
            WHERE ei.establishment_id = t.unit_id
        ) eia1 ON true
        LEFT JOIN LATERAL (
            SELECT array_agg(tag.path ORDER BY tag.path) AS tag_paths
            FROM public.tag_for_unit tfu
            JOIN public.tag ON tfu.tag_id = tag.id
            WHERE tfu.establishment_id = t.unit_id
        ) tpa ON true
        WHERE t.unit_id <@ p_id_ranges;

    ELSIF p_unit_type = 'legal_unit' THEN
        RETURN QUERY
        SELECT
            t.unit_type,
            t.unit_id,
            t.valid_from,
            t.valid_to,
            t.valid_until,
            COALESCE(eia1.external_idents, '{}'::jsonb) AS external_idents,
            t.name,
            t.birth_date,
            t.death_date,
            t.search,
            t.primary_activity_category_id,
            t.primary_activity_category_path,
            t.primary_activity_category_code,
            t.secondary_activity_category_id,
            t.secondary_activity_category_path,
            t.secondary_activity_category_code,
            t.activity_category_paths,
            t.sector_id,
            t.sector_path,
            t.sector_code,
            t.sector_name,
            t.data_source_ids,
            t.data_source_codes,
            t.legal_form_id,
            t.legal_form_code,
            t.legal_form_name,
            t.physical_address_part1,
            t.physical_address_part2,
            t.physical_address_part3,
            t.physical_postcode,
            t.physical_postplace,
            t.physical_region_id,
            t.physical_region_path,
            t.physical_region_code,
            t.physical_country_id,
            t.physical_country_iso_2,
            t.physical_latitude,
            t.physical_longitude,
            t.physical_altitude,
            t.domestic,
            t.postal_address_part1,
            t.postal_address_part2,
            t.postal_address_part3,
            t.postal_postcode,
            t.postal_postplace,
            t.postal_region_id,
            t.postal_region_path,
            t.postal_region_code,
            t.postal_country_id,
            t.postal_country_iso_2,
            t.postal_latitude,
            t.postal_longitude,
            t.postal_altitude,
            t.web_address,
            t.email_address,
            t.phone_number,
            t.landline,
            t.mobile_number,
            t.fax_number,
            t.unit_size_id,
            t.unit_size_code,
            t.status_id,
            t.status_code,
            t.used_for_counting,
            t.last_edit_comment,
            t.last_edit_by_user_id,
            t.last_edit_at,
            t.invalid_codes,
            t.has_legal_unit,
            t.related_establishment_ids,
            t.excluded_establishment_ids,
            t.included_establishment_ids,
            t.related_legal_unit_ids,
            t.excluded_legal_unit_ids,
            t.included_legal_unit_ids,
            t.related_enterprise_ids,
            t.excluded_enterprise_ids,
            t.included_enterprise_ids,
            t.stats,
            t.stats_summary,
            array_length(t.included_establishment_ids, 1) AS included_establishment_count,
            array_length(t.included_legal_unit_ids, 1) AS included_legal_unit_count,
            array_length(t.included_enterprise_ids, 1) AS included_enterprise_count,
            COALESCE(tpa.tag_paths, ARRAY[]::public.ltree[]) AS tag_paths
        FROM public.timeline_legal_unit t
        LEFT JOIN LATERAL (
            SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents
            FROM public.external_ident ei
            JOIN public.external_ident_type eit ON ei.type_id = eit.id
            WHERE ei.legal_unit_id = t.unit_id
        ) eia1 ON true
        LEFT JOIN LATERAL (
            SELECT array_agg(tag.path ORDER BY tag.path) AS tag_paths
            FROM public.tag_for_unit tfu
            JOIN public.tag ON tfu.tag_id = tag.id
            WHERE tfu.legal_unit_id = t.unit_id
        ) tpa ON true
        WHERE t.unit_id <@ p_id_ranges;

    ELSIF p_unit_type = 'enterprise' THEN
        RETURN QUERY
        SELECT
            t.unit_type,
            t.unit_id,
            t.valid_from,
            t.valid_to,
            t.valid_until,
            -- COALESCE chain for enterprise (Fallback logic)
            COALESCE(
                eia1.external_idents, -- Direct
                eia2.external_idents, -- Primary Establishment
                eia3.external_idents, -- Primary Legal Unit
                '{}'::jsonb
            ) AS external_idents,
            t.name::varchar,
            t.birth_date,
            t.death_date,
            t.search,
            t.primary_activity_category_id,
            t.primary_activity_category_path,
            t.primary_activity_category_code,
            t.secondary_activity_category_id,
            t.secondary_activity_category_path,
            t.secondary_activity_category_code,
            t.activity_category_paths,
            t.sector_id,
            t.sector_path,
            t.sector_code,
            t.sector_name,
            t.data_source_ids,
            t.data_source_codes,
            t.legal_form_id,
            t.legal_form_code,
            t.legal_form_name,
            t.physical_address_part1,
            t.physical_address_part2,
            t.physical_address_part3,
            t.physical_postcode,
            t.physical_postplace,
            t.physical_region_id,
            t.physical_region_path,
            t.physical_region_code,
            t.physical_country_id,
            t.physical_country_iso_2,
            t.physical_latitude,
            t.physical_longitude,
            t.physical_altitude,
            t.domestic,
            t.postal_address_part1,
            t.postal_address_part2,
            t.postal_address_part3,
            t.postal_postcode,
            t.postal_postplace,
            t.postal_region_id,
            t.postal_region_path,
            t.postal_region_code,
            t.postal_country_id,
            t.postal_country_iso_2,
            t.postal_latitude,
            t.postal_longitude,
            t.postal_altitude,
            t.web_address,
            t.email_address,
            t.phone_number,
            t.landline,
            t.mobile_number,
            t.fax_number,
            t.unit_size_id,
            t.unit_size_code,
            t.status_id,
            t.status_code,
            t.used_for_counting,
            t.last_edit_comment,
            t.last_edit_by_user_id,
            t.last_edit_at,
            t.invalid_codes,
            t.has_legal_unit,
            t.related_establishment_ids,
            t.excluded_establishment_ids,
            t.included_establishment_ids,
            t.related_legal_unit_ids,
            t.excluded_legal_unit_ids,
            t.included_legal_unit_ids,
            t.related_enterprise_ids,
            t.excluded_enterprise_ids,
            t.included_enterprise_ids,
            NULL::JSONB AS stats,
            t.stats_summary,
            array_length(t.included_establishment_ids, 1) AS included_establishment_count,
            array_length(t.included_legal_unit_ids, 1) AS included_legal_unit_count,
            array_length(t.included_enterprise_ids, 1) AS included_enterprise_count,
            COALESCE(tpa.tag_paths, ARRAY[]::public.ltree[]) AS tag_paths
        FROM public.timeline_enterprise t
        LEFT JOIN LATERAL (
            SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents
            FROM public.external_ident ei
            JOIN public.external_ident_type eit ON ei.type_id = eit.id
            WHERE ei.enterprise_id = t.unit_id
        ) eia1 ON true
        LEFT JOIN LATERAL (
            SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents
            FROM public.external_ident ei
            JOIN public.external_ident_type eit ON ei.type_id = eit.id
            WHERE ei.establishment_id = t.primary_establishment_id
        ) eia2 ON true
        LEFT JOIN LATERAL (
            SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents
            FROM public.external_ident ei
            JOIN public.external_ident_type eit ON ei.type_id = eit.id
            WHERE ei.legal_unit_id = t.primary_legal_unit_id
        ) eia3 ON true
        LEFT JOIN LATERAL (
            SELECT array_agg(tag.path ORDER BY tag.path) AS tag_paths
            FROM public.tag_for_unit tfu
            JOIN public.tag ON tfu.tag_id = tag.id
            WHERE tfu.enterprise_id = t.unit_id
        ) tpa ON true
        WHERE t.unit_id <@ p_id_ranges;
    END IF;
END;
$function$;

END;
