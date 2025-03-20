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
           , plu.name AS name
           , plu.birth_date AS birth_date
           , plu.death_date AS death_date
           -- Se supported languages with `SELECT * FROM pg_ts_config`
           , to_tsvector('simple', plu.name) AS search
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
           , c.web_address
           , c.email_address
           , c.phone_number
           , c.landline
           , c.mobile_number
           , c.fax_number
           --
           , plu.unit_size_id AS unit_size_id
           , us.code AS unit_size_code
           --
           , st.id AS status_id
           , st.code AS status_code
           , st.include_unit_in_reports AS include_unit_in_reports
           --
           , last_edit.edit_comment AS last_edit_comment
           , last_edit.edit_by_user_id AS last_edit_by_user_id
           , last_edit.edit_at AS last_edit_at
           --
           , plu.invalid_codes AS invalid_codes
           --
           , TRUE AS has_legal_unit
           --
           , ten.id AS enterprise_id
           , plu.id AS primary_legal_unit_id
      FROM timesegments_enterprise AS ten
      INNER JOIN public.legal_unit AS plu
          ON plu.enterprise_id = ten.enterprise_id
          AND plu.primary_for_enterprise
          AND daterange(ten.valid_after, ten.valid_to, '(]')
           && daterange(plu.valid_after, plu.valid_to, '(]')
      --
      LEFT OUTER JOIN public.activity AS pa
              ON pa.legal_unit_id = plu.id
             AND pa.type = 'primary'
             AND daterange(ten.valid_after, ten.valid_to, '(]')
              && daterange(pa.valid_after, pa.valid_to, '(]')
      LEFT JOIN public.activity_category AS pac
              ON pa.category_id = pac.id
      --
      LEFT OUTER JOIN public.activity AS sa
              ON sa.legal_unit_id = plu.id
             AND sa.type = 'secondary'
             AND daterange(ten.valid_after, ten.valid_to, '(]')
              && daterange(sa.valid_after, sa.valid_to, '(]')
      LEFT JOIN public.activity_category AS sac
              ON sa.category_id = sac.id
      --
      LEFT OUTER JOIN public.sector AS s
              ON plu.sector_id = s.id
      --
      LEFT OUTER JOIN public.legal_form AS lf
              ON plu.legal_form_id = lf.id
      --
      LEFT OUTER JOIN public.location AS phl
              ON phl.legal_unit_id = plu.id
             AND phl.type = 'physical'
             AND daterange(ten.valid_after, ten.valid_to, '(]')
              && daterange(phl.valid_after, phl.valid_to, '(]')
      LEFT JOIN public.region AS phr
              ON phl.region_id = phr.id
      LEFT JOIN public.country AS phc
              ON phl.country_id = phc.id
      --
      LEFT OUTER JOIN public.location AS pol
              ON pol.legal_unit_id = plu.id
             AND pol.type = 'postal'
             AND daterange(ten.valid_after, ten.valid_to, '(]')
              && daterange(pol.valid_after, pol.valid_to, '(]')
      LEFT JOIN public.region AS por
              ON pol.region_id = por.id
      LEFT JOIN public.country AS poc
              ON pol.country_id = poc.id
      --
      LEFT JOIN public.contact AS c
              ON c.legal_unit_id = plu.id
      --
      LEFT JOIN public.unit_size AS us
              ON us.id = plu.unit_size_id
      LEFT JOIN public.status AS st
              ON st.id = plu.status_id
      --
      LEFT JOIN LATERAL (
              SELECT array_agg(sfu.data_source_id) AS data_source_ids
              FROM public.stat_for_unit AS sfu
              WHERE sfu.legal_unit_id = plu.id
                AND daterange(ten.valid_after, ten.valid_to, '(]')
                && daterange(sfu.valid_after, sfu.valid_to, '(]')
        ) AS sfu ON TRUE
      --
      LEFT JOIN LATERAL (
          SELECT array_agg(ds.id) AS ids
               , array_agg(ds.code) AS codes
          FROM public.data_source AS ds
          WHERE COALESCE(ds.id = plu.data_source_id      , FALSE)
             OR COALESCE(ds.id = pa.data_source_id       , FALSE)
             OR COALESCE(ds.id = sa.data_source_id       , FALSE)
             OR COALESCE(ds.id = phl.data_source_id      , FALSE)
             OR COALESCE(ds.id = pol.data_source_id      , FALSE)
             OR COALESCE(ds.id = ANY(sfu.data_source_ids), FALSE)
        ) AS ds ON TRUE
      LEFT JOIN LATERAL (
        SELECT edit_comment, edit_by_user_id, edit_at
        FROM (
          SELECT plu.edit_comment, plu.edit_by_user_id, plu.edit_at
          UNION ALL
          SELECT pa.edit_comment, pa.edit_by_user_id, pa.edit_at
          WHERE pa.edit_at IS NOT NULL
          UNION ALL
          SELECT sa.edit_comment, sa.edit_by_user_id, sa.edit_at
          WHERE sa.edit_at IS NOT NULL
          UNION ALL
          SELECT phl.edit_comment, phl.edit_by_user_id, phl.edit_at
          WHERE phl.edit_at IS NOT NULL
          UNION ALL
          SELECT pol.edit_comment, pol.edit_by_user_id, pol.edit_at
          WHERE pol.edit_at IS NOT NULL
          UNION ALL
          SELECT c.edit_comment, c.edit_by_user_id, c.edit_at
          WHERE c.edit_at IS NOT NULL
        ) AS all_edits
        ORDER BY edit_at DESC
        LIMIT 1
      ) AS last_edit ON TRUE
      ), enterprise_with_primary_establishment AS (
      SELECT ten.unit_type
           , ten.unit_id
           , ten.valid_after
           , ten.valid_to
           , pes.name AS name
           , pes.birth_date AS birth_date
           , pes.death_date AS death_date
           -- Se supported languages with `SELECT * FROM pg_ts_config`
           , to_tsvector('simple', pes.name) AS search
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
           , COALESCE(ds.ids,ARRAY[]::INTEGER[]) AS data_source_ids
           , COALESCE(ds.codes, ARRAY[]::TEXT[]) AS data_source_codes
           --
           -- An establishment has no legal_form, that is for legal_unit only.
           , NULL::INTEGER AS legal_form_id
           , NULL::VARCHAR AS legal_form_code
           , NULL::VARCHAR AS legal_form_name
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
           , c.web_address
           , c.email_address
           , c.phone_number
           , c.landline
           , c.mobile_number
           , c.fax_number
           --
           , pes.unit_size_id AS unit_size_id
           , us.code AS unit_size_code
           --
           , st.id AS status_id
           , st.code AS status_code
           , st.include_unit_in_reports AS include_unit_in_reports
           --
           , last_edit.edit_comment AS last_edit_comment
           , last_edit.edit_by_user_id AS last_edit_by_user_id
           , last_edit.edit_at AS last_edit_at
           --
           , pes.invalid_codes AS invalid_codes
           --
           , FALSE AS has_legal_unit
           --
           , ten.id AS enterprise_id
           , pes.id AS primary_establishment_id
      FROM timesegments_enterprise AS ten
      INNER JOIN public.establishment AS pes
          ON pes.enterprise_id = ten.id
          AND pes.primary_for_enterprise
          AND daterange(ten.valid_after, ten.valid_to, '(]')
           && daterange(pes.valid_after, pes.valid_to, '(]')
      --
      LEFT OUTER JOIN public.activity AS pa
              ON pa.establishment_id = pes.id
             AND pa.type = 'primary'
             AND daterange(ten.valid_after, ten.valid_to, '(]')
              && daterange(pa.valid_after, pa.valid_to, '(]')
      LEFT JOIN public.activity_category AS pac
              ON pa.category_id = pac.id
      --
      LEFT OUTER JOIN public.activity AS sa
              ON sa.establishment_id = pes.id
             AND sa.type = 'secondary'
             AND daterange(ten.valid_after, ten.valid_to, '(]')
              && daterange(sa.valid_after, sa.valid_to, '(]')
      LEFT JOIN public.activity_category AS sac
              ON sa.category_id = sac.id
      --
      LEFT OUTER JOIN public.sector AS s
              ON pes.sector_id = s.id
      --
      LEFT OUTER JOIN public.location AS phl
              ON phl.establishment_id = pes.id
             AND phl.type = 'physical'
             AND daterange(ten.valid_after, ten.valid_to, '(]')
              && daterange(phl.valid_after, phl.valid_to, '(]')
      LEFT JOIN public.region AS phr
              ON phl.region_id = phr.id
      LEFT JOIN public.country AS phc
              ON phl.country_id = phc.id
      --
      LEFT OUTER JOIN public.location AS pol
              ON pol.establishment_id = pes.id
             AND pol.type = 'postal'
             AND daterange(ten.valid_after, ten.valid_to, '(]')
              && daterange(pol.valid_after, pol.valid_to, '(]')
      LEFT JOIN public.region AS por
              ON pol.region_id = por.id
      LEFT JOIN public.country AS poc
              ON pol.country_id = poc.id
      --
      LEFT JOIN public.contact AS c
              ON c.establishment_id = pes.id
      --
      LEFT JOIN public.unit_size AS us
              ON us.id = pes.unit_size_id
      LEFT JOIN public.status AS st
              ON st.id = pes.status_id
      --
      LEFT JOIN LATERAL (
            SELECT array_agg(sfu.data_source_id) AS data_source_ids
            FROM public.stat_for_unit AS sfu
            WHERE sfu.legal_unit_id = pes.id
              AND daterange(ten.valid_after, ten.valid_to, '(]')
              && daterange(sfu.valid_after, sfu.valid_to, '(]')
        ) AS sfu ON TRUE
      --
      LEFT JOIN LATERAL (
          SELECT array_agg(ds.id) AS ids
               , array_agg(ds.code) AS codes
          FROM public.data_source AS ds
         WHERE COALESCE(ds.id = pes.data_source_id      , FALSE)
            OR COALESCE(ds.id = pa.data_source_id       , FALSE)
            OR COALESCE(ds.id = sa.data_source_id       , FALSE)
            OR COALESCE(ds.id = phl.data_source_id      , FALSE)
            OR COALESCE(ds.id = pol.data_source_id      , FALSE)
            OR COALESCE(ds.id = ANY(sfu.data_source_ids), FALSE)
        ) AS ds ON TRUE
      LEFT JOIN LATERAL (
        SELECT edit_comment, edit_by_user_id, edit_at
        FROM (
          SELECT pes.edit_comment, pes.edit_by_user_id, pes.edit_at
          UNION ALL
          SELECT pa.edit_comment, pa.edit_by_user_id, pa.edit_at
          WHERE pa.edit_at IS NOT NULL
          UNION ALL
          SELECT sa.edit_comment, sa.edit_by_user_id, sa.edit_at
          WHERE sa.edit_at IS NOT NULL
          UNION ALL
          SELECT phl.edit_comment, phl.edit_by_user_id, phl.edit_at
          WHERE phl.edit_at IS NOT NULL
          UNION ALL
          SELECT pol.edit_comment, pol.edit_by_user_id, pol.edit_at
          WHERE pol.edit_at IS NOT NULL
          UNION ALL
          SELECT c.edit_comment, c.edit_by_user_id, c.edit_at
          WHERE c.edit_at IS NOT NULL
        ) AS all_edits
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
           , CASE
               WHEN enplu.last_edit_at IS NULL AND enpes.last_edit_at IS NULL THEN NULL
               WHEN enplu.last_edit_at IS NULL THEN enpes.last_edit_comment
               WHEN enpes.last_edit_at IS NULL THEN enplu.last_edit_comment
               WHEN enplu.last_edit_at > enpes.last_edit_at THEN enplu.last_edit_comment
               ELSE enpes.last_edit_comment
             END AS last_edit_comment
           , CASE
               WHEN enplu.last_edit_at IS NULL AND enpes.last_edit_at IS NULL THEN NULL
               WHEN enplu.last_edit_at IS NULL THEN enpes.last_edit_by_user_id
               WHEN enpes.last_edit_at IS NULL THEN enplu.last_edit_by_user_id
               WHEN enplu.last_edit_at > enpes.last_edit_at THEN enplu.last_edit_by_user_id
               ELSE enpes.last_edit_by_user_id
             END AS last_edit_by_user_id
           , GREATEST(enplu.last_edit_at, enpes.last_edit_at) AS last_edit_at
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

-- Create the physical unlogged table to store the view results
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
CREATE INDEX IF NOT EXISTS idx_timeline_enterprise_search ON public.timeline_enterprise
    USING gin (search);
CREATE INDEX IF NOT EXISTS idx_timeline_enterprise_establishment_ids ON public.timeline_enterprise
    USING gin (establishment_ids);
CREATE INDEX IF NOT EXISTS idx_timeline_enterprise_legal_unit_ids ON public.timeline_enterprise
    USING gin (legal_unit_ids);

-- Create a function to refresh the timeline_enterprise table
CREATE OR REPLACE FUNCTION public.timeline_enterprise_refresh(
    p_valid_after date DEFAULT NULL,
    p_valid_to date DEFAULT NULL
) RETURNS void LANGUAGE plpgsql AS $timeline_enterprise_refresh$
BEGIN
    -- Delete affected records from the main table
    DELETE FROM public.timeline_enterprise
    WHERE unit_type = 'enterprise'
    AND (p_valid_after IS NULL OR valid_after >= p_valid_after OR valid_to >= p_valid_after)
    AND (p_valid_to IS NULL OR valid_after <= p_valid_to OR valid_to <= p_valid_to);

    -- Insert directly from the definition view with filtering
    INSERT INTO public.timeline_enterprise
    SELECT * FROM public.timeline_enterprise_def
    WHERE unit_type = 'enterprise'
    AND (p_valid_after IS NULL OR valid_after >= p_valid_after OR valid_to >= p_valid_after)
    AND (p_valid_to IS NULL OR valid_after <= p_valid_to OR valid_to <= p_valid_to);
END;
$timeline_enterprise_refresh$;

-- Initial population of the timeline_enterprise table
SELECT public.timeline_enterprise_refresh();

END;
