BEGIN;

CREATE OR REPLACE VIEW public.timeline_enterprise_def
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
    , establishment_ids
    , legal_unit_ids
    , enterprise_id
    --
    , primary_establishment_id
    , primary_legal_unit_id
    --
    , stats_summary
    )
    AS
      WITH timesegments_enterprise AS (
      SELECT *
           , en.id AS enterprise_id
      FROM public.timesegments AS t
      INNER JOIN public.enterprise AS en
          ON t.unit_type = 'enterprise' AND t.unit_id = en.id
      ), enterprise_with_primary_legal_unit AS (
      SELECT ten.unit_type
           , ten.unit_id
           , ten.valid_after
           , ten.valid_to
           , tlu.name AS name
           , tlu.birth_date AS birth_date
           , tlu.death_date AS death_date
           , tlu.search AS search
           , tlu.primary_activity_category_id
           , tlu.primary_activity_category_path
           , tlu.primary_activity_category_code
           , tlu.secondary_activity_category_id
           , tlu.secondary_activity_category_path
           , tlu.secondary_activity_category_code
           , tlu.activity_category_paths
           , tlu.sector_id
           , tlu.sector_path
           , tlu.sector_code
           , tlu.sector_name
           , tlu.data_source_ids
           , tlu.data_source_codes
           , tlu.legal_form_id
           , tlu.legal_form_code
           , tlu.legal_form_name
           , tlu.physical_address_part1
           , tlu.physical_address_part2
           , tlu.physical_address_part3
           , tlu.physical_postcode
           , tlu.physical_postplace
           , tlu.physical_region_id
           , tlu.physical_region_path
           , tlu.physical_region_code
           , tlu.physical_country_id
           , tlu.physical_country_iso_2
           , tlu.physical_latitude
           , tlu.physical_longitude
           , tlu.physical_altitude
           , tlu.postal_address_part1
           , tlu.postal_address_part2
           , tlu.postal_address_part3
           , tlu.postal_postcode
           , tlu.postal_postplace
           , tlu.postal_region_id
           , tlu.postal_region_path
           , tlu.postal_region_code
           , tlu.postal_country_id
           , tlu.postal_country_iso_2
           , tlu.postal_latitude
           , tlu.postal_longitude
           , tlu.postal_altitude
           , tlu.web_address
           , tlu.email_address
           , tlu.phone_number
           , tlu.landline
           , tlu.mobile_number
           , tlu.fax_number
           , tlu.unit_size_id
           , tlu.unit_size_code
           , tlu.status_id
           , tlu.status_code
           , tlu.include_unit_in_reports
           , last_edit.edit_comment AS last_edit_comment
           , last_edit.edit_by_user_id AS last_edit_by_user_id
           , last_edit.edit_at AS last_edit_at
           , tlu.invalid_codes
           , tlu.has_legal_unit
           , ten.enterprise_id
           , tlu.legal_unit_id AS primary_legal_unit_id
      FROM timesegments_enterprise AS ten
        INNER JOIN public.timeline_legal_unit AS tlu
            ON tlu.enterprise_id = ten.enterprise_id
            AND tlu.primary_for_enterprise = true
            AND daterange(ten.valid_after, ten.valid_to, '(]')
            && daterange(tlu.valid_after, tlu.valid_to, '(]')
        LEFT JOIN LATERAL (
          SELECT edit_comment, edit_by_user_id, edit_at
          FROM (
            VALUES
              (ten.edit_comment, ten.edit_by_user_id, ten.edit_at),
              (tlu.last_edit_comment, tlu.last_edit_by_user_id, tlu.last_edit_at)
          ) AS all_edits(edit_comment, edit_by_user_id, edit_at)
          WHERE edit_at IS NOT NULL
          ORDER BY edit_at DESC
          LIMIT 1
        ) AS last_edit ON TRUE
      ), enterprise_with_primary_establishment AS (
      SELECT ten.unit_type
           , ten.unit_id
           , ten.valid_after
           , ten.valid_to
           , tes.name AS name
           , tes.birth_date AS birth_date
           , tes.death_date AS death_date
           , tes.search AS search
           , tes.primary_activity_category_id
           , tes.primary_activity_category_path
           , tes.primary_activity_category_code
           , tes.secondary_activity_category_id
           , tes.secondary_activity_category_path
           , tes.secondary_activity_category_code
           , tes.activity_category_paths
           , tes.sector_id
           , tes.sector_path
           , tes.sector_code
           , tes.sector_name
           , tes.data_source_ids
           , tes.data_source_codes
           , tes.legal_form_id
           , tes.legal_form_code
           , tes.legal_form_name
           , tes.physical_address_part1
           , tes.physical_address_part2
           , tes.physical_address_part3
           , tes.physical_postcode
           , tes.physical_postplace
           , tes.physical_region_id
           , tes.physical_region_path
           , tes.physical_region_code
           , tes.physical_country_id
           , tes.physical_country_iso_2
           , tes.physical_latitude
           , tes.physical_longitude
           , tes.physical_altitude
           , tes.postal_address_part1
           , tes.postal_address_part2
           , tes.postal_address_part3
           , tes.postal_postcode
           , tes.postal_postplace
           , tes.postal_region_id
           , tes.postal_region_path
           , tes.postal_region_code
           , tes.postal_country_id
           , tes.postal_country_iso_2
           , tes.postal_latitude
           , tes.postal_longitude
           , tes.postal_altitude
           , tes.web_address
           , tes.email_address
           , tes.phone_number
           , tes.landline
           , tes.mobile_number
           , tes.fax_number
           , tes.unit_size_id
           , tes.unit_size_code
           , tes.status_id
           , tes.status_code
           , tes.include_unit_in_reports
           , last_edit.edit_comment AS last_edit_comment
           , last_edit.edit_by_user_id AS last_edit_by_user_id
           , last_edit.edit_at AS last_edit_at
           , tes.invalid_codes
           , tes.has_legal_unit
           , ten.enterprise_id
           , tes.establishment_id AS primary_establishment_id
      FROM timesegments_enterprise AS ten
        INNER JOIN public.timeline_establishment AS tes
            ON tes.enterprise_id = ten.enterprise_id
            AND tes.primary_for_enterprise = true
            AND daterange(ten.valid_after, ten.valid_to, '(]')
            && daterange(tes.valid_after, tes.valid_to, '(]')
        LEFT JOIN LATERAL (
          SELECT edit_comment, edit_by_user_id, edit_at
          FROM (
            VALUES
              (ten.edit_comment, ten.edit_by_user_id, ten.edit_at),
              (tes.last_edit_comment, tes.last_edit_by_user_id, tes.last_edit_at)
          ) AS all_edits(edit_comment, edit_by_user_id, edit_at)
          WHERE edit_at IS NOT NULL
          ORDER BY edit_at DESC
          LIMIT 1
        ) AS last_edit ON TRUE
      ), enterprise_with_primary AS (
      SELECT ten.unit_type
           , ten.unit_id
           , ten.valid_after
           , ten.valid_to
           , COALESCE(enplu.name,enpes.name) AS name
           , COALESCE(enplu.birth_date,enpes.birth_date) AS birth_date
           , COALESCE(enplu.death_date,enpes.death_date) AS death_date
           --
           , COALESCE(enplu.primary_activity_category_id,enpes.primary_activity_category_id) AS primary_activity_category_id
           , COALESCE(enplu.primary_activity_category_path,enpes.primary_activity_category_path) AS primary_activity_category_path
           , COALESCE(enplu.primary_activity_category_code,enpes.primary_activity_category_code) AS primary_activity_category_code
           --
           , COALESCE(enplu.secondary_activity_category_id,enpes.secondary_activity_category_id) AS secondary_activity_category_id
           , COALESCE(enplu.secondary_activity_category_path,enpes.secondary_activity_category_path) AS secondary_activity_category_path
           , COALESCE(enplu.secondary_activity_category_code,enpes.secondary_activity_category_code) AS secondary_activity_category_code
           --
           , COALESCE(enplu.sector_id,enpes.sector_id) AS sector_id
           , COALESCE(enplu.sector_path,enpes.sector_path) AS sector_path
           , COALESCE(enplu.sector_code,enpes.sector_code) AS sector_code
           , COALESCE(enplu.sector_name,enpes.sector_name) AS sector_name
           --
           , (
               SELECT array_agg(DISTINCT id)
               FROM (
                   SELECT unnest(enplu.data_source_ids) AS id
                   UNION
                   SELECT unnest(enpes.data_source_ids) AS id
               ) AS ids
           ) AS data_source_ids
           , (
               SELECT array_agg(DISTINCT code)
               FROM (
                   SELECT unnest(enplu.data_source_codes) AS code
                   UNION
                   SELECT unnest(enpes.data_source_codes) AS code
               ) AS codes
           ) AS data_source_codes
           --
           , enplu.legal_form_id   AS legal_form_id
           , enplu.legal_form_code AS legal_form_code
           , enplu.legal_form_name AS legal_form_name
           --
           , COALESCE(enplu.physical_address_part1, enpes.physical_address_part1) AS physical_address_part1
           , COALESCE(enplu.physical_address_part2, enpes.physical_address_part2) AS physical_address_part2
           , COALESCE(enplu.physical_address_part3, enpes.physical_address_part3) AS physical_address_part3
           , COALESCE(enplu.physical_postcode, enpes.physical_postcode) AS physical_postcode
           , COALESCE(enplu.physical_postplace, enpes.physical_postplace) AS physical_postplace
           , COALESCE(enplu.physical_region_id, enpes.physical_region_id) AS physical_region_id
           , COALESCE(enplu.physical_region_path, enpes.physical_region_path) AS physical_region_path
           , COALESCE(enplu.physical_region_code, enpes.physical_region_code) AS physical_region_code
           , COALESCE(enplu.physical_country_id, enpes.physical_country_id) AS physical_country_id
           , COALESCE(enplu.physical_country_iso_2, enpes.physical_country_iso_2) AS physical_country_iso_2
           , COALESCE(enplu.physical_latitude, enpes.physical_latitude) AS physical_latitude
           , COALESCE(enplu.physical_longitude, enpes.physical_longitude) AS physical_longitude
           , COALESCE(enplu.physical_altitude, enpes.physical_altitude) AS physical_altitude
           --
           , COALESCE(enplu.postal_address_part1, enpes.postal_address_part1) AS postal_address_part1
           , COALESCE(enplu.postal_address_part2, enpes.postal_address_part2) AS postal_address_part2
           , COALESCE(enplu.postal_address_part3, enpes.postal_address_part3) AS postal_address_part3
           , COALESCE(enplu.postal_postcode, enpes.postal_postcode) AS postal_postcode
           , COALESCE(enplu.postal_postplace, enpes.postal_postplace) AS postal_postplace
           , COALESCE(enplu.postal_region_id, enpes.postal_region_id) AS postal_region_id
           , COALESCE(enplu.postal_region_path, enpes.postal_region_path) AS postal_region_path
           , COALESCE(enplu.postal_region_code, enpes.postal_region_code) AS postal_region_code
           , COALESCE(enplu.postal_country_id, enpes.postal_country_id) AS postal_country_id
           , COALESCE(enplu.postal_country_iso_2, enpes.postal_country_iso_2) AS postal_country_iso_2
           , COALESCE(enplu.postal_latitude, enpes.postal_latitude) AS postal_latitude
           , COALESCE(enplu.postal_longitude, enpes.postal_longitude) AS postal_longitude
           , COALESCE(enplu.postal_altitude, enpes.postal_altitude) AS postal_altitude
           --
           , COALESCE(enplu.web_address, enpes.web_address) AS web_address
           , COALESCE(enplu.email_address, enpes.email_address) AS email_address
           , COALESCE(enplu.phone_number, enpes.phone_number) AS phone_number
           , COALESCE(enplu.landline, enpes.landline) AS landline
           , COALESCE(enplu.mobile_number, enpes.mobile_number) AS mobile_number
           , COALESCE(enplu.fax_number, enpes.fax_number) AS fax_number
           --
           , COALESCE(enplu.unit_size_id, enpes.unit_size_id) AS unit_size_id
           , COALESCE(enplu.unit_size_code, enpes.unit_size_code) AS unit_size_code
           --
           , COALESCE(enplu.status_id, enpes.status_id) AS status_id
           , COALESCE(enplu.status_code, enpes.status_code) AS status_code
           , COALESCE(enplu.include_unit_in_reports, enpes.include_unit_in_reports) AS include_unit_in_reports
           --
           , last_edit.edit_comment AS last_edit_comment
           , last_edit.edit_by_user_id AS last_edit_by_user_id
           , last_edit.edit_at AS last_edit_at
           --
           , COALESCE(
              enplu.invalid_codes || enpes.invalid_codes,
              enplu.invalid_codes,
              enpes.invalid_codes
           ) AS invalid_codes
           --
           , GREATEST(enplu.has_legal_unit, enpes.has_legal_unit) AS has_legal_unit
           --
           , ten.enterprise_id AS enterprise_id
           , enplu.primary_legal_unit_id AS primary_legal_unit_id
           , enpes.primary_establishment_id AS primary_establishment_id
      FROM timesegments_enterprise AS ten
      LEFT JOIN enterprise_with_primary_legal_unit AS enplu
             ON enplu.enterprise_id = ten.enterprise_id
             AND ten.valid_after = enplu.valid_after
             AND ten.valid_to = enplu.valid_to
      LEFT JOIN enterprise_with_primary_establishment AS enpes
             ON enpes.enterprise_id = ten.enterprise_id
             AND ten.valid_after = enpes.valid_after
             AND ten.valid_to = enpes.valid_to
      LEFT JOIN LATERAL (
        SELECT edit_comment, edit_by_user_id, edit_at
        FROM (
          VALUES
            (ten.edit_comment, ten.edit_by_user_id, ten.edit_at),
            (enplu.last_edit_comment, enplu.last_edit_by_user_id, enplu.last_edit_at),
            (enpes.last_edit_comment, enpes.last_edit_by_user_id, enpes.last_edit_at)
        ) AS all_edits(edit_comment, edit_by_user_id, edit_at)
        WHERE edit_at IS NOT NULL
        ORDER BY edit_at DESC
        LIMIT 1
      ) AS last_edit ON TRUE
      ), aggregation AS (
        SELECT ten.enterprise_id
             , ten.valid_after
             , ten.valid_to
             --
             , public.array_distinct_concat(
                COALESCE(
                  array_cat(tlu.data_source_ids, tes.data_source_ids),
                  tlu.data_source_ids,
                  tes.data_source_ids
                )
             )
             AS data_source_ids
             , public.array_distinct_concat(
                COALESCE(
                  array_cat(tlu.data_source_codes, tes.data_source_codes),
                  tlu.data_source_codes,
                  tes.data_source_codes
                )
             )
             AS data_source_codes
             --
             , public.array_distinct_concat(
                COALESCE(
                  array_cat(tlu.establishment_ids, tes.establishment_ids),
                  tlu.establishment_ids,
                  tes.establishment_ids
                )
             ) AS establishment_ids
             --
             , public.array_distinct_concat(tlu.legal_unit_ids) AS legal_unit_ids
             --
             , COALESCE(
               public.jsonb_stats_summary_merge_agg(
                 COALESCE(
                   public.jsonb_stats_summary_merge(tlu.stats_summary, tes.stats_summary),
                   tlu.stats_summary,
                   tes.stats_summary
                   )
                 ),
               '{}'::jsonb
               ) AS stats_summary
          FROM timesegments_enterprise AS ten
          LEFT JOIN LATERAL (
              SELECT enterprise_id
                   , ten.valid_after
                   , ten.valid_to
                   , public.array_distinct_concat(data_source_ids) AS data_source_ids
                   , public.array_distinct_concat(data_source_codes) AS data_source_codes
                   , array_agg(DISTINCT legal_unit_id) AS legal_unit_ids
                   , public.array_distinct_concat(establishment_ids) AS establishment_ids
                   , public.jsonb_stats_summary_merge_agg(stats_summary) AS stats_summary
              FROM public.timeline_legal_unit
              WHERE enterprise_id = ten.enterprise_id
              AND include_unit_in_reports
              AND daterange(ten.valid_after, ten.valid_to, '(]') && daterange(valid_after, valid_to, '(]')
              GROUP BY enterprise_id, ten.valid_after, ten.valid_to
          ) AS tlu ON true
          LEFT JOIN LATERAL (
              SELECT enterprise_id
                   , ten.valid_after
                   , ten.valid_to
                   , public.array_distinct_concat(data_source_ids) AS data_source_ids
                   , public.array_distinct_concat(data_source_codes) AS data_source_codes
                   , array_agg(DISTINCT establishment_id) AS establishment_ids
                   , public.jsonb_stats_to_summary_agg(stats) AS stats_summary
              FROM public.timeline_establishment
              WHERE enterprise_id = ten.enterprise_id
              AND include_unit_in_reports
              AND daterange(ten.valid_after, ten.valid_to, '(]') && daterange(valid_after, valid_to, '(]')
              GROUP BY enterprise_id, ten.valid_after, ten.valid_to
          ) AS tes ON true
          GROUP BY ten.enterprise_id, ten.valid_after, ten.valid_to
      ), enterprise_with_primary_and_aggregation AS (
          SELECT basis.unit_type
               , basis.unit_id
               , basis.valid_after
               , basis.valid_to
               , basis.name
               , basis.birth_date
               , basis.death_date
               , basis.primary_activity_category_id
               , basis.primary_activity_category_path
               , basis.primary_activity_category_code
               , basis.secondary_activity_category_id
               , basis.secondary_activity_category_path
               , basis.secondary_activity_category_code
               , basis.sector_id
               , basis.sector_path
               , basis.sector_code
               , basis.sector_name
               , (
                   SELECT array_agg(DISTINCT id)
                   FROM (
                       SELECT unnest(basis.data_source_ids) AS id
                       UNION
                       SELECT unnest(aggregation.data_source_ids) AS id
                   ) AS ids
               ) AS data_source_ids
               , (
                   SELECT array_agg(DISTINCT code)
                   FROM (
                       SELECT unnest(basis.data_source_codes) AS code
                       UNION ALL
                       SELECT unnest(aggregation.data_source_codes) AS code
                   ) AS codes
               ) AS data_source_codes
               , basis.legal_form_id
               , basis.legal_form_code
               , basis.legal_form_name
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
               , COALESCE(aggregation.establishment_ids, ARRAY[]::INT[]) AS establishment_ids
               , COALESCE(aggregation.legal_unit_ids, ARRAY[]::INT[]) AS legal_unit_ids
               , basis.enterprise_id
               , basis.primary_establishment_id
               , basis.primary_legal_unit_id
               , aggregation.stats_summary
          FROM enterprise_with_primary AS basis
          LEFT OUTER JOIN aggregation
                     ON basis.enterprise_id = aggregation.enterprise_id
                     AND basis.valid_after = aggregation.valid_after
                     AND basis.valid_to = aggregation.valid_to
        ), enterprise_with_primary_and_aggregation_and_derived AS (
        SELECT unit_type
             , unit_id
             , valid_after
             , (valid_after + '1 day'::INTERVAL)::DATE AS valid_from
             , valid_to
             , name
             , birth_date
             , death_date
             -- Se supported languages with `SELECT * FROM pg_ts_config`
             , to_tsvector('simple', name) AS search
             --
             , primary_activity_category_id
             , primary_activity_category_path
             , primary_activity_category_code
             --
             , secondary_activity_category_id
             , secondary_activity_category_path
             , secondary_activity_category_code
             --
             , NULLIF(ARRAY_REMOVE(ARRAY[
                primary_activity_category_path,
                secondary_activity_category_path
              ], NULL), '{}') AS activity_category_paths
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
             --
             , has_legal_unit
             --
             , establishment_ids
             , legal_unit_ids
             --
             , enterprise_id
             , primary_establishment_id
             , primary_legal_unit_id
             , stats_summary
          FROM enterprise_with_primary_and_aggregation
        )
        SELECT * FROM enterprise_with_primary_and_aggregation_and_derived
         ORDER BY unit_type, unit_id, valid_after
