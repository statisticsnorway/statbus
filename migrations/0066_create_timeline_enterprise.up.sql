\echo public.timeline_enterprise
CREATE VIEW public.timeline_enterprise
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
    , secondary_activity_category_id
    , secondary_activity_category_path
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
    , physical_address_part1
    , physical_address_part2
    , physical_address_part3
    , physical_postal_code
    , physical_postal_place
    , physical_region_id
    , physical_region_path
    , physical_country_id
    , physical_country_iso_2
    , postal_address_part1
    , postal_address_part2
    , postal_address_part3
    , postal_postal_code
    , postal_postal_place
    , postal_region_id
    , postal_region_path
    , postal_country_id
    , postal_country_iso_2
    , invalid_codes
    , has_legal_unit
    , establishment_ids
    , legal_unit_ids
    , enterprise_id
    , primary_establishment_id
    , primary_legal_unit_id
    , stats_summary
    )
    AS
      WITH basis_with_legal_unit AS (
      SELECT t.unit_type
           , t.unit_id
           , t.valid_after
           , (t.valid_after + '1 day'::INTERVAL)::DATE AS valid_from
           , t.valid_to
           , plu.name AS name
           , plu.birth_date AS birth_date
           , plu.death_date AS death_date
           -- Se supported languages with `SELECT * FROM pg_ts_config`
           , to_tsvector('simple', plu.name) AS search
           --
           , pa.category_id AS primary_activity_category_id
           , pac.path                AS primary_activity_category_path
           --
           , sa.category_id AS secondary_activity_category_id
           , sac.path                AS secondary_activity_category_path
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
           , phl.postal_code AS physical_postal_code
           , phl.postal_place AS physical_postal_place
           , phl.region_id           AS physical_region_id
           , phr.path                AS physical_region_path
           , phl.country_id AS physical_country_id
           , phc.iso_2     AS physical_country_iso_2
           --
           , pol.address_part1 AS postal_address_part1
           , pol.address_part2 AS postal_address_part2
           , pol.address_part3 AS postal_address_part3
           , pol.postal_code AS postal_postal_code
           , pol.postal_place AS postal_postal_place
           , pol.region_id           AS postal_region_id
           , por.path                AS postal_region_path
           , pol.country_id AS postal_country_id
           , poc.iso_2     AS postal_country_iso_2
           --
           , plu.invalid_codes AS invalid_codes
           --
           , TRUE AS has_legal_unit
           --
           , en.id AS enterprise_id
           , plu.id AS primary_legal_unit_id
      FROM public.timesegments AS t
      INNER JOIN public.enterprise AS en
          ON t.unit_type = 'enterprise' AND t.unit_id = en.id
      INNER JOIN public.legal_unit AS plu
          ON plu.enterprise_id = en.id
          AND plu.primary_for_enterprise
          AND daterange(t.valid_after, t.valid_to, '(]')
           && daterange(plu.valid_after, plu.valid_to, '(]')
      --
      LEFT OUTER JOIN public.activity AS pa
              ON pa.legal_unit_id = plu.id
             AND pa.type = 'primary'
             AND daterange(t.valid_after, t.valid_to, '(]')
              && daterange(pa.valid_after, pa.valid_to, '(]')
      LEFT JOIN public.activity_category AS pac
              ON pa.category_id = pac.id
      --
      LEFT OUTER JOIN public.activity AS sa
              ON sa.legal_unit_id = plu.id
             AND sa.type = 'secondary'
             AND daterange(t.valid_after, t.valid_to, '(]')
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
             AND daterange(t.valid_after, t.valid_to, '(]')
              && daterange(phl.valid_after, phl.valid_to, '(]')
      LEFT JOIN public.region AS phr
              ON phl.region_id = phr.id
      LEFT JOIN public.country AS phc
              ON phl.country_id = phc.id
      --
      LEFT OUTER JOIN public.location AS pol
              ON pol.legal_unit_id = plu.id
             AND pol.type = 'postal'
             AND daterange(t.valid_after, t.valid_to, '(]')
              && daterange(pol.valid_after, pol.valid_to, '(]')
      LEFT JOIN public.region AS por
              ON pol.region_id = por.id
      LEFT JOIN public.country AS poc
              ON pol.country_id = poc.id
      LEFT JOIN LATERAL (
              SELECT array_agg(sfu.data_source_id) AS data_source_ids
              FROM public.stat_for_unit AS sfu
              WHERE sfu.legal_unit_id = plu.id
                AND daterange(t.valid_after, t.valid_to, '(]')
                && daterange(sfu.valid_after, sfu.valid_to, '(]')
        ) AS sfu ON TRUE
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
      ), basis_with_establishment AS (
      SELECT t.unit_type
           , t.unit_id
           , t.valid_after
           , (t.valid_after + '1 day'::INTERVAL)::DATE AS valid_from
           , t.valid_to
           , pes.name AS name
           , pes.birth_date AS birth_date
           , pes.death_date AS death_date
           -- Se supported languages with `SELECT * FROM pg_ts_config`
           , to_tsvector('simple', pes.name) AS search
           --
           , pa.category_id AS primary_activity_category_id
           , pac.path                AS primary_activity_category_path
           --
           , sa.category_id AS secondary_activity_category_id
           , sac.path                AS secondary_activity_category_path
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
           , phl.postal_code AS physical_postal_code
           , phl.postal_place AS physical_postal_place
           , phl.region_id           AS physical_region_id
           , phr.path                AS physical_region_path
           , phl.country_id AS physical_country_id
           , phc.iso_2     AS physical_country_iso_2
           --
           , pol.address_part1 AS postal_address_part1
           , pol.address_part2 AS postal_address_part2
           , pol.address_part3 AS postal_address_part3
           , pol.postal_code AS postal_postal_code
           , pol.postal_place AS postal_postal_place
           , pol.region_id           AS postal_region_id
           , por.path                AS postal_region_path
           , pol.country_id AS postal_country_id
           , poc.iso_2     AS postal_country_iso_2
           --
           , pes.invalid_codes AS invalid_codes
           --
           , FALSE AS has_legal_unit
           --
           , en.id AS enterprise_id
           , pes.id AS primary_establishment_id
      FROM public.timesegments AS t
      INNER JOIN public.enterprise AS en
          ON t.unit_type = 'enterprise' AND t.unit_id = en.id
      INNER JOIN public.establishment AS pes
          ON pes.enterprise_id = en.id
          AND daterange(t.valid_after, t.valid_to, '(]')
           && daterange(pes.valid_after, pes.valid_to, '(]')
      --
      LEFT OUTER JOIN public.activity AS pa
              ON pa.establishment_id = pes.id
             AND pa.type = 'primary'
             AND daterange(t.valid_after, t.valid_to, '(]')
              && daterange(pa.valid_after, pa.valid_to, '(]')
      LEFT JOIN public.activity_category AS pac
              ON pa.category_id = pac.id
      --
      LEFT OUTER JOIN public.activity AS sa
              ON sa.establishment_id = pes.id
             AND sa.type = 'secondary'
             AND daterange(t.valid_after, t.valid_to, '(]')
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
             AND daterange(t.valid_after, t.valid_to, '(]')
              && daterange(phl.valid_after, phl.valid_to, '(]')
      LEFT JOIN public.region AS phr
              ON phl.region_id = phr.id
      LEFT JOIN public.country AS phc
              ON phl.country_id = phc.id
      --
      LEFT OUTER JOIN public.location AS pol
              ON pol.establishment_id = pes.id
             AND pol.type = 'postal'
             AND daterange(t.valid_after, t.valid_to, '(]')
              && daterange(pol.valid_after, pol.valid_to, '(]')
      LEFT JOIN public.region AS por
              ON pol.region_id = por.id
      LEFT JOIN public.country AS poc
              ON pol.country_id = poc.id
      LEFT JOIN LATERAL (
            SELECT array_agg(sfu.data_source_id) AS data_source_ids
            FROM public.stat_for_unit AS sfu
            WHERE sfu.legal_unit_id = pes.id
              AND daterange(t.valid_after, t.valid_to, '(]')
              && daterange(sfu.valid_after, sfu.valid_to, '(]')
        ) AS sfu ON TRUE
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
      ), establishment_aggregation AS (
        SELECT tes.enterprise_id
             , basis.valid_after
             , basis.valid_to
             , public.array_distinct_concat(tes.data_source_ids) AS data_source_ids
             , public.array_distinct_concat(tes.data_source_codes) AS data_source_codes
             , array_agg(DISTINCT tes.establishment_id) FILTER (WHERE tes.establishment_id IS NOT NULL) AS establishment_ids
             , public.jsonb_stats_to_summary_agg(tes.stats) AS stats_summary
          FROM public.timeline_establishment AS tes
          INNER JOIN basis_with_establishment AS basis
           ON tes.enterprise_id = basis.enterprise_id
          AND daterange(basis.valid_after, basis.valid_to, '(]')
           && daterange(tes.valid_after, tes.valid_to, '(]')
        GROUP BY tes.enterprise_id, basis.valid_after , basis.valid_to
      ), legal_unit_aggregation AS (
        SELECT tlu.enterprise_id
             , basis.valid_after
             , basis.valid_to
             , public.array_distinct_concat(tlu.data_source_ids) AS data_source_ids
             , public.array_distinct_concat(tlu.data_source_codes) AS data_source_codes
             , public.array_distinct_concat(tlu.establishment_ids) AS establishment_ids
             , array_agg(DISTINCT tlu.legal_unit_id) FILTER (WHERE tlu.legal_unit_id IS NOT NULL) AS legal_unit_ids
             , public.jsonb_stats_summary_merge_agg(tlu.stats_summary) AS stats_summary
          FROM public.timeline_legal_unit AS tlu
          INNER JOIN basis_with_legal_unit AS basis
           ON tlu.enterprise_id = basis.enterprise_id
          AND daterange(basis.valid_after, basis.valid_to, '(]')
           && daterange(tlu.valid_after, tlu.valid_to, '(]')
        GROUP BY tlu.enterprise_id, basis.valid_after , basis.valid_to
        ), basis_with_legal_unit_aggregation AS (
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
               , basis.secondary_activity_category_id
               , basis.secondary_activity_category_path
               , basis.activity_category_paths
               , basis.sector_id
               , basis.sector_path
               , basis.sector_code
               , basis.sector_name
               , (
                   SELECT array_agg(DISTINCT id)
                   FROM (
                       SELECT unnest(basis.data_source_ids) AS id
                       UNION
                       SELECT unnest(lua.data_source_ids) AS id
                   ) AS ids
               ) AS data_source_ids
               , (
                   SELECT array_agg(DISTINCT code)
                   FROM (
                       SELECT unnest(basis.data_source_codes) AS code
                       UNION ALL
                       SELECT unnest(lua.data_source_codes) AS code
                   ) AS codes
               ) AS data_source_codes
               , basis.legal_form_id
               , basis.legal_form_code
               , basis.legal_form_name
               , basis.physical_address_part1
               , basis.physical_address_part2
               , basis.physical_address_part3
               , basis.physical_postal_code
               , basis.physical_postal_place
               , basis.physical_region_id
               , basis.physical_region_path
               , basis.physical_country_id
               , basis.physical_country_iso_2
               , basis.postal_address_part1
               , basis.postal_address_part2
               , basis.postal_address_part3
               , basis.postal_postal_code
               , basis.postal_postal_place
               , basis.postal_region_id
               , basis.postal_region_path
               , basis.postal_country_id
               , basis.postal_country_iso_2
               , basis.invalid_codes
               , basis.has_legal_unit
               , COALESCE(lua.establishment_ids, ARRAY[]::INT[]) AS establishment_ids
               , COALESCE(lua.legal_unit_ids, ARRAY[]::INT[]) AS legal_unit_ids
               , basis.enterprise_id
               , NULL::INTEGER AS primary_establishment_id
               , basis.primary_legal_unit_id
               , lua.stats_summary AS stats_summary
          FROM basis_with_legal_unit AS basis
          LEFT OUTER JOIN legal_unit_aggregation AS lua
                       ON basis.enterprise_id = lua.enterprise_id
                      AND basis.valid_after = lua.valid_after
                      AND basis.valid_to = lua.valid_to
        ), basis_with_establishment_aggregation AS (
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
               , basis.secondary_activity_category_id
               , basis.secondary_activity_category_path
               , basis.activity_category_paths
               , basis.sector_id
               , basis.sector_path
               , basis.sector_code
               , basis.sector_name
               , (
                   SELECT array_agg(DISTINCT id)
                   FROM (
                       SELECT unnest(basis.data_source_ids) AS id
                       UNION
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
               , basis.physical_address_part1
               , basis.physical_address_part2
               , basis.physical_address_part3
               , basis.physical_postal_code
               , basis.physical_postal_place
               , basis.physical_region_id
               , basis.physical_region_path
               , basis.physical_country_id
               , basis.physical_country_iso_2
               , basis.postal_address_part1
               , basis.postal_address_part2
               , basis.postal_address_part3
               , basis.postal_postal_code
               , basis.postal_postal_place
               , basis.postal_region_id
               , basis.postal_region_path
               , basis.postal_country_id
               , basis.postal_country_iso_2
               , basis.invalid_codes
               , basis.has_legal_unit
               , COALESCE(esa.establishment_ids, ARRAY[]::INT[]) AS establishment_ids
               , ARRAY[]::INT[] AS legal_unit_ids
               , basis.enterprise_id
               , basis.primary_establishment_id
               , NULL::INTEGER AS primary_legal_unit_id
               , esa.stats_summary AS stats_summary
          FROM basis_with_establishment AS basis
          LEFT OUTER JOIN establishment_aggregation AS esa
                       ON basis.enterprise_id = esa.enterprise_id
                      AND basis.valid_after = esa.valid_after
                      AND basis.valid_to = esa.valid_to
        ), basis_with_both AS (
            SELECT * FROM basis_with_legal_unit_aggregation
            UNION ALL
            SELECT * FROM basis_with_establishment_aggregation
        )
        SELECT * FROM basis_with_both
         ORDER BY unit_type, unit_id, valid_after
;
