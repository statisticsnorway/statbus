BEGIN;

CREATE OR REPLACE VIEW public.timeline_establishment_def
    ( unit_type
    , unit_id
    , valid_from
    , valid_to
    , valid_until
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
    , include_unit_in_reports
    --
    , last_edit_comment
    , last_edit_by_user_id
    , last_edit_at
    --
    , invalid_codes
    , has_legal_unit
    , establishment_id
    , legal_unit_id
    , enterprise_id
    --
    , primary_for_enterprise
    , primary_for_legal_unit
    --
    , stats
    , stats_summary
    , related_establishment_ids
    , excluded_establishment_ids
    , included_establishment_ids
    , related_legal_unit_ids
    , excluded_legal_unit_ids
    , included_legal_unit_ids
    , related_enterprise_ids
    , excluded_enterprise_ids
    , included_enterprise_ids
    )
    AS
      WITH establishment_stats AS (
        SELECT
            t.unit_id,
            t.valid_from,
            jsonb_object_agg(
                sd.code,
                CASE
                    WHEN sfu.value_float IS NOT NULL THEN to_jsonb(sfu.value_float)
                    WHEN sfu.value_int IS NOT NULL THEN to_jsonb(sfu.value_int)
                    WHEN sfu.value_string IS NOT NULL THEN to_jsonb(sfu.value_string)
                    WHEN sfu.value_bool IS NOT NULL THEN to_jsonb(sfu.value_bool)
                END
            ) FILTER (WHERE sd.code IS NOT NULL) AS stats
        FROM public.timesegments AS t
        JOIN public.stat_for_unit AS sfu
            ON sfu.establishment_id = t.unit_id
            AND from_until_overlaps(t.valid_from, t.valid_until, sfu.valid_from, sfu.valid_until)
        JOIN public.stat_definition AS sd
            ON sfu.stat_definition_id = sd.id
        WHERE t.unit_type = 'establishment'
        GROUP BY t.unit_id, t.valid_from
      )
      SELECT t.unit_type
           , t.unit_id
           , t.valid_from
           , (t.valid_until - '1 day'::INTERVAL)::DATE AS valid_to
           , t.valid_until
           , es.name AS name
           , es.birth_date AS birth_date
           , es.death_date AS death_date
           -- Se supported languages with `SELECT * FROM pg_ts_config`
           , to_tsvector('simple', es.name) AS search
           --
           , pa.category_id AS primary_activity_category_id
           , pac.path                AS primary_activity_category_path
           , pac.code                AS primary_activity_category_code
           --
           , sa.category_id AS secondary_activity_category_id
           , sac.path                AS secondary_activity_category_path
           , sac.code                AS secondary_activity_category_code
           --
           , NULLIF(ARRAY_REMOVE(ARRAY[pac.path, sac.path], NULL), '{}') AS activity_category_paths
           --
           , s.id   AS sector_id
           , s.path AS sector_path
           , s.code AS sector_code
           , s.name AS sector_name
           --
           , COALESCE(ds.ids, ARRAY[]::INTEGER[]) AS data_source_ids
           , COALESCE(ds.codes, ARRAY[]::TEXT[]) AS data_source_codes
           --
           , NULL::INTEGER AS legal_form_id
           , NULL::TEXT    AS legal_form_code
           , NULL::TEXT    AS legal_form_name
           --
           , phl.address_part1 AS physical_address_part1
           , phl.address_part2 AS physical_address_part2
           , phl.address_part3 AS physical_address_part3
           , phl.postcode AS physical_postcode
           , phl.postplace AS physical_postplace
           , phl.region_id           AS physical_region_id
           , phr.path                AS physical_region_path
           , phr.code                AS physical_region_code
           , phl.country_id AS physical_country_id
           , phc.iso_2     AS physical_country_iso_2
           , phl.latitude  AS physical_latitude
           , phl.longitude AS physical_longitude
           , phl.altitude  AS physical_altitude
           --
           , pol.address_part1 AS postal_address_part1
           , pol.address_part2 AS postal_address_part2
           , pol.address_part3 AS postal_address_part3
           , pol.postcode AS postal_postcode
           , pol.postplace AS postal_postplace
           , pol.region_id           AS postal_region_id
           , por.path                AS postal_region_path
           , por.code                AS postal_region_code
           , pol.country_id AS postal_country_id
           , poc.iso_2     AS postal_country_iso_2
           , pol.latitude  AS postal_latitude
           , pol.longitude AS postal_longitude
           , pol.altitude  AS postal_altitude
           --
           , c.web_address AS web_address
           , c.email_address AS email_address
           , c.phone_number AS phone_number
           , c.landline AS landline
           , c.mobile_number AS mobile_number
           , c.fax_number AS fax_number
           --
           , es.unit_size_id AS unit_size_id
           , us.code AS unit_size_code
           --
           , es.status_id AS status_id
           , st.code AS status_code
           , st.include_unit_in_reports AS include_unit_in_reports
           --
           , last_edit.edit_comment AS last_edit_comment
           , last_edit.edit_by_user_id AS last_edit_by_user_id
           , last_edit.edit_at AS last_edit_at
           --
           , es.invalid_codes AS invalid_codes
           --
           , (es.legal_unit_id IS NOT NULL) AS has_legal_unit
           --
           , es.id AS establishment_id
           , es.legal_unit_id AS legal_unit_id
           , es.enterprise_id AS enterprise_id
           --
           , es.primary_for_enterprise AS primary_for_enterprise
           , es.primary_for_legal_unit AS primary_for_legal_unit
           --
           , COALESCE(es_stats.stats, '{}'::JSONB) AS stats
           -- FINESSE: An establishment is the lowest-level unit. Its `stats_summary` is generated
           -- directly from its own `stats`. This pre-calculation is critical for enabling
           -- consistent, incremental roll-ups at higher levels of the hierarchy (legal unit, enterprise).
           , public.jsonb_stats_to_summary('{}'::jsonb, COALESCE(es_stats.stats, '{}'::JSONB)) AS stats_summary
           -- 'included_*' arrays form a directed acyclic graph (DAG) for statistical roll-ups.
           -- A unit includes IDs of units below it in the hierarchy, plus itself.
           -- E.g., a legal_unit includes its establishments' IDs; an establishment includes its own ID.
           -- A child NEVER includes its parent's ID in this array. This prevents double-counting stats during roll-ups.
           , ARRAY[t.unit_id] AS related_establishment_ids
           , ARRAY[]::INT[] AS excluded_establishment_ids
           , CASE WHEN st.include_unit_in_reports THEN ARRAY[t.unit_id] ELSE '{}'::INT[] END AS included_establishment_ids
           , CASE WHEN es.legal_unit_id IS NOT NULL THEN ARRAY[es.legal_unit_id] ELSE ARRAY[]::INT[] END AS related_legal_unit_ids
           , ARRAY[]::INT[] AS excluded_legal_unit_ids
           , ARRAY[]::INT[] AS included_legal_unit_ids
           , CASE WHEN es.enterprise_id IS NOT NULL THEN ARRAY[es.enterprise_id] ELSE ARRAY[]::INT[] END AS related_enterprise_ids
           , ARRAY[]::INT[] AS excluded_enterprise_ids
           , ARRAY[]::INT[] AS included_enterprise_ids
      --
      FROM public.timesegments AS t
      JOIN LATERAL (
          SELECT * FROM public.establishment es_1
          WHERE es_1.id = t.unit_id AND from_until_overlaps(t.valid_from, t.valid_until, es_1.valid_from, es_1.valid_until)
          ORDER BY es_1.id DESC, es_1.valid_from DESC LIMIT 1
      ) es ON true
      LEFT JOIN establishment_stats AS es_stats
          ON es_stats.unit_id = t.unit_id AND es_stats.valid_from = t.valid_from
      --
      LEFT JOIN LATERAL (SELECT a.* FROM public.activity a WHERE a.establishment_id = es.id AND a.type = 'primary' AND from_until_overlaps(t.valid_from, t.valid_until, a.valid_from, a.valid_until) ORDER BY a.id DESC LIMIT 1) pa ON true
      LEFT JOIN public.activity_category AS pac
              ON pa.category_id = pac.id
      --
      LEFT JOIN LATERAL (SELECT a.* FROM public.activity a WHERE a.establishment_id = es.id AND a.type = 'secondary' AND from_until_overlaps(t.valid_from, t.valid_until, a.valid_from, a.valid_until) ORDER BY a.id DESC LIMIT 1) sa ON true
      LEFT JOIN public.activity_category AS sac
              ON sa.category_id = sac.id
      --
      LEFT OUTER JOIN public.sector AS s
              ON es.sector_id = s.id
      --
      LEFT JOIN LATERAL (SELECT l.* FROM public.location l WHERE l.establishment_id = es.id AND l.type = 'physical' AND from_until_overlaps(t.valid_from, t.valid_until, l.valid_from, l.valid_until) ORDER BY l.id DESC LIMIT 1) phl ON true
      LEFT JOIN public.region AS phr
              ON phl.region_id = phr.id
      LEFT JOIN public.country AS phc
              ON phl.country_id = phc.id
      --
      LEFT JOIN LATERAL (SELECT l.* FROM public.location l WHERE l.establishment_id = es.id AND l.type = 'postal' AND from_until_overlaps(t.valid_from, t.valid_until, l.valid_from, l.valid_until) ORDER BY l.id DESC LIMIT 1) pol ON true
      LEFT JOIN public.region AS por
              ON pol.region_id = por.id
      LEFT JOIN public.country AS poc
              ON pol.country_id = poc.id
      LEFT JOIN LATERAL (SELECT c_1.* FROM public.contact c_1 WHERE c_1.establishment_id = es.id AND from_until_overlaps(t.valid_from, t.valid_until, c_1.valid_from, c_1.valid_until) ORDER BY c_1.id DESC LIMIT 1) c ON true
      LEFT JOIN public.unit_size AS us
              ON es.unit_size_id = us.id
      LEFT JOIN public.status AS st
              ON es.status_id = st.id
      LEFT JOIN LATERAL (
            SELECT array_agg(DISTINCT sfu.data_source_id) FILTER (WHERE sfu.data_source_id IS NOT NULL) AS data_source_ids
            FROM public.stat_for_unit AS sfu
            WHERE sfu.establishment_id = es.id
              AND from_until_overlaps(t.valid_from, t.valid_until, sfu.valid_from, sfu.valid_until)
        ) AS sfu ON TRUE
      LEFT JOIN LATERAL (
        SELECT array_agg(ds.id) AS ids
             , array_agg(ds.code) AS codes
        FROM public.data_source AS ds
        WHERE COALESCE(ds.id = es.data_source_id       , FALSE)
           OR COALESCE(ds.id = pa.data_source_id       , FALSE)
           OR COALESCE(ds.id = sa.data_source_id       , FALSE)
           OR COALESCE(ds.id = phl.data_source_id      , FALSE)
           OR COALESCE(ds.id = pol.data_source_id      , FALSE)
           OR COALESCE(ds.id = ANY(sfu.data_source_ids), FALSE)
        ) AS ds ON TRUE
      LEFT JOIN LATERAL (
        SELECT edit_comment, edit_by_user_id, edit_at
        FROM (
          VALUES
            (es.edit_comment, es.edit_by_user_id, es.edit_at),
            (pa.edit_comment, pa.edit_by_user_id, pa.edit_at),
            (sa.edit_comment, sa.edit_by_user_id, sa.edit_at),
            (phl.edit_comment, phl.edit_by_user_id, phl.edit_at),
            (pol.edit_comment, pol.edit_by_user_id, pol.edit_at),
            (c.edit_comment, c.edit_by_user_id, c.edit_at)
        ) AS all_edits(edit_comment, edit_by_user_id, edit_at)
        WHERE edit_at IS NOT NULL
        ORDER BY edit_at DESC
        LIMIT 1
      ) AS last_edit ON TRUE
      --
      ORDER BY t.unit_type, t.unit_id, t.valid_from
