BEGIN;

CREATE OR REPLACE VIEW public.timeline_legal_unit_def
    ( unit_type
    , unit_id
    , valid_after
    , valid_from
    , valid_to
    , name
    , birth_date
    , death_date
    , search
    --
    , primary_activity_category_id
    , primary_activity_category_path
    , primary_activity_category_code
    , secondary_activity_category_id
    , secondary_activity_category_path
    , secondary_activity_category_code
    , activity_category_paths
    --
    , sector_id
    , sector_path
    , sector_code
    , sector_name
    --
    , data_source_ids
    , data_source_codes
    --
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
    , related_establishment_ids
    , excluded_establishment_ids
    , included_establishment_ids
    , legal_unit_id
    , enterprise_id
    --
    , primary_for_enterprise
    --
    , stats
    , stats_summary
    )
    AS
      WITH basis AS (
      SELECT t.unit_type
           , t.unit_id
           , t.valid_after
           , (t.valid_after + '1 day'::INTERVAL)::DATE AS valid_from
           , t.valid_to
           , lu.name AS name
           , lu.birth_date AS birth_date
           , lu.death_date AS death_date
           -- Se supported languages with `SELECT * FROM pg_ts_config`
           , to_tsvector('simple', lu.name) AS search
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
           , s.id    AS sector_id
           , s.path  AS sector_path
           , s.code  AS sector_code
           , s.name  AS sector_name
           --
           , COALESCE(ds.ids,ARRAY[]::INTEGER[]) AS data_source_ids
           , COALESCE(ds.codes, ARRAY[]::TEXT[]) AS data_source_codes
           --
           , lf.id   AS legal_form_id
           , lf.code AS legal_form_code
           , lf.name AS legal_form_name
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
           , lu.unit_size_id AS unit_size_id
           , us.code AS unit_size_code
           --
           , lu.status_id AS status_id
           , st.code AS status_code
           , st.include_unit_in_reports AS include_unit_in_reports
           --
           , last_edit.edit_comment AS last_edit_comment
           , last_edit.edit_by_user_id AS last_edit_by_user_id
           , last_edit.edit_at AS last_edit_at
           --
           , lu.invalid_codes AS invalid_codes
           --
           , TRUE AS has_legal_unit
           --
           , lu.id AS legal_unit_id
           , lu.enterprise_id AS enterprise_id
           --
           , lu.primary_for_enterprise AS primary_for_enterprise
           --
           , COALESCE(public.get_jsonb_stats(NULL, lu.id, t.valid_after, t.valid_to), '{}'::JSONB) AS stats
      --
      FROM public.timesegments AS t
      INNER JOIN public.legal_unit AS lu
          ON t.unit_type = 'legal_unit' AND t.unit_id = lu.id
         AND daterange(t.valid_after, t.valid_to, '(]')
          && daterange(lu.valid_after, lu.valid_to, '(]')
      --
      LEFT OUTER JOIN public.activity AS pa
              ON pa.legal_unit_id = lu.id
             AND pa.type = 'primary'
             AND daterange(t.valid_after, t.valid_to, '(]')
              && daterange(pa.valid_after, pa.valid_to, '(]')
      LEFT JOIN public.activity_category AS pac
              ON pa.category_id = pac.id
      --
      LEFT OUTER JOIN public.activity AS sa
              ON sa.legal_unit_id = lu.id
             AND sa.type = 'secondary'
             AND daterange(t.valid_after, t.valid_to, '(]')
              && daterange(sa.valid_after, sa.valid_to, '(]')
      LEFT JOIN public.activity_category AS sac
              ON sa.category_id = sac.id
      --
      LEFT OUTER JOIN public.sector AS s
              ON lu.sector_id = s.id
      --
      LEFT OUTER JOIN public.legal_form AS lf
              ON lu.legal_form_id = lf.id
      --
      LEFT OUTER JOIN public.location AS phl
              ON phl.legal_unit_id = lu.id
             AND phl.type = 'physical'
             AND daterange(t.valid_after, t.valid_to, '(]')
              && daterange(phl.valid_after, phl.valid_to, '(]')
      LEFT JOIN public.region AS phr
              ON phl.region_id = phr.id
      LEFT JOIN public.country AS phc
              ON phl.country_id = phc.id
      --
      LEFT OUTER JOIN public.location AS pol
              ON pol.legal_unit_id = lu.id
             AND pol.type = 'postal'
             AND daterange(t.valid_after, t.valid_to, '(]')
              && daterange(pol.valid_after, pol.valid_to, '(]')
      LEFT JOIN public.region AS por
              ON pol.region_id = por.id
      LEFT JOIN public.country AS poc
              ON pol.country_id = poc.id
      LEFT OUTER JOIN public.contact AS c
              ON c.legal_unit_id = lu.id
             AND daterange(t.valid_after, t.valid_to, '(]')
              && daterange(c.valid_after, c.valid_to, '(]')
      LEFT JOIN public.unit_size AS us
              ON lu.unit_size_id = us.id
      LEFT JOIN public.status AS st
              ON lu.status_id = st.id
      LEFT JOIN LATERAL (
              SELECT array_agg(DISTINCT sfu.data_source_id) FILTER (WHERE sfu.data_source_id IS NOT NULL) AS data_source_ids
              FROM public.stat_for_unit AS sfu
              WHERE sfu.legal_unit_id = lu.id
                AND daterange(t.valid_after, t.valid_to, '(]')
                && daterange(sfu.valid_after, sfu.valid_to, '(]')
        ) AS sfu ON TRUE
      LEFT JOIN LATERAL (
          SELECT array_agg(ds.id) AS ids
               , array_agg(ds.code) AS codes
          FROM public.data_source AS ds
         WHERE COALESCE(ds.id = lu.data_source_id       , FALSE)
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
            (lu.edit_comment, lu.edit_by_user_id, lu.edit_at),
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
      ), establishment_aggregation AS (
        SELECT tes.legal_unit_id
             , basis.valid_after
             , basis.valid_to
             , public.array_distinct_concat(tes.data_source_ids) AS data_source_ids
             , public.array_distinct_concat(tes.data_source_codes) AS data_source_codes
             , array_agg(DISTINCT tes.establishment_id) FILTER (WHERE tes.establishment_id IS NOT NULL) AS related_establishment_ids
             , array_agg(DISTINCT tes.establishment_id) FILTER (WHERE tes.establishment_id IS NOT NULL AND NOT tes.include_unit_in_reports) AS excluded_establishment_ids
             , array_agg(DISTINCT tes.establishment_id) FILTER (WHERE tes.establishment_id IS NOT NULL AND tes.include_unit_in_reports) AS included_establishment_ids
             , public.jsonb_stats_to_summary_agg(tes.stats) FILTER (WHERE tes.include_unit_in_reports) AS stats_summary
          FROM public.timeline_establishment AS tes
          INNER JOIN basis
           ON tes.legal_unit_id = basis.legal_unit_id
          AND daterange(basis.valid_after, basis.valid_to, '(]')
           && daterange(tes.valid_after, tes.valid_to, '(]')
        GROUP BY tes.legal_unit_id, basis.valid_after , basis.valid_to
        )
      SELECT basis.unit_type
           , basis.unit_id
           , basis.valid_after
           , basis.valid_from
           , basis.valid_to
           , basis.name
           , basis.birth_date
           , basis.death_date
           , basis.search
           , basis.primary_activity_category_id
           , basis.primary_activity_category_path
           , basis.primary_activity_category_code
           , basis.secondary_activity_category_id
           , basis.secondary_activity_category_path
           , basis.secondary_activity_category_code
           , basis.activity_category_paths
           , basis.sector_id
           , basis.sector_path
           , basis.sector_code
           , basis.sector_name
           , (
               SELECT array_agg(DISTINCT id)
               FROM (
                   SELECT unnest(basis.data_source_ids) AS id
                   UNION ALL
                   SELECT unnest(esa.data_source_ids) AS id
               ) AS ids
           ) AS data_source_ids
           , (
               SELECT array_agg(DISTINCT code)
               FROM (
                   SELECT unnest(basis.data_source_codes) AS code
                   UNION ALL
                   SELECT unnest(esa.data_source_codes) AS code
               ) AS codes
           ) AS data_source_codes
           , basis.legal_form_id
           , basis.legal_form_code
           , basis.legal_form_name
           --
           , basis.physical_address_part1
           , basis.physical_address_part2
           , basis.physical_address_part3
           , basis.physical_postcode
           , basis.physical_postplace
           , basis.physical_region_id
           , basis.physical_region_path
           , basis.physical_region_code
           , basis.physical_country_id
           , basis.physical_country_iso_2
           , basis.physical_latitude
           , basis.physical_longitude
           , basis.physical_altitude
           --
           , basis.postal_address_part1
           , basis.postal_address_part2
           , basis.postal_address_part3
           , basis.postal_postcode
           , basis.postal_postplace
           , basis.postal_region_id
           , basis.postal_region_path
           , basis.postal_region_code
           , basis.postal_country_id
           , basis.postal_country_iso_2
           , basis.postal_latitude
           , basis.postal_longitude
           , basis.postal_altitude
           --
           , basis.web_address
           , basis.email_address
           , basis.phone_number
           , basis.landline
           , basis.mobile_number
           , basis.fax_number
           --
           , basis.unit_size_id
           , basis.unit_size_code
           --
           , basis.status_id
           , basis.status_code
           , basis.include_unit_in_reports
           --
           , basis.last_edit_comment
           , basis.last_edit_by_user_id
           , basis.last_edit_at
           --
           , basis.invalid_codes
           , basis.has_legal_unit
           , COALESCE(esa.related_establishment_ids, ARRAY[]::INT[]) AS related_establishment_ids
           , COALESCE(esa.excluded_establishment_ids, ARRAY[]::INT[]) AS excluded_establishment_ids
           , COALESCE(esa.included_establishment_ids, ARRAY[]::INT[]) AS included_establishment_ids
           , basis.legal_unit_id
           , basis.enterprise_id
           --
           , basis.primary_for_enterprise
           -- Expose the stats for just this entry.
           , basis.stats AS stats
           -- Continue one more aggregation iteration adding the stats for this unit
           -- to the aggregated stats for establishments, by using the internal
           -- aggregation function for one more step.
           , public.jsonb_stats_to_summary(COALESCE(esa.stats_summary,'{}'::JSONB), basis.stats) AS stats_summary
      FROM basis
      LEFT OUTER JOIN establishment_aggregation AS esa
       ON basis.legal_unit_id = esa.legal_unit_id
       AND basis.valid_after = esa.valid_after
       AND basis.valid_to = esa.valid_to
      --
      ORDER BY unit_type, unit_id, valid_after
;

DROP TABLE IF EXISTS public.timeline_legal_unit;

-- Create the physical table to store the view results
CREATE TABLE IF NOT EXISTS public.timeline_legal_unit AS
SELECT * FROM public.timeline_legal_unit_def
WHERE FALSE;

-- Add constraints to the physical table
ALTER TABLE public.timeline_legal_unit
    ADD PRIMARY KEY (unit_type, unit_id, valid_after),
    ALTER COLUMN unit_type SET NOT NULL,
    ALTER COLUMN unit_id SET NOT NULL,
    ALTER COLUMN valid_after SET NOT NULL,
    ALTER COLUMN valid_from SET NOT NULL;

-- Create indices to optimize queries
CREATE INDEX IF NOT EXISTS idx_timeline_legal_unit_daterange ON public.timeline_legal_unit
    USING gist (daterange(valid_after, valid_to, '(]'));
CREATE INDEX IF NOT EXISTS idx_timeline_legal_unit_valid_period ON public.timeline_legal_unit
    (valid_after, valid_to);
CREATE INDEX IF NOT EXISTS idx_timeline_legal_unit_related_establishment_ids ON public.timeline_legal_unit
    USING gin (related_establishment_ids);
CREATE INDEX IF NOT EXISTS idx_timeline_legal_unit_primary_for_enterprise ON public.timeline_legal_unit
    (primary_for_enterprise) WHERE primary_for_enterprise = true;
CREATE INDEX IF NOT EXISTS idx_timeline_legal_unit_legal_unit_id ON public.timeline_legal_unit
    (legal_unit_id) WHERE legal_unit_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_timeline_legal_unit_enterprise_id ON public.timeline_legal_unit
    (enterprise_id);


-- Create a function to refresh the timeline_legal_unit table
CREATE OR REPLACE FUNCTION public.timeline_legal_unit_refresh(
    p_valid_after date DEFAULT NULL,
    p_valid_to date DEFAULT NULL
) RETURNS void LANGUAGE plpgsql AS $timeline_legal_unit_refresh$
DECLARE
    date_range daterange;
BEGIN
    -- Create the date range for filtering
    date_range := daterange(COALESCE(p_valid_after, '-infinity'::date), COALESCE(p_valid_to, 'infinity'::date), '(]');

    -- Create a temporary table with the new data
    CREATE TEMPORARY TABLE temp_timeline_legal_unit ON COMMIT DROP AS
    SELECT * FROM public.timeline_legal_unit_def
    WHERE daterange(valid_after, valid_to, '(]') && date_range;

    -- Delete records that exist in the main table but not in the temp table
    DELETE FROM public.timeline_legal_unit tlu
    WHERE daterange(tlu.valid_after, tlu.valid_to, '(]') && date_range
    AND NOT EXISTS (
        SELECT 1 FROM temp_timeline_legal_unit ttlu
        WHERE ttlu.unit_type = tlu.unit_type
        AND ttlu.unit_id = tlu.unit_id
        AND ttlu.valid_after = tlu.valid_after
        AND ttlu.valid_to = tlu.valid_to
    );

    -- Insert or update records from the temp table into the main table
    INSERT INTO public.timeline_legal_unit
    SELECT ttlu.* FROM temp_timeline_legal_unit ttlu
    ON CONFLICT (unit_type, unit_id, valid_after) DO UPDATE SET
        valid_to = EXCLUDED.valid_to,
        valid_from = EXCLUDED.valid_from,
        name = EXCLUDED.name,
        birth_date = EXCLUDED.birth_date,
        death_date = EXCLUDED.death_date,
        search = EXCLUDED.search,
        primary_activity_category_id = EXCLUDED.primary_activity_category_id,
        primary_activity_category_path = EXCLUDED.primary_activity_category_path,
        primary_activity_category_code = EXCLUDED.primary_activity_category_code,
        secondary_activity_category_id = EXCLUDED.secondary_activity_category_id,
        secondary_activity_category_path = EXCLUDED.secondary_activity_category_path,
        secondary_activity_category_code = EXCLUDED.secondary_activity_category_code,
        activity_category_paths = EXCLUDED.activity_category_paths,
        sector_id = EXCLUDED.sector_id,
        sector_path = EXCLUDED.sector_path,
        sector_code = EXCLUDED.sector_code,
        sector_name = EXCLUDED.sector_name,
        data_source_ids = EXCLUDED.data_source_ids,
        data_source_codes = EXCLUDED.data_source_codes,
        legal_form_id = EXCLUDED.legal_form_id,
        legal_form_code = EXCLUDED.legal_form_code,
        legal_form_name = EXCLUDED.legal_form_name,
        physical_address_part1 = EXCLUDED.physical_address_part1,
        physical_address_part2 = EXCLUDED.physical_address_part2,
        physical_address_part3 = EXCLUDED.physical_address_part3,
        physical_postcode = EXCLUDED.physical_postcode,
        physical_postplace = EXCLUDED.physical_postplace,
        physical_region_id = EXCLUDED.physical_region_id,
        physical_region_path = EXCLUDED.physical_region_path,
        physical_region_code = EXCLUDED.physical_region_code,
        physical_country_id = EXCLUDED.physical_country_id,
        physical_country_iso_2 = EXCLUDED.physical_country_iso_2,
        physical_latitude = EXCLUDED.physical_latitude,
        physical_longitude = EXCLUDED.physical_longitude,
        physical_altitude = EXCLUDED.physical_altitude,
        postal_address_part1 = EXCLUDED.postal_address_part1,
        postal_address_part2 = EXCLUDED.postal_address_part2,
        postal_address_part3 = EXCLUDED.postal_address_part3,
        postal_postcode = EXCLUDED.postal_postcode,
        postal_postplace = EXCLUDED.postal_postplace,
        postal_region_id = EXCLUDED.postal_region_id,
        postal_region_path = EXCLUDED.postal_region_path,
        postal_region_code = EXCLUDED.postal_region_code,
        postal_country_id = EXCLUDED.postal_country_id,
        postal_country_iso_2 = EXCLUDED.postal_country_iso_2,
        postal_latitude = EXCLUDED.postal_latitude,
        postal_longitude = EXCLUDED.postal_longitude,
        postal_altitude = EXCLUDED.postal_altitude,
        web_address = EXCLUDED.web_address,
        email_address = EXCLUDED.email_address,
        phone_number = EXCLUDED.phone_number,
        landline = EXCLUDED.landline,
        mobile_number = EXCLUDED.mobile_number,
        fax_number = EXCLUDED.fax_number,
        unit_size_id = EXCLUDED.unit_size_id,
        unit_size_code = EXCLUDED.unit_size_code,
        status_id = EXCLUDED.status_id,
        status_code = EXCLUDED.status_code,
        include_unit_in_reports = EXCLUDED.include_unit_in_reports,
        last_edit_comment = EXCLUDED.last_edit_comment,
        last_edit_by_user_id = EXCLUDED.last_edit_by_user_id,
        last_edit_at = EXCLUDED.last_edit_at,
        invalid_codes = EXCLUDED.invalid_codes,
        has_legal_unit = EXCLUDED.has_legal_unit,
        related_establishment_ids = EXCLUDED.related_establishment_ids,
        excluded_establishment_ids = EXCLUDED.excluded_establishment_ids,
        included_establishment_ids = EXCLUDED.included_establishment_ids,
        legal_unit_id = EXCLUDED.legal_unit_id,
        enterprise_id = EXCLUDED.enterprise_id,
        primary_for_enterprise = EXCLUDED.primary_for_enterprise,
        stats = EXCLUDED.stats,
        stats_summary = EXCLUDED.stats_summary;

    -- Drop the temporary table
    DROP TABLE temp_timeline_legal_unit;

    -- Ensure sql execution planning takes in to account table changes.
    ANALYZE public.timeline_legal_unit;
END;
$timeline_legal_unit_refresh$;

-- Initial population of the timeline_legal_unit table
SELECT public.timeline_legal_unit_refresh();

END;
