```sql
                                          View "public.timeline_enterprise"
              Column              |          Type          | Collation | Nullable | Default | Storage  | Description 
----------------------------------+------------------------+-----------+----------+---------+----------+-------------
 unit_type                        | statistical_unit_type  |           |          |         | plain    | 
 unit_id                          | integer                |           |          |         | plain    | 
 valid_after                      | date                   |           |          |         | plain    | 
 valid_from                       | date                   |           |          |         | plain    | 
 valid_to                         | date                   |           |          |         | plain    | 
 name                             | character varying(256) |           |          |         | extended | 
 birth_date                       | date                   |           |          |         | plain    | 
 death_date                       | date                   |           |          |         | plain    | 
 search                           | tsvector               |           |          |         | extended | 
 primary_activity_category_id     | integer                |           |          |         | plain    | 
 primary_activity_category_path   | ltree                  |           |          |         | extended | 
 secondary_activity_category_id   | integer                |           |          |         | plain    | 
 secondary_activity_category_path | ltree                  |           |          |         | extended | 
 activity_category_paths          | ltree[]                |           |          |         | extended | 
 sector_id                        | integer                |           |          |         | plain    | 
 sector_path                      | ltree                  |           |          |         | extended | 
 sector_code                      | character varying      |           |          |         | extended | 
 sector_name                      | text                   |           |          |         | extended | 
 data_source_ids                  | integer[]              |           |          |         | extended | 
 data_source_codes                | text[]                 |           |          |         | extended | 
 legal_form_id                    | integer                |           |          |         | plain    | 
 legal_form_code                  | text                   |           |          |         | extended | 
 legal_form_name                  | text                   |           |          |         | extended | 
 physical_address_part1           | character varying(200) |           |          |         | extended | 
 physical_address_part2           | character varying(200) |           |          |         | extended | 
 physical_address_part3           | character varying(200) |           |          |         | extended | 
 physical_postcode                | character varying(200) |           |          |         | extended | 
 physical_postplace               | character varying(200) |           |          |         | extended | 
 physical_region_id               | integer                |           |          |         | plain    | 
 physical_region_path             | ltree                  |           |          |         | extended | 
 physical_country_id              | integer                |           |          |         | plain    | 
 physical_country_iso_2           | text                   |           |          |         | extended | 
 postal_address_part1             | character varying(200) |           |          |         | extended | 
 postal_address_part2             | character varying(200) |           |          |         | extended | 
 postal_address_part3             | character varying(200) |           |          |         | extended | 
 postal_postcode                  | character varying(200) |           |          |         | extended | 
 postal_postplace                 | character varying(200) |           |          |         | extended | 
 postal_region_id                 | integer                |           |          |         | plain    | 
 postal_region_path               | ltree                  |           |          |         | extended | 
 postal_country_id                | integer                |           |          |         | plain    | 
 postal_country_iso_2             | text                   |           |          |         | extended | 
 invalid_codes                    | jsonb                  |           |          |         | extended | 
 has_legal_unit                   | boolean                |           |          |         | plain    | 
 establishment_ids                | integer[]              |           |          |         | extended | 
 legal_unit_ids                   | integer[]              |           |          |         | extended | 
 enterprise_id                    | integer                |           |          |         | plain    | 
 primary_establishment_id         | integer                |           |          |         | plain    | 
 primary_legal_unit_id            | integer                |           |          |         | plain    | 
 stats_summary                    | jsonb                  |           |          |         | extended | 
View definition:
 WITH basis_with_legal_unit AS (
         SELECT t.unit_type,
            t.unit_id,
            t.valid_after,
            (t.valid_after + '1 day'::interval)::date AS valid_from,
            t.valid_to,
            plu.name,
            plu.birth_date,
            plu.death_date,
            to_tsvector('simple'::regconfig, plu.name::text) AS search,
            pa.category_id AS primary_activity_category_id,
            pac.path AS primary_activity_category_path,
            sa.category_id AS secondary_activity_category_id,
            sac.path AS secondary_activity_category_path,
            NULLIF(array_remove(ARRAY[pac.path, sac.path], NULL::ltree), '{}'::ltree[]) AS activity_category_paths,
            s.id AS sector_id,
            s.path AS sector_path,
            s.code AS sector_code,
            s.name AS sector_name,
            COALESCE(ds.ids, ARRAY[]::integer[]) AS data_source_ids,
            COALESCE(ds.codes, ARRAY[]::text[]) AS data_source_codes,
            lf.id AS legal_form_id,
            lf.code AS legal_form_code,
            lf.name AS legal_form_name,
            phl.address_part1 AS physical_address_part1,
            phl.address_part2 AS physical_address_part2,
            phl.address_part3 AS physical_address_part3,
            phl.postcode AS physical_postcode,
            phl.postplace AS physical_postplace,
            phl.region_id AS physical_region_id,
            phr.path AS physical_region_path,
            phl.country_id AS physical_country_id,
            phc.iso_2 AS physical_country_iso_2,
            pol.address_part1 AS postal_address_part1,
            pol.address_part2 AS postal_address_part2,
            pol.address_part3 AS postal_address_part3,
            pol.postcode AS postal_postcode,
            pol.postplace AS postal_postplace,
            pol.region_id AS postal_region_id,
            por.path AS postal_region_path,
            pol.country_id AS postal_country_id,
            poc.iso_2 AS postal_country_iso_2,
            plu.invalid_codes,
            true AS has_legal_unit,
            en.id AS enterprise_id,
            plu.id AS primary_legal_unit_id
           FROM timesegments t
             JOIN enterprise en ON t.unit_type = 'enterprise'::statistical_unit_type AND t.unit_id = en.id
             JOIN legal_unit plu ON plu.enterprise_id = en.id AND plu.primary_for_enterprise AND daterange(t.valid_after, t.valid_to, '(]'::text) && daterange(plu.valid_after, plu.valid_to, '(]'::text)
             LEFT JOIN activity pa ON pa.legal_unit_id = plu.id AND pa.type = 'primary'::activity_type AND daterange(t.valid_after, t.valid_to, '(]'::text) && daterange(pa.valid_after, pa.valid_to, '(]'::text)
             LEFT JOIN activity_category pac ON pa.category_id = pac.id
             LEFT JOIN activity sa ON sa.legal_unit_id = plu.id AND sa.type = 'secondary'::activity_type AND daterange(t.valid_after, t.valid_to, '(]'::text) && daterange(sa.valid_after, sa.valid_to, '(]'::text)
             LEFT JOIN activity_category sac ON sa.category_id = sac.id
             LEFT JOIN sector s ON plu.sector_id = s.id
             LEFT JOIN legal_form lf ON plu.legal_form_id = lf.id
             LEFT JOIN location phl ON phl.legal_unit_id = plu.id AND phl.type = 'physical'::location_type AND daterange(t.valid_after, t.valid_to, '(]'::text) && daterange(phl.valid_after, phl.valid_to, '(]'::text)
             LEFT JOIN region phr ON phl.region_id = phr.id
             LEFT JOIN country phc ON phl.country_id = phc.id
             LEFT JOIN location pol ON pol.legal_unit_id = plu.id AND pol.type = 'postal'::location_type AND daterange(t.valid_after, t.valid_to, '(]'::text) && daterange(pol.valid_after, pol.valid_to, '(]'::text)
             LEFT JOIN region por ON pol.region_id = por.id
             LEFT JOIN country poc ON pol.country_id = poc.id
             LEFT JOIN LATERAL ( SELECT array_agg(sfu_1.data_source_id) AS data_source_ids
                   FROM stat_for_unit sfu_1
                  WHERE sfu_1.legal_unit_id = plu.id AND daterange(t.valid_after, t.valid_to, '(]'::text) && daterange(sfu_1.valid_after, sfu_1.valid_to, '(]'::text)) sfu ON true
             LEFT JOIN LATERAL ( SELECT array_agg(ds_1.id) AS ids,
                    array_agg(ds_1.code) AS codes
                   FROM data_source ds_1
                  WHERE COALESCE(ds_1.id = plu.data_source_id, false) OR COALESCE(ds_1.id = pa.data_source_id, false) OR COALESCE(ds_1.id = sa.data_source_id, false) OR COALESCE(ds_1.id = phl.data_source_id, false) OR COALESCE(ds_1.id = pol.data_source_id, false) OR COALESCE(ds_1.id = ANY (sfu.data_source_ids), false)) ds ON true
        ), basis_with_establishment AS (
         SELECT t.unit_type,
            t.unit_id,
            t.valid_after,
            (t.valid_after + '1 day'::interval)::date AS valid_from,
            t.valid_to,
            pes.name,
            pes.birth_date,
            pes.death_date,
            to_tsvector('simple'::regconfig, pes.name::text) AS search,
            pa.category_id AS primary_activity_category_id,
            pac.path AS primary_activity_category_path,
            sa.category_id AS secondary_activity_category_id,
            sac.path AS secondary_activity_category_path,
            NULLIF(array_remove(ARRAY[pac.path, sac.path], NULL::ltree), '{}'::ltree[]) AS activity_category_paths,
            s.id AS sector_id,
            s.path AS sector_path,
            s.code AS sector_code,
            s.name AS sector_name,
            COALESCE(ds.ids, ARRAY[]::integer[]) AS data_source_ids,
            COALESCE(ds.codes, ARRAY[]::text[]) AS data_source_codes,
            NULL::integer AS legal_form_id,
            NULL::character varying AS legal_form_code,
            NULL::character varying AS legal_form_name,
            phl.address_part1 AS physical_address_part1,
            phl.address_part2 AS physical_address_part2,
            phl.address_part3 AS physical_address_part3,
            phl.postcode AS physical_postcode,
            phl.postplace AS physical_postplace,
            phl.region_id AS physical_region_id,
            phr.path AS physical_region_path,
            phl.country_id AS physical_country_id,
            phc.iso_2 AS physical_country_iso_2,
            pol.address_part1 AS postal_address_part1,
            pol.address_part2 AS postal_address_part2,
            pol.address_part3 AS postal_address_part3,
            pol.postcode AS postal_postcode,
            pol.postplace AS postal_postplace,
            pol.region_id AS postal_region_id,
            por.path AS postal_region_path,
            pol.country_id AS postal_country_id,
            poc.iso_2 AS postal_country_iso_2,
            pes.invalid_codes,
            false AS has_legal_unit,
            en.id AS enterprise_id,
            pes.id AS primary_establishment_id
           FROM timesegments t
             JOIN enterprise en ON t.unit_type = 'enterprise'::statistical_unit_type AND t.unit_id = en.id
             JOIN establishment pes ON pes.enterprise_id = en.id AND daterange(t.valid_after, t.valid_to, '(]'::text) && daterange(pes.valid_after, pes.valid_to, '(]'::text)
             LEFT JOIN activity pa ON pa.establishment_id = pes.id AND pa.type = 'primary'::activity_type AND daterange(t.valid_after, t.valid_to, '(]'::text) && daterange(pa.valid_after, pa.valid_to, '(]'::text)
             LEFT JOIN activity_category pac ON pa.category_id = pac.id
             LEFT JOIN activity sa ON sa.establishment_id = pes.id AND sa.type = 'secondary'::activity_type AND daterange(t.valid_after, t.valid_to, '(]'::text) && daterange(sa.valid_after, sa.valid_to, '(]'::text)
             LEFT JOIN activity_category sac ON sa.category_id = sac.id
             LEFT JOIN sector s ON pes.sector_id = s.id
             LEFT JOIN location phl ON phl.establishment_id = pes.id AND phl.type = 'physical'::location_type AND daterange(t.valid_after, t.valid_to, '(]'::text) && daterange(phl.valid_after, phl.valid_to, '(]'::text)
             LEFT JOIN region phr ON phl.region_id = phr.id
             LEFT JOIN country phc ON phl.country_id = phc.id
             LEFT JOIN location pol ON pol.establishment_id = pes.id AND pol.type = 'postal'::location_type AND daterange(t.valid_after, t.valid_to, '(]'::text) && daterange(pol.valid_after, pol.valid_to, '(]'::text)
             LEFT JOIN region por ON pol.region_id = por.id
             LEFT JOIN country poc ON pol.country_id = poc.id
             LEFT JOIN LATERAL ( SELECT array_agg(sfu_1.data_source_id) AS data_source_ids
                   FROM stat_for_unit sfu_1
                  WHERE sfu_1.legal_unit_id = pes.id AND daterange(t.valid_after, t.valid_to, '(]'::text) && daterange(sfu_1.valid_after, sfu_1.valid_to, '(]'::text)) sfu ON true
             LEFT JOIN LATERAL ( SELECT array_agg(ds_1.id) AS ids,
                    array_agg(ds_1.code) AS codes
                   FROM data_source ds_1
                  WHERE COALESCE(ds_1.id = pes.data_source_id, false) OR COALESCE(ds_1.id = pa.data_source_id, false) OR COALESCE(ds_1.id = sa.data_source_id, false) OR COALESCE(ds_1.id = phl.data_source_id, false) OR COALESCE(ds_1.id = pol.data_source_id, false) OR COALESCE(ds_1.id = ANY (sfu.data_source_ids), false)) ds ON true
        ), establishment_aggregation AS (
         SELECT tes.enterprise_id,
            basis.valid_after,
            basis.valid_to,
            array_distinct_concat(tes.data_source_ids) AS data_source_ids,
            array_distinct_concat(tes.data_source_codes) AS data_source_codes,
            array_agg(DISTINCT tes.establishment_id) FILTER (WHERE tes.establishment_id IS NOT NULL) AS establishment_ids,
            jsonb_stats_to_summary_agg(tes.stats) AS stats_summary
           FROM timeline_establishment tes
             JOIN basis_with_establishment basis ON tes.enterprise_id = basis.enterprise_id AND daterange(basis.valid_after, basis.valid_to, '(]'::text) && daterange(tes.valid_after, tes.valid_to, '(]'::text)
          GROUP BY tes.enterprise_id, basis.valid_after, basis.valid_to
        ), legal_unit_aggregation AS (
         SELECT tlu.enterprise_id,
            basis.valid_after,
            basis.valid_to,
            array_distinct_concat(tlu.data_source_ids) AS data_source_ids,
            array_distinct_concat(tlu.data_source_codes) AS data_source_codes,
            array_distinct_concat(tlu.establishment_ids) AS establishment_ids,
            array_agg(DISTINCT tlu.legal_unit_id) FILTER (WHERE tlu.legal_unit_id IS NOT NULL) AS legal_unit_ids,
            jsonb_stats_summary_merge_agg(tlu.stats_summary) AS stats_summary
           FROM timeline_legal_unit tlu
             JOIN basis_with_legal_unit basis ON tlu.enterprise_id = basis.enterprise_id AND daterange(basis.valid_after, basis.valid_to, '(]'::text) && daterange(tlu.valid_after, tlu.valid_to, '(]'::text)
          GROUP BY tlu.enterprise_id, basis.valid_after, basis.valid_to
        ), basis_with_legal_unit_aggregation AS (
         SELECT basis.unit_type,
            basis.unit_id,
            basis.valid_after,
            basis.valid_from,
            basis.valid_to,
            basis.name,
            basis.birth_date,
            basis.death_date,
            basis.search,
            basis.primary_activity_category_id,
            basis.primary_activity_category_path,
            basis.secondary_activity_category_id,
            basis.secondary_activity_category_path,
            basis.activity_category_paths,
            basis.sector_id,
            basis.sector_path,
            basis.sector_code,
            basis.sector_name,
            ( SELECT array_agg(DISTINCT ids.id) AS array_agg
                   FROM ( SELECT unnest(basis.data_source_ids) AS id
                        UNION
                         SELECT unnest(lua.data_source_ids) AS id) ids) AS data_source_ids,
            ( SELECT array_agg(DISTINCT codes.code) AS array_agg
                   FROM ( SELECT unnest(basis.data_source_codes) AS code
                        UNION ALL
                         SELECT unnest(lua.data_source_codes) AS code) codes) AS data_source_codes,
            basis.legal_form_id,
            basis.legal_form_code,
            basis.legal_form_name,
            basis.physical_address_part1,
            basis.physical_address_part2,
            basis.physical_address_part3,
            basis.physical_postcode,
            basis.physical_postplace,
            basis.physical_region_id,
            basis.physical_region_path,
            basis.physical_country_id,
            basis.physical_country_iso_2,
            basis.postal_address_part1,
            basis.postal_address_part2,
            basis.postal_address_part3,
            basis.postal_postcode,
            basis.postal_postplace,
            basis.postal_region_id,
            basis.postal_region_path,
            basis.postal_country_id,
            basis.postal_country_iso_2,
            basis.invalid_codes,
            basis.has_legal_unit,
            COALESCE(lua.establishment_ids, ARRAY[]::integer[]) AS establishment_ids,
            COALESCE(lua.legal_unit_ids, ARRAY[]::integer[]) AS legal_unit_ids,
            basis.enterprise_id,
            NULL::integer AS primary_establishment_id,
            basis.primary_legal_unit_id,
            lua.stats_summary
           FROM basis_with_legal_unit basis
             LEFT JOIN legal_unit_aggregation lua ON basis.enterprise_id = lua.enterprise_id AND basis.valid_after = lua.valid_after AND basis.valid_to = lua.valid_to
        ), basis_with_establishment_aggregation AS (
         SELECT basis.unit_type,
            basis.unit_id,
            basis.valid_after,
            basis.valid_from,
            basis.valid_to,
            basis.name,
            basis.birth_date,
            basis.death_date,
            basis.search,
            basis.primary_activity_category_id,
            basis.primary_activity_category_path,
            basis.secondary_activity_category_id,
            basis.secondary_activity_category_path,
            basis.activity_category_paths,
            basis.sector_id,
            basis.sector_path,
            basis.sector_code,
            basis.sector_name,
            ( SELECT array_agg(DISTINCT ids.id) AS array_agg
                   FROM ( SELECT unnest(basis.data_source_ids) AS id
                        UNION
                         SELECT unnest(esa.data_source_ids) AS id) ids) AS data_source_ids,
            ( SELECT array_agg(DISTINCT codes.code) AS array_agg
                   FROM ( SELECT unnest(basis.data_source_codes) AS code
                        UNION ALL
                         SELECT unnest(esa.data_source_codes) AS code) codes) AS data_source_codes,
            basis.legal_form_id,
            basis.legal_form_code,
            basis.legal_form_name,
            basis.physical_address_part1,
            basis.physical_address_part2,
            basis.physical_address_part3,
            basis.physical_postcode,
            basis.physical_postplace,
            basis.physical_region_id,
            basis.physical_region_path,
            basis.physical_country_id,
            basis.physical_country_iso_2,
            basis.postal_address_part1,
            basis.postal_address_part2,
            basis.postal_address_part3,
            basis.postal_postcode,
            basis.postal_postplace,
            basis.postal_region_id,
            basis.postal_region_path,
            basis.postal_country_id,
            basis.postal_country_iso_2,
            basis.invalid_codes,
            basis.has_legal_unit,
            COALESCE(esa.establishment_ids, ARRAY[]::integer[]) AS establishment_ids,
            ARRAY[]::integer[] AS legal_unit_ids,
            basis.enterprise_id,
            basis.primary_establishment_id,
            NULL::integer AS primary_legal_unit_id,
            esa.stats_summary
           FROM basis_with_establishment basis
             LEFT JOIN establishment_aggregation esa ON basis.enterprise_id = esa.enterprise_id AND basis.valid_after = esa.valid_after AND basis.valid_to = esa.valid_to
        ), basis_with_both AS (
         SELECT basis_with_legal_unit_aggregation.unit_type,
            basis_with_legal_unit_aggregation.unit_id,
            basis_with_legal_unit_aggregation.valid_after,
            basis_with_legal_unit_aggregation.valid_from,
            basis_with_legal_unit_aggregation.valid_to,
            basis_with_legal_unit_aggregation.name,
            basis_with_legal_unit_aggregation.birth_date,
            basis_with_legal_unit_aggregation.death_date,
            basis_with_legal_unit_aggregation.search,
            basis_with_legal_unit_aggregation.primary_activity_category_id,
            basis_with_legal_unit_aggregation.primary_activity_category_path,
            basis_with_legal_unit_aggregation.secondary_activity_category_id,
            basis_with_legal_unit_aggregation.secondary_activity_category_path,
            basis_with_legal_unit_aggregation.activity_category_paths,
            basis_with_legal_unit_aggregation.sector_id,
            basis_with_legal_unit_aggregation.sector_path,
            basis_with_legal_unit_aggregation.sector_code,
            basis_with_legal_unit_aggregation.sector_name,
            basis_with_legal_unit_aggregation.data_source_ids,
            basis_with_legal_unit_aggregation.data_source_codes,
            basis_with_legal_unit_aggregation.legal_form_id,
            basis_with_legal_unit_aggregation.legal_form_code,
            basis_with_legal_unit_aggregation.legal_form_name,
            basis_with_legal_unit_aggregation.physical_address_part1,
            basis_with_legal_unit_aggregation.physical_address_part2,
            basis_with_legal_unit_aggregation.physical_address_part3,
            basis_with_legal_unit_aggregation.physical_postcode,
            basis_with_legal_unit_aggregation.physical_postplace,
            basis_with_legal_unit_aggregation.physical_region_id,
            basis_with_legal_unit_aggregation.physical_region_path,
            basis_with_legal_unit_aggregation.physical_country_id,
            basis_with_legal_unit_aggregation.physical_country_iso_2,
            basis_with_legal_unit_aggregation.postal_address_part1,
            basis_with_legal_unit_aggregation.postal_address_part2,
            basis_with_legal_unit_aggregation.postal_address_part3,
            basis_with_legal_unit_aggregation.postal_postcode,
            basis_with_legal_unit_aggregation.postal_postplace,
            basis_with_legal_unit_aggregation.postal_region_id,
            basis_with_legal_unit_aggregation.postal_region_path,
            basis_with_legal_unit_aggregation.postal_country_id,
            basis_with_legal_unit_aggregation.postal_country_iso_2,
            basis_with_legal_unit_aggregation.invalid_codes,
            basis_with_legal_unit_aggregation.has_legal_unit,
            basis_with_legal_unit_aggregation.establishment_ids,
            basis_with_legal_unit_aggregation.legal_unit_ids,
            basis_with_legal_unit_aggregation.enterprise_id,
            basis_with_legal_unit_aggregation.primary_establishment_id,
            basis_with_legal_unit_aggregation.primary_legal_unit_id,
            basis_with_legal_unit_aggregation.stats_summary
           FROM basis_with_legal_unit_aggregation
        UNION ALL
         SELECT basis_with_establishment_aggregation.unit_type,
            basis_with_establishment_aggregation.unit_id,
            basis_with_establishment_aggregation.valid_after,
            basis_with_establishment_aggregation.valid_from,
            basis_with_establishment_aggregation.valid_to,
            basis_with_establishment_aggregation.name,
            basis_with_establishment_aggregation.birth_date,
            basis_with_establishment_aggregation.death_date,
            basis_with_establishment_aggregation.search,
            basis_with_establishment_aggregation.primary_activity_category_id,
            basis_with_establishment_aggregation.primary_activity_category_path,
            basis_with_establishment_aggregation.secondary_activity_category_id,
            basis_with_establishment_aggregation.secondary_activity_category_path,
            basis_with_establishment_aggregation.activity_category_paths,
            basis_with_establishment_aggregation.sector_id,
            basis_with_establishment_aggregation.sector_path,
            basis_with_establishment_aggregation.sector_code,
            basis_with_establishment_aggregation.sector_name,
            basis_with_establishment_aggregation.data_source_ids,
            basis_with_establishment_aggregation.data_source_codes,
            basis_with_establishment_aggregation.legal_form_id,
            basis_with_establishment_aggregation.legal_form_code,
            basis_with_establishment_aggregation.legal_form_name,
            basis_with_establishment_aggregation.physical_address_part1,
            basis_with_establishment_aggregation.physical_address_part2,
            basis_with_establishment_aggregation.physical_address_part3,
            basis_with_establishment_aggregation.physical_postcode,
            basis_with_establishment_aggregation.physical_postplace,
            basis_with_establishment_aggregation.physical_region_id,
            basis_with_establishment_aggregation.physical_region_path,
            basis_with_establishment_aggregation.physical_country_id,
            basis_with_establishment_aggregation.physical_country_iso_2,
            basis_with_establishment_aggregation.postal_address_part1,
            basis_with_establishment_aggregation.postal_address_part2,
            basis_with_establishment_aggregation.postal_address_part3,
            basis_with_establishment_aggregation.postal_postcode,
            basis_with_establishment_aggregation.postal_postplace,
            basis_with_establishment_aggregation.postal_region_id,
            basis_with_establishment_aggregation.postal_region_path,
            basis_with_establishment_aggregation.postal_country_id,
            basis_with_establishment_aggregation.postal_country_iso_2,
            basis_with_establishment_aggregation.invalid_codes,
            basis_with_establishment_aggregation.has_legal_unit,
            basis_with_establishment_aggregation.establishment_ids,
            basis_with_establishment_aggregation.legal_unit_ids,
            basis_with_establishment_aggregation.enterprise_id,
            basis_with_establishment_aggregation.primary_establishment_id,
            basis_with_establishment_aggregation.primary_legal_unit_id,
            basis_with_establishment_aggregation.stats_summary
           FROM basis_with_establishment_aggregation
        )
 SELECT basis_with_both.unit_type,
    basis_with_both.unit_id,
    basis_with_both.valid_after,
    basis_with_both.valid_from,
    basis_with_both.valid_to,
    basis_with_both.name,
    basis_with_both.birth_date,
    basis_with_both.death_date,
    basis_with_both.search,
    basis_with_both.primary_activity_category_id,
    basis_with_both.primary_activity_category_path,
    basis_with_both.secondary_activity_category_id,
    basis_with_both.secondary_activity_category_path,
    basis_with_both.activity_category_paths,
    basis_with_both.sector_id,
    basis_with_both.sector_path,
    basis_with_both.sector_code,
    basis_with_both.sector_name,
    basis_with_both.data_source_ids,
    basis_with_both.data_source_codes,
    basis_with_both.legal_form_id,
    basis_with_both.legal_form_code,
    basis_with_both.legal_form_name,
    basis_with_both.physical_address_part1,
    basis_with_both.physical_address_part2,
    basis_with_both.physical_address_part3,
    basis_with_both.physical_postcode,
    basis_with_both.physical_postplace,
    basis_with_both.physical_region_id,
    basis_with_both.physical_region_path,
    basis_with_both.physical_country_id,
    basis_with_both.physical_country_iso_2,
    basis_with_both.postal_address_part1,
    basis_with_both.postal_address_part2,
    basis_with_both.postal_address_part3,
    basis_with_both.postal_postcode,
    basis_with_both.postal_postplace,
    basis_with_both.postal_region_id,
    basis_with_both.postal_region_path,
    basis_with_both.postal_country_id,
    basis_with_both.postal_country_iso_2,
    basis_with_both.invalid_codes,
    basis_with_both.has_legal_unit,
    basis_with_both.establishment_ids,
    basis_with_both.legal_unit_ids,
    basis_with_both.enterprise_id,
    basis_with_both.primary_establishment_id,
    basis_with_both.primary_legal_unit_id,
    basis_with_both.stats_summary
   FROM basis_with_both
  ORDER BY basis_with_both.unit_type, basis_with_both.unit_id, basis_with_both.valid_after;

```
