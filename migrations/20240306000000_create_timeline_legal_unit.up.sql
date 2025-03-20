BEGIN;

CREATE VIEW public.timeline_legal_unit
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
    , legal_unit_id
    , enterprise_id
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
          SELECT lu.edit_comment, lu.edit_by_user_id, lu.edit_at
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
      ), establishment_aggregation AS (
        SELECT tes.legal_unit_id
             , basis.valid_after
             , basis.valid_to
             , public.array_distinct_concat(tes.data_source_ids) AS data_source_ids
             , public.array_distinct_concat(tes.data_source_codes) AS data_source_codes
             , array_agg(DISTINCT tes.establishment_id) FILTER (WHERE tes.establishment_id IS NOT NULL) AS establishment_ids
             , public.jsonb_stats_to_summary_agg(tes.stats) AS stats_summary
          FROM public.timeline_establishment AS tes
          INNER JOIN basis
           ON tes.legal_unit_id = basis.legal_unit_id
          AND daterange(basis.valid_after, basis.valid_to, '(]')
           && daterange(tes.valid_after, tes.valid_to, '(]')
        WHERE tes.include_unit_in_reports = basis.include_unit_in_reports
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
           , COALESCE(esa.establishment_ids, ARRAY[]::INT[]) AS establishment_ids
           , basis.legal_unit_id
           , basis.enterprise_id
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

END;
