-- Down migration for STATBUS-460: restore the record-validity definitions verbatim (dumped with \sf before the change).
BEGIN;

CREATE OR REPLACE FUNCTION public.legal_unit_hierarchy(legal_unit_id integer, parent_enterprise_id integer, scope hierarchy_scope DEFAULT 'all'::hierarchy_scope, valid_on date DEFAULT CURRENT_DATE, primary_only boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  WITH ordered_data AS (
    SELECT to_jsonb(lu.*)
        || (SELECT public.external_idents_hierarchy(NULL,lu.id,NULL,NULL))
        || (SELECT public.power_group_membership_hierarchy(lu.id, valid_on, primary_only))
        || CASE WHEN scope IN ('all','tree') THEN (SELECT public.establishment_hierarchy(NULL, lu.id, NULL, scope, valid_on)) ELSE '{}'::JSONB END
        || (SELECT public.activity_hierarchy(NULL,lu.id,valid_on))
        || (SELECT public.location_hierarchy(NULL,lu.id,valid_on))
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.stat_for_unit_hierarchy(NULL,lu.id,valid_on)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.sector_hierarchy(lu.sector_id)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.unit_size_hierarchy(lu.unit_size_id)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.status_hierarchy(lu.status_id)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.legal_form_hierarchy(lu.legal_form_id)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.contact_hierarchy(NULL,lu.id,valid_on)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.data_source_hierarchy(lu.data_source_id)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.notes_for_unit(NULL,lu.id,NULL,NULL)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.tag_for_unit_hierarchy(NULL,lu.id,NULL,NULL)) ELSE '{}'::JSONB END
        AS data
    FROM public.legal_unit AS lu
   WHERE (  (legal_unit_id IS NOT NULL AND lu.id = legal_unit_id)
         OR (parent_enterprise_id IS NOT NULL AND lu.enterprise_id = parent_enterprise_id)
         )
     AND lu.valid_from <= valid_on AND valid_on < lu.valid_until
   ORDER BY lu.primary_for_enterprise DESC, lu.name
  ), data_list AS (
      SELECT jsonb_agg(data) AS data FROM ordered_data
  )
  SELECT CASE
    WHEN data IS NULL THEN '{}'::JSONB
    ELSE jsonb_build_object('legal_unit',data)
    END
  FROM data_list;
$function$
;

CREATE OR REPLACE FUNCTION public.establishment_hierarchy(establishment_id integer, parent_legal_unit_id integer, parent_enterprise_id integer, scope hierarchy_scope DEFAULT 'all'::hierarchy_scope, valid_on date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  WITH ordered_data AS (
    SELECT to_jsonb(es.*)
        || (SELECT public.external_idents_hierarchy(es.id,NULL,NULL,NULL))
        || (SELECT public.activity_hierarchy(es.id,NULL,valid_on))
        || (SELECT public.location_hierarchy(es.id,NULL,valid_on))
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.stat_for_unit_hierarchy(es.id,NULL,valid_on)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.sector_hierarchy(es.sector_id)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.unit_size_hierarchy(es.unit_size_id)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.status_hierarchy(es.status_id)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.contact_hierarchy(es.id,NULL,valid_on)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.data_source_hierarchy(es.data_source_id)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.notes_for_unit(es.id,NULL,NULL,NULL)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.tag_for_unit_hierarchy(es.id,NULL,NULL,NULL)) ELSE '{}'::JSONB END
        AS data
    FROM public.establishment AS es
   WHERE (  (establishment_id IS NOT NULL AND es.id = establishment_id)
         OR (parent_legal_unit_id IS NOT NULL AND es.legal_unit_id = parent_legal_unit_id)
         OR (parent_enterprise_id IS NOT NULL AND es.enterprise_id = parent_enterprise_id)
         )
     AND es.valid_from <= valid_on AND valid_on < es.valid_until
   ORDER BY es.primary_for_legal_unit DESC, es.name
  ), data_list AS (
      SELECT jsonb_agg(data) AS data FROM ordered_data
  )
  SELECT CASE
    WHEN data IS NULL THEN '{}'::JSONB
    ELSE jsonb_build_object('establishment',data)
    END
  FROM data_list;
$function$
;