;


DROP TABLE IF EXISTS public.timeline_enterprise;

-- Create the physical table to store the view results
CREATE TABLE IF NOT EXISTS public.timeline_enterprise AS
SELECT * FROM public.timeline_enterprise_def
WHERE FALSE;

-- Add constraints to the physical table
ALTER TABLE public.timeline_enterprise
    ADD PRIMARY KEY (unit_type, unit_id, valid_after),
    ALTER COLUMN unit_type SET NOT NULL,
    ALTER COLUMN unit_id SET NOT NULL,
    ALTER COLUMN valid_after SET NOT NULL,
    ALTER COLUMN valid_from SET NOT NULL;

-- Create indices to optimize queries
CREATE INDEX IF NOT EXISTS idx_timeline_enterprise_daterange ON public.timeline_enterprise
    USING gist (daterange(valid_after, valid_to, '(]'));
CREATE INDEX IF NOT EXISTS idx_timeline_enterprise_valid_period ON public.timeline_enterprise
    (valid_after, valid_to);
CREATE INDEX IF NOT EXISTS idx_timeline_enterprise_establishment_ids ON public.timeline_enterprise
    USING gin (establishment_ids);
CREATE INDEX IF NOT EXISTS idx_timeline_enterprise_legal_unit_ids ON public.timeline_enterprise
    USING gin (legal_unit_ids);