;

DROP TABLE IF EXISTS public.timeline_establishment;

-- Create the physical table to store the view results
CREATE TABLE public.timeline_establishment AS
SELECT * FROM public.timeline_establishment_def
WHERE FALSE;

-- Add constraints to the physical table
ALTER TABLE public.timeline_establishment
    ADD PRIMARY KEY (unit_type, unit_id, valid_from),
    ALTER COLUMN unit_type SET NOT NULL,
    ALTER COLUMN unit_id SET NOT NULL,
    ALTER COLUMN valid_from SET NOT NULL,
    ALTER COLUMN valid_to SET NOT NULL,
    ALTER COLUMN valid_until SET NOT NULL;

-- Create indices to optimize queries
CREATE INDEX IF NOT EXISTS idx_timeline_establishment_lu_daterange ON public.timeline_establishment
    USING gist (daterange(valid_from, valid_until, '[)'), legal_unit_id) WHERE legal_unit_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_timeline_establishment_en_daterange ON public.timeline_establishment
    USING gist (daterange(valid_from, valid_until, '[)'), enterprise_id) WHERE enterprise_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_timeline_establishment_valid_period ON public.timeline_establishment
    (valid_from, valid_until);
CREATE INDEX IF NOT EXISTS idx_timeline_establishment_primary_for_enterprise ON public.timeline_establishment
    (primary_for_enterprise) WHERE primary_for_enterprise = true;