CREATE OR REPLACE FUNCTION public.statistical_unit_enterprise_id(unit_type statistical_unit_type, unit_id integer, valid_on date DEFAULT CURRENT_DATE)
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE unit_type
         WHEN 'establishment' THEN (
            WITH selected_establishment AS (
                SELECT es.id, es.enterprise_id, es.legal_unit_id, es.valid_from, es.valid_to
                FROM public.establishment AS es
                WHERE es.id = unit_id
                  AND es.valid_from <= valid_on AND valid_on < es.valid_until
            )
            -- Either the establishment has a a direct enterprise connection
            SELECT enterprise_id FROM selected_establishment WHERE enterprise_id IS NOT NULL
            UNION ALL
            -- Or connects to an enterprise through it's legal unit.
            SELECT lu.enterprise_id
            FROM selected_establishment AS es
            JOIN public.legal_unit AS lu ON es.legal_unit_id = lu.id
            WHERE lu.valid_from <= valid_on AND valid_on < lu.valid_until
         )
         WHEN 'legal_unit' THEN (
             -- A legal_unit is always connected to an enterprise.
             SELECT lu.enterprise_id
               FROM public.legal_unit AS lu
              WHERE lu.id = unit_id
                AND lu.valid_from <= valid_on AND valid_on < lu.valid_until
         )
         WHEN 'enterprise' THEN (
            -- Handle both formal (legal unit) and informal (establishment) connections
            -- Return the enterprise ID if it matches either connection type
            SELECT DISTINCT unit_id AS enterprise_id
            FROM (
                SELECT lu.enterprise_id
                FROM public.legal_unit AS lu
                WHERE lu.enterprise_id = unit_id
                  AND lu.valid_from <= valid_on AND valid_on < lu.valid_until
                UNION ALL
                SELECT es.enterprise_id
                FROM public.establishment AS es
                WHERE es.enterprise_id = unit_id
                  AND es.valid_from <= valid_on AND valid_on < es.valid_until
            ) combined_connections
            WHERE enterprise_id IS NOT NULL
         )
         WHEN 'power_group' THEN (
            -- A power group's enterprise is the enterprise of its root legal unit (power_level = 0).
            SELECT lu.enterprise_id
            FROM public.power_group_membership AS pgm
            JOIN public.legal_unit AS lu
                ON lu.id = pgm.legal_unit_id
                AND lu.valid_from <= valid_on AND valid_on < lu.valid_until
            WHERE pgm.power_group_id = unit_id
              AND pgm.power_level = 0
              AND pgm.valid_range @> valid_on
            LIMIT 1
         )
         END
  ;
$function$
;

CREATE OR REPLACE FUNCTION public.statistical_unit_stats(unit_type statistical_unit_type, unit_id integer, valid_on date DEFAULT CURRENT_DATE)
 RETURNS SETOF statistical_unit_stats
 LANGUAGE sql
 STABLE
AS $function$
    WITH root_unit AS (
        SELECT su.unit_id,
               su.related_legal_unit_ids,
               su.related_establishment_ids
        FROM public.statistical_unit AS su
        WHERE su.unit_type = 'enterprise'
          AND su.unit_id = public.statistical_unit_enterprise_id($1, $2, $3)
          AND su.valid_from <= $3 AND $3 < su.valid_until
    ), relevant_ids AS (
        SELECT 'enterprise'::statistical_unit_type AS unit_type, ru.unit_id FROM root_unit AS ru
        UNION ALL
        SELECT 'legal_unit'::statistical_unit_type, unnest(ru.related_legal_unit_ids) FROM root_unit AS ru
        UNION ALL
        SELECT 'establishment'::statistical_unit_type, unnest(ru.related_establishment_ids) FROM root_unit AS ru
    )
    SELECT su.unit_type, su.unit_id, su.valid_from, su.valid_to, su.stats, su.stats_summary
    FROM relevant_ids AS ri
    JOIN public.statistical_unit AS su
      ON su.unit_type = ri.unit_type
     AND su.unit_id = ri.unit_id
     AND su.valid_from <= $3 AND $3 < su.valid_until
    ORDER BY su.unit_type, su.unit_id;
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
          AND su.valid_from <= $3 AND $3 < su.valid_until
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
         AND su.valid_from <= $3 AND $3 < su.valid_until
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
         , physical_latitude
         , physical_longitude
         , physical_altitude
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
         , postal_latitude
         , postal_longitude
         , postal_altitude
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

