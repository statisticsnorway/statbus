BEGIN;

CREATE VIEW public.timeline_establishment_def
    ( unit_type
    , unit_id
    , valid_after
    , valid_from
    , valid_to
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
    )
    AS
      SELECT t.unit_type
           , t.unit_id
           , t.valid_after
           , (t.valid_after + '1 day'::INTERVAL)::DATE AS valid_from
           , t.valid_to
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
           , COALESCE(public.get_jsonb_stats(es.id, NULL, t.valid_after, t.valid_to), '{}'::JSONB) AS stats
      --
      FROM public.timesegments AS t
      INNER JOIN public.establishment AS es
          ON t.unit_type = 'establishment' AND t.unit_id = es.id
         AND after_to_overlaps(t.valid_after, t.valid_to, es.valid_after, es.valid_to)
      --
      LEFT OUTER JOIN public.activity AS pa
              ON pa.establishment_id = es.id
             AND pa.type = 'primary'
             AND after_to_overlaps(t.valid_after, t.valid_to, pa.valid_after, pa.valid_to)
      LEFT JOIN public.activity_category AS pac
              ON pa.category_id = pac.id
      --
      LEFT OUTER JOIN public.activity AS sa
              ON sa.establishment_id = es.id
             AND sa.type = 'secondary'
             AND after_to_overlaps(t.valid_after, t.valid_to, sa.valid_after, sa.valid_to)
      LEFT JOIN public.activity_category AS sac
              ON sa.category_id = sac.id
      --
      LEFT OUTER JOIN public.sector AS s
              ON es.sector_id = s.id
      --
      LEFT OUTER JOIN public.location AS phl
              ON phl.establishment_id = es.id
             AND phl.type = 'physical'
             AND after_to_overlaps(t.valid_after, t.valid_to, phl.valid_after, phl.valid_to)
      LEFT JOIN public.region AS phr
              ON phl.region_id = phr.id
      LEFT JOIN public.country AS phc
              ON phl.country_id = phc.id
      --
      LEFT OUTER JOIN public.location AS pol
              ON pol.establishment_id = es.id
             AND pol.type = 'postal'
             AND after_to_overlaps(t.valid_after, t.valid_to, pol.valid_after, pol.valid_to)
      LEFT JOIN public.region AS por
              ON pol.region_id = por.id
      LEFT JOIN public.country AS poc
              ON pol.country_id = poc.id
      LEFT OUTER JOIN public.contact AS c
              ON c.establishment_id = es.id
             AND after_to_overlaps(t.valid_after, t.valid_to, c.valid_after, c.valid_to)
      LEFT JOIN public.unit_size AS us
              ON es.unit_size_id = us.id
      LEFT JOIN public.status AS st
              ON es.status_id = st.id
      LEFT JOIN LATERAL (
            SELECT array_agg(DISTINCT sfu.data_source_id) FILTER (WHERE sfu.data_source_id IS NOT NULL) AS data_source_ids
            FROM public.stat_for_unit AS sfu
            WHERE sfu.establishment_id = es.id
              AND after_to_overlaps(t.valid_after, t.valid_to, sfu.valid_after, sfu.valid_to)
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
      ORDER BY t.unit_type, t.unit_id, t.valid_after
;

DROP TABLE IF EXISTS public.timeline_establishment;

-- Create the physical table to store the view results
CREATE TABLE public.timeline_establishment AS
SELECT * FROM public.timeline_establishment_def
WHERE FALSE;

-- Add constraints to the physical table
ALTER TABLE public.timeline_establishment
    ADD PRIMARY KEY (unit_type, unit_id, valid_after),
    ALTER COLUMN unit_type SET NOT NULL,
    ALTER COLUMN unit_id SET NOT NULL,
    ALTER COLUMN valid_after SET NOT NULL,
    ALTER COLUMN valid_from SET NOT NULL;

-- Create indices to optimize queries
CREATE INDEX IF NOT EXISTS idx_timeline_establishment_daterange ON public.timeline_establishment
    USING gist (daterange(valid_after, valid_to, '(]'));
CREATE INDEX IF NOT EXISTS idx_timeline_establishment_valid_period ON public.timeline_establishment
    (valid_after, valid_to);
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
CREATE OR REPLACE FUNCTION public.timeline_establishment_refresh(
    p_valid_after date DEFAULT NULL,
    p_valid_to date DEFAULT NULL
) RETURNS void LANGUAGE plpgsql AS $timeline_establishment_refresh$
DECLARE
    v_valid_after date;
    v_valid_to date;
BEGIN
    -- Set the time range for filtering
    v_valid_after := COALESCE(p_valid_after, '-infinity'::date);
    v_valid_to := COALESCE(p_valid_to, 'infinity'::date);

    -- Create a temporary table with the new data
    CREATE TEMPORARY TABLE temp_timeline_establishment ON COMMIT DROP AS
    SELECT * FROM public.timeline_establishment_def
    WHERE after_to_overlaps(valid_after, valid_to, v_valid_after, v_valid_to);

    -- Delete records that exist in the main table but not in the temp table
    DELETE FROM public.timeline_establishment te
    WHERE after_to_overlaps(te.valid_after, te.valid_to, v_valid_after, v_valid_to)
    AND NOT EXISTS (
        SELECT 1 FROM temp_timeline_establishment tte
        WHERE tte.unit_type = te.unit_type
        AND tte.unit_id = te.unit_id
        AND tte.valid_after = te.valid_after
        AND tte.valid_to = te.valid_to
    );

    -- Insert or update records from the temp table into the main table
    INSERT INTO public.timeline_establishment
    SELECT tte.* FROM temp_timeline_establishment tte
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
        establishment_id = EXCLUDED.establishment_id,
        legal_unit_id = EXCLUDED.legal_unit_id,
        enterprise_id = EXCLUDED.enterprise_id,
        primary_for_enterprise = EXCLUDED.primary_for_enterprise,
        primary_for_legal_unit = EXCLUDED.primary_for_legal_unit,
        stats = EXCLUDED.stats;

    -- Drop the temporary table
    DROP TABLE temp_timeline_establishment;

    -- Ensure sql execution planning takes in to account table changes.
    ANALYZE public.timeline_establishment;
END;
$timeline_establishment_refresh$;

-- Initial population of the timeline_establishment table
SELECT public.timeline_establishment_refresh();

END;