CREATE INDEX IF NOT EXISTS idx_timeline_establishment_primary_for_legal_unit ON public.timeline_establishment
    (primary_for_legal_unit) WHERE primary_for_legal_unit = true;
CREATE INDEX IF NOT EXISTS idx_timeline_establishment_establishment_id ON public.timeline_establishment
    (establishment_id) WHERE establishment_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_timeline_establishment_legal_unit_id ON public.timeline_establishment
    (legal_unit_id) WHERE legal_unit_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_timeline_establishment_enterprise_id ON public.timeline_establishment
    (enterprise_id) WHERE enterprise_id IS NOT NULL;


-- Create a function to refresh the timeline_establishment table
CREATE OR REPLACE PROCEDURE public.timeline_refresh(p_target_table text, p_unit_type public.statistical_unit_type, p_unit_id_ranges int4multirange DEFAULT NULL)
LANGUAGE plpgsql AS $procedure$
DECLARE
    v_batch_size INT := 65536;
    v_def_view_name text := p_target_table || '_def';
    v_min_id int; v_max_id int; v_start_id int; v_end_id int;
    v_batch_num INT := 0;
    v_total_units INT;
    v_batch_start_time timestamptz;
    v_batch_duration_ms numeric;
    v_batch_speed numeric;
    v_current_batch_size int;