CREATE OR REPLACE FUNCTION public.statistical_history_def(p_resolution history_resolution, p_year integer, p_month integer, p_hash_partition int4range DEFAULT NULL::int4range)
 RETURNS SETOF statistical_history_type
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_curr_start date;
    v_curr_stop date;
    v_prev_start date;
    v_prev_stop date;
BEGIN
    IF p_resolution = 'year'::public.history_resolution THEN
        v_curr_start := make_date(p_year, 1, 1);
        v_curr_stop  := make_date(p_year, 12, 31);
        v_prev_start := make_date(p_year - 1, 1, 1);
        v_prev_stop  := make_date(p_year - 1, 12, 31);
    ELSE -- 'year-month'
        v_curr_start := make_date(p_year, p_month, 1);
        v_curr_stop  := (v_curr_start + interval '1 month') - interval '1 day';
        v_prev_stop  := v_curr_start - interval '1 day';
        v_prev_start := date_trunc('month', v_prev_stop)::date;
    END IF;

    RETURN QUERY
    WITH
    units_in_period AS (
        SELECT *
        FROM public.statistical_unit su
        WHERE public.from_to_overlaps(su.valid_from, su.valid_to, v_prev_start, v_curr_stop)
          -- When computing a partition range, filter by hash_slot within the range.
          -- Use explicit half-open bounds (not <@) so the btree index on
          -- statistical_unit(hash_slot) is used at 2.2M-row scale.
          AND (p_hash_partition IS NULL
               OR (su.hash_slot >= lower(p_hash_partition)
                   AND su.hash_slot <  upper(p_hash_partition)))
    ),
    latest_versions_curr AS (
        SELECT DISTINCT ON (uip.unit_id, uip.unit_type) uip.*
        FROM units_in_period AS uip
        WHERE uip.valid_from <= v_curr_stop AND uip.valid_to >= v_curr_start
        ORDER BY uip.unit_id, uip.unit_type, uip.valid_from DESC, uip.valid_until DESC
    ),
    latest_versions_prev AS (
        SELECT DISTINCT ON (uip.unit_id, uip.unit_type) uip.*
        FROM units_in_period AS uip
        WHERE uip.valid_from <= v_prev_stop
        ORDER BY uip.unit_id, uip.unit_type, uip.valid_from DESC, uip.valid_until DESC
    ),
    stock_at_end_of_curr AS (
        SELECT * FROM latest_versions_curr lvc
        WHERE lvc.valid_until > v_curr_stop
          AND COALESCE(lvc.birth_date, lvc.valid_from) <= v_curr_stop
          AND (lvc.death_date IS NULL OR lvc.death_date > v_curr_stop)
    ),
    stock_at_end_of_prev AS (
        SELECT * FROM latest_versions_prev lvp
        WHERE lvp.valid_until > v_prev_stop
          AND COALESCE(lvp.birth_date, lvp.valid_from) <= v_prev_stop
          AND (lvp.death_date IS NULL OR lvp.death_date > v_prev_stop)
    ),
    changed_units AS (
        SELECT
            COALESCE(c.unit_id, p.unit_id) AS unit_id,
            COALESCE(c.unit_type, p.unit_type) AS unit_type,
            -- hash_slot is stable per unit (function of unit_type + unit_id),
            -- so c and p (when both present) carry the same value.
            COALESCE(c.hash_slot, p.hash_slot) AS hash_slot,
            c AS curr,
            p AS prev,
            lvc AS last_version_in_curr
        FROM stock_at_end_of_curr c
        FULL JOIN stock_at_end_of_prev p ON c.unit_id = p.unit_id AND c.unit_type = p.unit_type
        LEFT JOIN latest_versions_curr lvc ON lvc.unit_id = COALESCE(p.unit_id, c.unit_id) AND lvc.unit_type = COALESCE(p.unit_type, c.unit_type)
    ),
    stats_by_slot AS (
        SELECT
            lvc.unit_type,
            lvc.hash_slot,
            COALESCE(public.jsonb_stats_merge_agg(lvc.stats_summary), '{}'::jsonb) AS stats_summary
        FROM latest_versions_curr lvc
        WHERE lvc.used_for_counting
        GROUP BY lvc.unit_type, lvc.hash_slot
    ),
    demographics AS (
        SELECT
            p_resolution, p_year, p_month, unit_type, hash_slot,
            count((curr).unit_id)::integer AS exists_count,
            (count((curr).unit_id) - count((prev).unit_id))::integer AS exists_change,
            count((curr).unit_id) FILTER (WHERE (prev).unit_id IS NULL)::integer AS exists_added_count,
            count((prev).unit_id) FILTER (WHERE (curr).unit_id IS NULL)::integer AS exists_removed_count,
            count((curr).unit_id) FILTER (WHERE (curr).used_for_counting)::integer AS countable_count,
            (count((curr).unit_id) FILTER (WHERE (curr).used_for_counting) - count((prev).unit_id) FILTER (WHERE (prev).used_for_counting))::integer AS countable_change,
            count(*) FILTER (WHERE (curr).used_for_counting AND NOT COALESCE((prev).used_for_counting, false))::integer AS countable_added_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND NOT COALESCE((curr).used_for_counting, false))::integer AS countable_removed_count,
            count(*) FILTER (WHERE (last_version_in_curr).used_for_counting AND (last_version_in_curr).birth_date BETWEEN v_curr_start AND v_curr_stop)::integer AS births,
            count(*) FILTER (WHERE (last_version_in_curr).used_for_counting AND (last_version_in_curr).death_date BETWEEN v_curr_start AND v_curr_stop)::integer AS deaths,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).name IS DISTINCT FROM (prev).name)::integer AS name_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).primary_activity_category_path IS DISTINCT FROM (prev).primary_activity_category_path)::integer AS primary_activity_category_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).secondary_activity_category_path IS DISTINCT FROM (prev).secondary_activity_category_path)::integer AS secondary_activity_category_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).sector_path IS DISTINCT FROM (prev).sector_path)::integer AS sector_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).legal_form_id IS DISTINCT FROM (prev).legal_form_id)::integer AS legal_form_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).physical_region_path IS DISTINCT FROM (prev).physical_region_path)::integer AS physical_region_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).physical_country_id IS DISTINCT FROM (prev).physical_country_id)::integer AS physical_country_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND ((curr).physical_address_part1, (curr).physical_address_part2, (curr).physical_address_part3, (curr).physical_postcode, (curr).physical_postplace) IS DISTINCT FROM ((prev).physical_address_part1, (prev).physical_address_part2, (prev).physical_address_part3, (prev).physical_postcode, (prev).physical_postplace))::integer AS physical_address_change_count
        FROM changed_units
        GROUP BY 1, 2, 3, 4, 5
    )
    SELECT
        d.p_resolution AS resolution, d.p_year AS year, d.p_month AS month, d.unit_type,
        d.exists_count, d.exists_change, d.exists_added_count, d.exists_removed_count,
        d.countable_count, d.countable_change, d.countable_added_count, d.countable_removed_count,
        d.births, d.deaths,
        d.name_change_count, d.primary_activity_category_change_count, d.secondary_activity_category_change_count,
        d.sector_change_count, d.legal_form_change_count, d.physical_region_change_count,
        d.physical_country_change_count, d.physical_address_change_count,
        COALESCE(sbs.stats_summary, '{}'::jsonb) AS stats_summary,
        -- Slot-keyed storage: each output row corresponds to exactly one slot.
        -- The hash_partition column stores int4range(hash_slot, hash_slot+1).
        int4range(d.hash_slot, d.hash_slot + 1) AS hash_partition
    FROM demographics d
    LEFT JOIN stats_by_slot sbs ON sbs.unit_type = d.unit_type AND sbs.hash_slot = d.hash_slot;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.statistical_history_facet_def(p_resolution history_resolution, p_year integer, p_month integer, p_hash_partition int4range DEFAULT NULL::int4range)
 RETURNS SETOF statistical_history_facet_partitions
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_curr_start date;
    v_curr_stop date;
    v_prev_start date;
    v_prev_stop date;