-- Create a function to refresh the timeline_enterprise table
CREATE OR REPLACE FUNCTION public.timeline_enterprise_refresh(
    p_valid_after date DEFAULT NULL,
    p_valid_to date DEFAULT NULL
) RETURNS void LANGUAGE plpgsql AS $timeline_enterprise_refresh$
DECLARE
    date_range daterange;
BEGIN
    -- Create the date range for filtering
    date_range := daterange(COALESCE(p_valid_after, '-infinity'::date), COALESCE(p_valid_to, 'infinity'::date), '(]');

    -- Create a temporary table with the new data
    CREATE TEMPORARY TABLE temp_timeline_enterprise ON COMMIT DROP AS
    SELECT * FROM public.timeline_enterprise_def
    WHERE daterange(valid_after, valid_to, '(]') && date_range;

    -- Delete records that exist in the main table but not in the temp table
    DELETE FROM public.timeline_enterprise te
    WHERE daterange(te.valid_after, te.valid_to, '(]') && date_range
    AND NOT EXISTS (
        SELECT 1 FROM temp_timeline_enterprise tte
        WHERE tte.unit_type = te.unit_type
        AND tte.unit_id = te.unit_id
        AND tte.valid_after = te.valid_after
        AND tte.valid_to = te.valid_to
    );

    -- Insert records that exist in the temp table but not in the main table
    INSERT INTO public.timeline_enterprise
    SELECT tte.* FROM temp_timeline_enterprise tte
    WHERE NOT EXISTS (
        SELECT 1 FROM public.timeline_enterprise te
        WHERE te.unit_type = tte.unit_type
        AND te.unit_id = tte.unit_id
        AND te.valid_after = tte.valid_after
        AND te.valid_to = tte.valid_to
    );

    -- Drop the temporary table
    DROP TABLE temp_timeline_enterprise;
END;
$timeline_enterprise_refresh$;

-- Initial population of the timeline_enterprise table
SELECT public.timeline_enterprise_refresh();

END;