BEGIN
    IF p_unit_id_ranges IS NOT NULL THEN
        EXECUTE format('DELETE FROM public.%I WHERE unit_type = %L AND unit_id <@ %L::int4multirange', p_target_table, p_unit_type, p_unit_id_ranges);
        EXECUTE format('INSERT INTO public.%I SELECT * FROM public.%I WHERE unit_type = %L AND unit_id <@ %L::int4multirange',
                       p_target_table, v_def_view_name, p_unit_type, p_unit_id_ranges);
    ELSE
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = p_unit_type;
        IF v_min_id IS NULL THEN RETURN; END IF;

        RAISE DEBUG 'Refreshing % for % units in batches of %...', p_target_table, v_total_units, v_batch_size;
        FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_start_time := clock_timestamp();
            v_batch_num := v_batch_num + 1;
            v_start_id := i; v_end_id := i + v_batch_size - 1;

            EXECUTE format('DELETE FROM public.%I WHERE unit_type = %L AND unit_id BETWEEN %L AND %L',
                           p_target_table, p_unit_type, v_start_id, v_end_id);
            EXECUTE format('INSERT INTO public.%I SELECT * FROM public.%I WHERE unit_type = %L AND unit_id BETWEEN %L AND %L',
                           p_target_table, v_def_view_name, p_unit_type, v_start_id, v_end_id);

            v_batch_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_batch_start_time))) * 1000;
            v_current_batch_size := v_batch_size; -- Simplified for this loop type
            v_batch_speed := v_current_batch_size / (v_batch_duration_ms / 1000.0);
            RAISE DEBUG '% batch %/% done. (% units, % ms, % units/s)', p_target_table, v_batch_num, ceil(v_total_units::decimal / v_batch_size), v_current_batch_size, round(v_batch_duration_ms), round(v_batch_speed);
        END LOOP;
    END IF;

    EXECUTE format('ANALYZE public.%I', p_target_table);
END;
$procedure$;

CREATE OR REPLACE PROCEDURE public.timeline_establishment_refresh(p_unit_id_ranges int4multirange DEFAULT NULL) LANGUAGE plpgsql AS $$
BEGIN
    ANALYZE public.timesegments, public.establishment, public.activity, public.location, public.contact, public.stat_for_unit;
    CALL public.timeline_refresh('timeline_establishment', 'establishment', p_unit_id_ranges);
END;
$$;

-- Initial population of the timeline_establishment table
CALL public.timeline_establishment_refresh();

END;