BEGIN
    IF p_resolution = 'year'::public.history_resolution THEN
        v_curr_start := make_date(p_year, 1, 1);
        v_curr_stop  := make_date(p_year, 12, 31);
        v_prev_start := make_date(p_year - 1, 1, 1);
        v_prev_stop  := make_date(p_year - 1, 12, 31);
    ELSE
        v_curr_start := make_date(p_year, p_month, 1);
        v_curr_stop  := (v_curr_start + interval '1 month') - interval '1 day';
        v_prev_stop  := v_curr_start - interval '1 day';
        v_prev_start := date_trunc('month', v_prev_stop)::date;
    END IF;

    RETURN QUERY
    WITH
    units_in_period AS (
        SELECT *
        FROM public.statistical_unit su
        WHERE daterange(su.valid_from, su.valid_to, '[)') && daterange(v_prev_start, v_curr_stop + 1, '[)')
          -- Partition filter: explicit half-open bounds hit the btree index on
          -- statistical_unit(hash_slot). Mirrors statistical_history_def.
          AND (p_hash_partition IS NULL
               OR (su.hash_slot >= lower(p_hash_partition)
                   AND su.hash_slot <  upper(p_hash_partition)))
    ),
    latest_versions_curr AS (
        SELECT DISTINCT ON (uip.unit_id, uip.unit_type) uip.*
        FROM units_in_period AS uip
        WHERE uip.valid_from <= v_curr_stop AND uip.valid_to >= v_curr_start
        ORDER BY uip.unit_id, uip.unit_type, uip.valid_from DESC, uip.valid_until DESC
    ),
    latest_versions_prev AS (
        SELECT DISTINCT ON (uip.unit_id, uip.unit_type) uip.*
        FROM units_in_period AS uip
        WHERE uip.valid_from <= v_prev_stop
        ORDER BY uip.unit_id, uip.unit_type, uip.valid_from DESC, uip.valid_until DESC
    ),
    stock_at_end_of_curr AS (
        SELECT * FROM latest_versions_curr lvc
        WHERE lvc.valid_until > v_curr_stop
          AND COALESCE(lvc.birth_date, lvc.valid_from) <= v_curr_stop
          AND (lvc.death_date IS NULL OR lvc.death_date > v_curr_stop)
    ),
    stock_at_end_of_prev AS (
        SELECT * FROM latest_versions_prev lvp
        WHERE lvp.valid_until > v_prev_stop
          AND COALESCE(lvp.birth_date, lvp.valid_from) <= v_prev_stop
          AND (lvp.death_date IS NULL OR lvp.death_date > v_prev_stop)
    ),
    -- PERF: pre-aggregate per-(slot, facet) stats for fast hash join.
    -- hash_slot is a pure function of (unit_type, unit_id) so every lvc row
    -- already has the slot it belongs to.
    stats_by_facet AS (
        SELECT
            hash_slot,
            unit_type::text || '|' ||
            COALESCE(primary_activity_category_path::text, '') || '|' ||
            COALESCE(secondary_activity_category_path::text, '') || '|' ||
            COALESCE(sector_path::text, '') || '|' ||
            COALESCE(legal_form_id::text, '') || '|' ||
            COALESCE(physical_region_path::text, '') || '|' ||
            COALESCE(physical_country_id::text, '') || '|' ||
            COALESCE(unit_size_id::text, '') || '|' ||
            COALESCE(status_id::text, '') AS facet_key,
            COALESCE(public.jsonb_stats_merge_agg(stats_summary), '{}'::jsonb) AS stats_summary
        FROM latest_versions_curr
        WHERE used_for_counting
        GROUP BY 1, 2
    ),
    -- PERF: flatten columns instead of storing entire ROW types. Carry hash_slot
    -- forward via COALESCE(c.hash_slot, p.hash_slot) — both are equal for any
    -- matching (unit_id, unit_type) because hash_slot is a pure function.
    changed_units AS (
        SELECT
            COALESCE(c.unit_id, p.unit_id) AS unit_id,
            COALESCE(c.unit_type, p.unit_type) AS unit_type,
            COALESCE(c.hash_slot, p.hash_slot) AS hash_slot,
            c.unit_id AS c_unit_id, c.used_for_counting AS c_used_for_counting,
            c.primary_activity_category_path AS c_pac_path,
            c.secondary_activity_category_path AS c_sac_path,
            c.sector_path AS c_sector_path, c.legal_form_id AS c_legal_form_id,
            c.physical_region_path AS c_region_path, c.physical_country_id AS c_country_id,
            c.physical_address_part1 AS c_addr1, c.physical_address_part2 AS c_addr2,
            c.physical_address_part3 AS c_addr3, c.physical_postcode AS c_postcode,
            c.physical_postplace AS c_postplace,
            c.unit_size_id AS c_size_id, c.status_id AS c_status_id, c.name AS c_name,
            p.unit_id AS p_unit_id, p.used_for_counting AS p_used_for_counting,
            p.primary_activity_category_path AS p_pac_path,
            p.secondary_activity_category_path AS p_sac_path,
            p.sector_path AS p_sector_path, p.legal_form_id AS p_legal_form_id,
            p.physical_region_path AS p_region_path, p.physical_country_id AS p_country_id,
            p.physical_address_part1 AS p_addr1, p.physical_address_part2 AS p_addr2,
            p.physical_address_part3 AS p_addr3, p.physical_postcode AS p_postcode,
            p.physical_postplace AS p_postplace,
            p.unit_size_id AS p_size_id, p.status_id AS p_status_id, p.name AS p_name,
            lvc.birth_date AS lvc_birth_date, lvc.death_date AS lvc_death_date,
            lvc.used_for_counting AS lvc_used_for_counting
        FROM stock_at_end_of_curr c
        FULL JOIN stock_at_end_of_prev p ON c.unit_id = p.unit_id AND c.unit_type = p.unit_type
        LEFT JOIN latest_versions_curr lvc ON lvc.unit_id = COALESCE(p.unit_id, c.unit_id)
                                 AND lvc.unit_type = COALESCE(p.unit_type, c.unit_type)
    ),
    demographics AS (
        SELECT
            hash_slot,
            p_resolution, p_year, p_month,
            unit_type,
            COALESCE(c_pac_path, p_pac_path) AS primary_activity_category_path,
            COALESCE(c_sac_path, p_sac_path) AS secondary_activity_category_path,
            COALESCE(c_sector_path, p_sector_path) AS sector_path,
            COALESCE(c_legal_form_id, p_legal_form_id) AS legal_form_id,
            COALESCE(c_region_path, p_region_path) AS physical_region_path,
            COALESCE(c_country_id, p_country_id) AS physical_country_id,
            COALESCE(c_size_id, p_size_id) AS unit_size_id,
            COALESCE(c_status_id, p_status_id) AS status_id,
            unit_type::text || '|' ||
            COALESCE(COALESCE(c_pac_path, p_pac_path)::text, '') || '|' ||
            COALESCE(COALESCE(c_sac_path, p_sac_path)::text, '') || '|' ||
            COALESCE(COALESCE(c_sector_path, p_sector_path)::text, '') || '|' ||
            COALESCE(COALESCE(c_legal_form_id, p_legal_form_id)::text, '') || '|' ||
            COALESCE(COALESCE(c_region_path, p_region_path)::text, '') || '|' ||
            COALESCE(COALESCE(c_country_id, p_country_id)::text, '') || '|' ||
            COALESCE(COALESCE(c_size_id, p_size_id)::text, '') || '|' ||
            COALESCE(COALESCE(c_status_id, p_status_id)::text, '') AS facet_key,
            count(c_unit_id)::integer AS exists_count,
            (count(c_unit_id) - count(p_unit_id))::integer AS exists_change,
            count(c_unit_id) FILTER (WHERE p_unit_id IS NULL)::integer AS exists_added_count,
            count(p_unit_id) FILTER (WHERE c_unit_id IS NULL)::integer AS exists_removed_count,
            count(c_unit_id) FILTER (WHERE c_used_for_counting)::integer AS countable_count,
            (count(c_unit_id) FILTER (WHERE c_used_for_counting) - count(p_unit_id) FILTER (WHERE p_used_for_counting))::integer AS countable_change,
            count(*) FILTER (WHERE c_used_for_counting AND NOT COALESCE(p_used_for_counting, false))::integer AS countable_added_count,
            count(*) FILTER (WHERE p_used_for_counting AND NOT COALESCE(c_used_for_counting, false))::integer AS countable_removed_count,
            count(*) FILTER (WHERE lvc_used_for_counting AND lvc_birth_date BETWEEN v_curr_start AND v_curr_stop)::integer AS births,
            count(*) FILTER (WHERE lvc_used_for_counting AND lvc_death_date BETWEEN v_curr_start AND v_curr_stop)::integer AS deaths,
            count(*) FILTER (WHERE p_used_for_counting AND c_used_for_counting AND c_name IS DISTINCT FROM p_name)::integer AS name_change_count,
            count(*) FILTER (WHERE p_used_for_counting AND c_used_for_counting AND c_pac_path IS DISTINCT FROM p_pac_path)::integer AS primary_activity_category_change_count,
            count(*) FILTER (WHERE p_used_for_counting AND c_used_for_counting AND c_sac_path IS DISTINCT FROM p_sac_path)::integer AS secondary_activity_category_change_count,
            count(*) FILTER (WHERE p_used_for_counting AND c_used_for_counting AND c_sector_path IS DISTINCT FROM p_sector_path)::integer AS sector_change_count,
            count(*) FILTER (WHERE p_used_for_counting AND c_used_for_counting AND c_legal_form_id IS DISTINCT FROM p_legal_form_id)::integer AS legal_form_change_count,
            count(*) FILTER (WHERE p_used_for_counting AND c_used_for_counting AND c_region_path IS DISTINCT FROM p_region_path)::integer AS physical_region_change_count,
            count(*) FILTER (WHERE p_used_for_counting AND c_used_for_counting AND c_country_id IS DISTINCT FROM p_country_id)::integer AS physical_country_change_count,
            count(*) FILTER (WHERE p_used_for_counting AND c_used_for_counting AND
                (c_addr1, c_addr2, c_addr3, c_postcode, c_postplace) IS DISTINCT FROM
                (p_addr1, p_addr2, p_addr3, p_postcode, p_postplace))::integer AS physical_address_change_count,
            count(*) FILTER (WHERE p_used_for_counting AND c_used_for_counting AND c_size_id IS DISTINCT FROM p_size_id)::integer AS unit_size_change_count,
            count(*) FILTER (WHERE p_used_for_counting AND c_used_for_counting AND c_status_id IS DISTINCT FROM p_status_id)::integer AS status_change_count
        FROM changed_units
        GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14
    )
    SELECT
        d.hash_slot,
        d.p_resolution AS resolution,
        d.p_year AS year,
        d.p_month AS month,
        d.unit_type,
        d.primary_activity_category_path,
        d.secondary_activity_category_path,
        d.sector_path,
        d.legal_form_id,
        d.physical_region_path,
        d.physical_country_id,
        d.unit_size_id,
        d.status_id,
        d.exists_count,
        d.exists_change,
        d.exists_added_count,
        d.exists_removed_count,
        d.countable_count,
        d.countable_change,
        d.countable_added_count,
        d.countable_removed_count,
        d.births,
        d.deaths,
        d.name_change_count,
        d.primary_activity_category_change_count,
        d.secondary_activity_category_change_count,
        d.sector_change_count,
        d.legal_form_change_count,
        d.physical_region_change_count,
        d.physical_country_change_count,
        d.physical_address_change_count,
        d.unit_size_change_count,
        d.status_change_count,
        COALESCE(s.stats_summary, '{}'::jsonb) AS stats_summary
    FROM demographics d
    LEFT JOIN stats_by_facet s ON s.hash_slot = d.hash_slot AND s.facet_key = d.facet_key;
END;
$function$
;

DROP STATISTICS IF EXISTS public.statistical_unit_existence_stat;

DROP FUNCTION public.existence_until(public.establishment);
DROP FUNCTION public.existence_from(public.establishment);
DROP FUNCTION public.existence_until(public.legal_unit);
DROP FUNCTION public.existence_from(public.legal_unit);
DROP FUNCTION public.existence_until(public.statistical_unit);
DROP FUNCTION public.existence_from(public.statistical_unit);
DROP FUNCTION public.unit_existence_until(date, date);
DROP FUNCTION public.unit_existence_from(date, date);

END;
