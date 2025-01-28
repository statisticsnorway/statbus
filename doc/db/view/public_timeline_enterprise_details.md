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
 primary_activity_category_code   | character varying      |           |          |         | extended | 
 secondary_activity_category_id   | integer                |           |          |         | plain    | 
 secondary_activity_category_path | ltree                  |           |          |         | extended | 
 secondary_activity_category_code | character varying      |           |          |         | extended | 
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
 physical_region_code             | character varying      |           |          |         | extended | 
 physical_country_id              | integer                |           |          |         | plain    | 
 physical_country_iso_2           | text                   |           |          |         | extended | 
 physical_latitude                | numeric(9,6)           |           |          |         | main     | 
 physical_longitude               | numeric(9,6)           |           |          |         | main     | 
 physical_altitude                | numeric(6,1)           |           |          |         | main     | 
 postal_address_part1             | character varying(200) |           |          |         | extended | 
 postal_address_part2             | character varying(200) |           |          |         | extended | 
 postal_address_part3             | character varying(200) |           |          |         | extended | 
 postal_postcode                  | character varying(200) |           |          |         | extended | 
 postal_postplace                 | character varying(200) |           |          |         | extended | 
 postal_region_id                 | integer                |           |          |         | plain    | 
 postal_region_path               | ltree                  |           |          |         | extended | 
 postal_region_code               | character varying      |           |          |         | extended | 
 postal_country_id                | integer                |           |          |         | plain    | 
 postal_country_iso_2             | text                   |           |          |         | extended | 
 postal_latitude                  | numeric(9,6)           |           |          |         | main     | 
 postal_longitude                 | numeric(9,6)           |           |          |         | main     | 
 postal_altitude                  | numeric(6,1)           |           |          |         | main     | 
 web_address                      | character varying(256) |           |          |         | extended | 
 email_address                    | character varying(50)  |           |          |         | extended | 
 phone_number                     | character varying(50)  |           |          |         | extended | 
 landline                         | character varying(50)  |           |          |         | extended | 
 mobile_number                    | character varying(50)  |           |          |         | extended | 
 fax_number                       | character varying(50)  |           |          |         | extended | 
 status_id                        | integer                |           |          |         | plain    | 
 status_code                      | character varying      |           |          |         | extended | 
 invalid_codes                    | jsonb                  |           |          |         | extended | 
 has_legal_unit                   | boolean                |           |          |         | plain    | 
 establishment_ids                | integer[]              |           |          |         | extended | 
 legal_unit_ids                   | integer[]              |           |          |         | extended | 
 enterprise_id                    | integer                |           |          |         | plain    | 
 primary_establishment_id         | integer                |           |          |         | plain    | 
 primary_legal_unit_id            | integer                |           |          |         | plain    | 
 stats_summary                    | jsonb                  |           |          |         | extended | 
View definition:
 WITH timesegments_enterprise AS (
         SELECT t.unit_type,
            t.unit_id,
            t.valid_after,
            t.valid_to,
            en.id,
            en.active,
            en.short_name,
            en.edit_comment,
            en.edit_by_user_id,
            en.edit_at,
            en.id AS enterprise_id
           FROM timesegments t
             JOIN enterprise en ON t.unit_type = 'enterprise'::statistical_unit_type AND t.unit_id = en.id
        ), enterprise_with_primary_legal_unit AS (
         SELECT ten.unit_type,
            ten.unit_id,
            ten.valid_after,
            ten.valid_to,
            plu.name,
            plu.birth_date,
            plu.death_date,
            to_tsvector('simple'::regconfig, plu.name::text) AS search,
            pa.category_id AS primary_activity_category_id,
            pac.path AS primary_activity_category_path,
            pac.code AS primary_activity_category_code,
            sa.category_id AS secondary_activity_category_id,
            sac.path AS secondary_activity_category_path,
            sac.code AS secondary_activity_category_code,
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
            phr.code AS physical_region_code,
            phl.country_id AS physical_country_id,
            phc.iso_2 AS physical_country_iso_2,
            phl.latitude AS physical_latitude,
            phl.longitude AS physical_longitude,
            phl.altitude AS physical_altitude,
            pol.address_part1 AS postal_address_part1,
            pol.address_part2 AS postal_address_part2,
            pol.address_part3 AS postal_address_part3,
            pol.postcode AS postal_postcode,
            pol.postplace AS postal_postplace,
            pol.region_id AS postal_region_id,
            por.path AS postal_region_path,
            por.code AS postal_region_code,
            pol.country_id AS postal_country_id,
            poc.iso_2 AS postal_country_iso_2,
            pol.latitude AS postal_latitude,
            pol.longitude AS postal_longitude,
            pol.altitude AS postal_altitude,
            c.web_address,
            c.email_address,
            c.phone_number,
            c.landline,
            c.mobile_number,
            c.fax_number,
            st.id AS status_id,
            st.code AS status_code,
            plu.invalid_codes,
            true AS has_legal_unit,
            ten.id AS enterprise_id,
            plu.id AS primary_legal_unit_id
           FROM timesegments_enterprise ten
             JOIN legal_unit plu ON plu.enterprise_id = ten.enterprise_id AND plu.primary_for_enterprise AND daterange(ten.valid_after, ten.valid_to, '(]'::text) && daterange(plu.valid_after, plu.valid_to, '(]'::text)
             LEFT JOIN activity pa ON pa.legal_unit_id = plu.id AND pa.type = 'primary'::activity_type AND daterange(ten.valid_after, ten.valid_to, '(]'::text) && daterange(pa.valid_after, pa.valid_to, '(]'::text)
             LEFT JOIN activity_category pac ON pa.category_id = pac.id
             LEFT JOIN activity sa ON sa.legal_unit_id = plu.id AND sa.type = 'secondary'::activity_type AND daterange(ten.valid_after, ten.valid_to, '(]'::text) && daterange(sa.valid_after, sa.valid_to, '(]'::text)
             LEFT JOIN activity_category sac ON sa.category_id = sac.id
             LEFT JOIN sector s ON plu.sector_id = s.id
             LEFT JOIN legal_form lf ON plu.legal_form_id = lf.id
             LEFT JOIN location phl ON phl.legal_unit_id = plu.id AND phl.type = 'physical'::location_type AND daterange(ten.valid_after, ten.valid_to, '(]'::text) && daterange(phl.valid_after, phl.valid_to, '(]'::text)
             LEFT JOIN region phr ON phl.region_id = phr.id
             LEFT JOIN country phc ON phl.country_id = phc.id
             LEFT JOIN location pol ON pol.legal_unit_id = plu.id AND pol.type = 'postal'::location_type AND daterange(ten.valid_after, ten.valid_to, '(]'::text) && daterange(pol.valid_after, pol.valid_to, '(]'::text)
             LEFT JOIN region por ON pol.region_id = por.id
             LEFT JOIN country poc ON pol.country_id = poc.id
             LEFT JOIN contact c ON c.legal_unit_id = plu.id
             LEFT JOIN status st ON st.id = plu.status_id
             LEFT JOIN LATERAL ( SELECT array_agg(sfu_1.data_source_id) AS data_source_ids
                   FROM stat_for_unit sfu_1
                  WHERE sfu_1.legal_unit_id = plu.id AND daterange(ten.valid_after, ten.valid_to, '(]'::text) && daterange(sfu_1.valid_after, sfu_1.valid_to, '(]'::text)) sfu ON true
             LEFT JOIN LATERAL ( SELECT array_agg(ds_1.id) AS ids,
                    array_agg(ds_1.code) AS codes
                   FROM data_source ds_1
                  WHERE COALESCE(ds_1.id = plu.data_source_id, false) OR COALESCE(ds_1.id = pa.data_source_id, false) OR COALESCE(ds_1.id = sa.data_source_id, false) OR COALESCE(ds_1.id = phl.data_source_id, false) OR COALESCE(ds_1.id = pol.data_source_id, false) OR COALESCE(ds_1.id = ANY (sfu.data_source_ids), false)) ds ON true
        ), enterprise_with_primary_establishment AS (
         SELECT ten.unit_type,
            ten.unit_id,
            ten.valid_after,
            ten.valid_to,
            pes.name,
            pes.birth_date,
            pes.death_date,
            to_tsvector('simple'::regconfig, pes.name::text) AS search,
            pa.category_id AS primary_activity_category_id,
            pac.path AS primary_activity_category_path,
            pac.code AS primary_activity_category_code,
            sa.category_id AS secondary_activity_category_id,
            sac.path AS secondary_activity_category_path,
            sac.code AS secondary_activity_category_code,
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
            phr.code AS physical_region_code,
            phl.country_id AS physical_country_id,
            phc.iso_2 AS physical_country_iso_2,
            phl.latitude AS physical_latitude,
            phl.longitude AS physical_longitude,
            phl.altitude AS physical_altitude,
            pol.address_part1 AS postal_address_part1,
            pol.address_part2 AS postal_address_part2,
            pol.address_part3 AS postal_address_part3,
            pol.postcode AS postal_postcode,
            pol.postplace AS postal_postplace,
            pol.region_id AS postal_region_id,
            por.path AS postal_region_path,
            por.code AS postal_region_code,
            pol.country_id AS postal_country_id,
            poc.iso_2 AS postal_country_iso_2,
            pol.latitude AS postal_latitude,
            pol.longitude AS postal_longitude,
            pol.altitude AS postal_altitude,
            c.web_address,
            c.email_address,
            c.phone_number,
            c.landline,
            c.mobile_number,
            c.fax_number,
            st.id AS status_id,
            st.code AS status_code,
            pes.invalid_codes,
            false AS has_legal_unit,
            ten.id AS enterprise_id,
            pes.id AS primary_establishment_id
           FROM timesegments_enterprise ten
             JOIN establishment pes ON pes.enterprise_id = ten.id AND pes.primary_for_enterprise AND daterange(ten.valid_after, ten.valid_to, '(]'::text) && daterange(pes.valid_after, pes.valid_to, '(]'::text)
             LEFT JOIN activity pa ON pa.establishment_id = pes.id AND pa.type = 'primary'::activity_type AND daterange(ten.valid_after, ten.valid_to, '(]'::text) && daterange(pa.valid_after, pa.valid_to, '(]'::text)
             LEFT JOIN activity_category pac ON pa.category_id = pac.id
             LEFT JOIN activity sa ON sa.establishment_id = pes.id AND sa.type = 'secondary'::activity_type AND daterange(ten.valid_after, ten.valid_to, '(]'::text) && daterange(sa.valid_after, sa.valid_to, '(]'::text)
             LEFT JOIN activity_category sac ON sa.category_id = sac.id
             LEFT JOIN sector s ON pes.sector_id = s.id
             LEFT JOIN location phl ON phl.establishment_id = pes.id AND phl.type = 'physical'::location_type AND daterange(ten.valid_after, ten.valid_to, '(]'::text) && daterange(phl.valid_after, phl.valid_to, '(]'::text)
             LEFT JOIN region phr ON phl.region_id = phr.id
             LEFT JOIN country phc ON phl.country_id = phc.id
             LEFT JOIN location pol ON pol.establishment_id = pes.id AND pol.type = 'postal'::location_type AND daterange(ten.valid_after, ten.valid_to, '(]'::text) && daterange(pol.valid_after, pol.valid_to, '(]'::text)
             LEFT JOIN region por ON pol.region_id = por.id
             LEFT JOIN country poc ON pol.country_id = poc.id
             LEFT JOIN contact c ON c.establishment_id = pes.id
             LEFT JOIN status st ON st.id = pes.status_id
             LEFT JOIN LATERAL ( SELECT array_agg(sfu_1.data_source_id) AS data_source_ids
                   FROM stat_for_unit sfu_1
                  WHERE sfu_1.legal_unit_id = pes.id AND daterange(ten.valid_after, ten.valid_to, '(]'::text) && daterange(sfu_1.valid_after, sfu_1.valid_to, '(]'::text)) sfu ON true
             LEFT JOIN LATERAL ( SELECT array_agg(ds_1.id) AS ids,
                    array_agg(ds_1.code) AS codes
                   FROM data_source ds_1
                  WHERE COALESCE(ds_1.id = pes.data_source_id, false) OR COALESCE(ds_1.id = pa.data_source_id, false) OR COALESCE(ds_1.id = sa.data_source_id, false) OR COALESCE(ds_1.id = phl.data_source_id, false) OR COALESCE(ds_1.id = pol.data_source_id, false) OR COALESCE(ds_1.id = ANY (sfu.data_source_ids), false)) ds ON true
        ), enterprise_with_primary AS (
         SELECT ten.unit_type,
            ten.unit_id,
            ten.valid_after,
            ten.valid_to,
            COALESCE(enplu.name, enpes.name) AS name,
            COALESCE(enplu.birth_date, enpes.birth_date) AS birth_date,
            COALESCE(enplu.death_date, enpes.death_date) AS death_date,
            COALESCE(enplu.primary_activity_category_id, enpes.primary_activity_category_id) AS primary_activity_category_id,
            COALESCE(enplu.primary_activity_category_path, enpes.primary_activity_category_path) AS primary_activity_category_path,
            COALESCE(enplu.primary_activity_category_code, enpes.primary_activity_category_code) AS primary_activity_category_code,
            COALESCE(enplu.secondary_activity_category_id, enpes.secondary_activity_category_id) AS secondary_activity_category_id,
            COALESCE(enplu.secondary_activity_category_path, enpes.secondary_activity_category_path) AS secondary_activity_category_path,
            COALESCE(enplu.secondary_activity_category_code, enpes.secondary_activity_category_code) AS secondary_activity_category_code,
            COALESCE(enplu.sector_id, enpes.sector_id) AS sector_id,
            COALESCE(enplu.sector_path, enpes.sector_path) AS sector_path,
            COALESCE(enplu.sector_code, enpes.sector_code) AS sector_code,
            COALESCE(enplu.sector_name, enpes.sector_name) AS sector_name,
            ( SELECT array_agg(DISTINCT ids.id) AS array_agg
                   FROM ( SELECT unnest(enplu.data_source_ids) AS id
                        UNION
                         SELECT unnest(enpes.data_source_ids) AS id) ids) AS data_source_ids,
            ( SELECT array_agg(DISTINCT codes.code) AS array_agg
                   FROM ( SELECT unnest(enplu.data_source_codes) AS code
                        UNION
                         SELECT unnest(enpes.data_source_codes) AS code) codes) AS data_source_codes,
            enplu.legal_form_id,
            enplu.legal_form_code,
            enplu.legal_form_name,
            COALESCE(enplu.physical_address_part1, enpes.physical_address_part1) AS physical_address_part1,
            COALESCE(enplu.physical_address_part2, enpes.physical_address_part2) AS physical_address_part2,
            COALESCE(enplu.physical_address_part3, enpes.physical_address_part3) AS physical_address_part3,
            COALESCE(enplu.physical_postcode, enpes.physical_postcode) AS physical_postcode,
            COALESCE(enplu.physical_postplace, enpes.physical_postplace) AS physical_postplace,
            COALESCE(enplu.physical_region_id, enpes.physical_region_id) AS physical_region_id,
            COALESCE(enplu.physical_region_path, enpes.physical_region_path) AS physical_region_path,
            COALESCE(enplu.physical_region_code, enpes.physical_region_code) AS physical_region_code,
            COALESCE(enplu.physical_country_id, enpes.physical_country_id) AS physical_country_id,
            COALESCE(enplu.physical_country_iso_2, enpes.physical_country_iso_2) AS physical_country_iso_2,
            COALESCE(enplu.physical_latitude, enpes.physical_latitude) AS physical_latitude,
            COALESCE(enplu.physical_longitude, enpes.physical_longitude) AS physical_longitude,
            COALESCE(enplu.physical_altitude, enpes.physical_altitude) AS physical_altitude,
            COALESCE(enplu.postal_address_part1, enpes.postal_address_part1) AS postal_address_part1,
            COALESCE(enplu.postal_address_part2, enpes.postal_address_part2) AS postal_address_part2,
            COALESCE(enplu.postal_address_part3, enpes.postal_address_part3) AS postal_address_part3,
            COALESCE(enplu.postal_postcode, enpes.postal_postcode) AS postal_postcode,
            COALESCE(enplu.postal_postplace, enpes.postal_postplace) AS postal_postplace,
            COALESCE(enplu.postal_region_id, enpes.postal_region_id) AS postal_region_id,
            COALESCE(enplu.postal_region_path, enpes.postal_region_path) AS postal_region_path,
            COALESCE(enplu.postal_region_code, enpes.postal_region_code) AS postal_region_code,
            COALESCE(enplu.postal_country_id, enpes.postal_country_id) AS postal_country_id,
            COALESCE(enplu.postal_country_iso_2, enpes.postal_country_iso_2) AS postal_country_iso_2,
            COALESCE(enplu.postal_latitude, enpes.postal_latitude) AS postal_latitude,
            COALESCE(enplu.postal_longitude, enpes.postal_longitude) AS postal_longitude,
            COALESCE(enplu.postal_altitude, enpes.postal_altitude) AS postal_altitude,
            COALESCE(enplu.web_address, enpes.web_address) AS web_address,
            COALESCE(enplu.email_address, enpes.email_address) AS email_address,
            COALESCE(enplu.phone_number, enpes.phone_number) AS phone_number,
            COALESCE(enplu.landline, enpes.landline) AS landline,
            COALESCE(enplu.mobile_number, enpes.mobile_number) AS mobile_number,
            COALESCE(enplu.fax_number, enpes.fax_number) AS fax_number,
            COALESCE(enplu.status_id, enpes.status_id) AS status_id,
            COALESCE(enplu.status_code, enpes.status_code) AS status_code,
            COALESCE(enplu.invalid_codes || enpes.invalid_codes, enplu.invalid_codes, enpes.invalid_codes) AS invalid_codes,
            GREATEST(enplu.has_legal_unit, enpes.has_legal_unit) AS has_legal_unit,
            ten.enterprise_id,
            enplu.primary_legal_unit_id,
            enpes.primary_establishment_id
           FROM timesegments_enterprise ten
             LEFT JOIN enterprise_with_primary_legal_unit enplu ON enplu.enterprise_id = ten.enterprise_id AND ten.valid_after = enplu.valid_after AND ten.valid_to = enplu.valid_to
             LEFT JOIN enterprise_with_primary_establishment enpes ON enpes.enterprise_id = ten.enterprise_id AND ten.valid_after = enpes.valid_after AND ten.valid_to = enpes.valid_to
        ), aggregation AS (
         SELECT ten.enterprise_id,
            ten.valid_after,
            ten.valid_to,
            array_distinct_concat(COALESCE(array_cat(tlu.data_source_ids, tes.data_source_ids), tlu.data_source_ids, tes.data_source_ids)) AS data_source_ids,
            array_distinct_concat(COALESCE(array_cat(tlu.data_source_codes, tes.data_source_codes), tlu.data_source_codes, tes.data_source_codes)) AS data_source_codes,
            array_distinct_concat(COALESCE(array_cat(tlu.establishment_ids, tes.establishment_ids), tlu.establishment_ids, tes.establishment_ids)) AS establishment_ids,
            array_distinct_concat(tlu.legal_unit_ids) AS legal_unit_ids,
            COALESCE(jsonb_stats_summary_merge_agg(COALESCE(jsonb_stats_summary_merge(tlu.stats_summary, tes.stats_summary), tlu.stats_summary, tes.stats_summary)), '{}'::jsonb) AS stats_summary
           FROM timesegments_enterprise ten
             LEFT JOIN LATERAL ( SELECT timeline_legal_unit.enterprise_id,
                    ten.valid_after,
                    ten.valid_to,
                    array_distinct_concat(timeline_legal_unit.data_source_ids) AS data_source_ids,
                    array_distinct_concat(timeline_legal_unit.data_source_codes) AS data_source_codes,
                    array_agg(DISTINCT timeline_legal_unit.legal_unit_id) AS legal_unit_ids,
                    array_distinct_concat(timeline_legal_unit.establishment_ids) AS establishment_ids,
                    jsonb_stats_summary_merge_agg(timeline_legal_unit.stats_summary) AS stats_summary
                   FROM timeline_legal_unit
                  WHERE timeline_legal_unit.enterprise_id = ten.enterprise_id AND daterange(ten.valid_after, ten.valid_to, '(]'::text) && daterange(timeline_legal_unit.valid_after, timeline_legal_unit.valid_to, '(]'::text)
                  GROUP BY timeline_legal_unit.enterprise_id, ten.valid_after, ten.valid_to) tlu ON true
             LEFT JOIN LATERAL ( SELECT timeline_establishment.enterprise_id,
                    ten.valid_after,
                    ten.valid_to,
                    array_distinct_concat(timeline_establishment.data_source_ids) AS data_source_ids,
                    array_distinct_concat(timeline_establishment.data_source_codes) AS data_source_codes,
                    array_agg(DISTINCT timeline_establishment.establishment_id) AS establishment_ids,
                    jsonb_stats_to_summary_agg(timeline_establishment.stats) AS stats_summary
                   FROM timeline_establishment
                  WHERE timeline_establishment.enterprise_id = ten.enterprise_id AND daterange(ten.valid_after, ten.valid_to, '(]'::text) && daterange(timeline_establishment.valid_after, timeline_establishment.valid_to, '(]'::text)
                  GROUP BY timeline_establishment.enterprise_id, ten.valid_after, ten.valid_to) tes ON true
          GROUP BY ten.enterprise_id, ten.valid_after, ten.valid_to
        ), enterprise_with_primary_and_aggregation AS (
         SELECT basis.unit_type,
            basis.unit_id,
            basis.valid_after,
            basis.valid_to,
            basis.name,
            basis.birth_date,
            basis.death_date,
            basis.primary_activity_category_id,
            basis.primary_activity_category_path,
            basis.primary_activity_category_code,
            basis.secondary_activity_category_id,
            basis.secondary_activity_category_path,
            basis.secondary_activity_category_code,
            basis.sector_id,
            basis.sector_path,
            basis.sector_code,
            basis.sector_name,
            ( SELECT array_agg(DISTINCT ids.id) AS array_agg
                   FROM ( SELECT unnest(basis.data_source_ids) AS id
                        UNION
                         SELECT unnest(aggregation.data_source_ids) AS id) ids) AS data_source_ids,
            ( SELECT array_agg(DISTINCT codes.code) AS array_agg
                   FROM ( SELECT unnest(basis.data_source_codes) AS code
                        UNION ALL
                         SELECT unnest(aggregation.data_source_codes) AS code) codes) AS data_source_codes,
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
            basis.physical_region_code,
            basis.physical_country_id,
            basis.physical_country_iso_2,
            basis.physical_latitude,
            basis.physical_longitude,
            basis.physical_altitude,
            basis.postal_address_part1,
            basis.postal_address_part2,
            basis.postal_address_part3,
            basis.postal_postcode,
            basis.postal_postplace,
            basis.postal_region_id,
            basis.postal_region_path,
            basis.postal_region_code,
            basis.postal_country_id,
            basis.postal_country_iso_2,
            basis.postal_latitude,
            basis.postal_longitude,
            basis.postal_altitude,
            basis.web_address,
            basis.email_address,
            basis.phone_number,
            basis.landline,
            basis.mobile_number,
            basis.fax_number,
            basis.status_id,
            basis.status_code,
            basis.invalid_codes,
            basis.has_legal_unit,
            COALESCE(aggregation.establishment_ids, ARRAY[]::integer[]) AS establishment_ids,
            COALESCE(aggregation.legal_unit_ids, ARRAY[]::integer[]) AS legal_unit_ids,
            basis.enterprise_id,
            basis.primary_establishment_id,
            basis.primary_legal_unit_id,
            aggregation.stats_summary
           FROM enterprise_with_primary basis
             LEFT JOIN aggregation ON basis.enterprise_id = aggregation.enterprise_id AND basis.valid_after = aggregation.valid_after AND basis.valid_to = aggregation.valid_to
        ), enterprise_with_primary_and_aggregation_and_derived AS (
         SELECT enterprise_with_primary_and_aggregation.unit_type,
            enterprise_with_primary_and_aggregation.unit_id,
            enterprise_with_primary_and_aggregation.valid_after,
            (enterprise_with_primary_and_aggregation.valid_after + '1 day'::interval)::date AS valid_from,
            enterprise_with_primary_and_aggregation.valid_to,
            enterprise_with_primary_and_aggregation.name,
            enterprise_with_primary_and_aggregation.birth_date,
            enterprise_with_primary_and_aggregation.death_date,
            to_tsvector('simple'::regconfig, enterprise_with_primary_and_aggregation.name::text) AS search,
            enterprise_with_primary_and_aggregation.primary_activity_category_id,
            enterprise_with_primary_and_aggregation.primary_activity_category_path,
            enterprise_with_primary_and_aggregation.primary_activity_category_code,
            enterprise_with_primary_and_aggregation.secondary_activity_category_id,
            enterprise_with_primary_and_aggregation.secondary_activity_category_path,
            enterprise_with_primary_and_aggregation.secondary_activity_category_code,
            NULLIF(array_remove(ARRAY[enterprise_with_primary_and_aggregation.primary_activity_category_path, enterprise_with_primary_and_aggregation.secondary_activity_category_path], NULL::ltree), '{}'::ltree[]) AS activity_category_paths,
            enterprise_with_primary_and_aggregation.sector_id,
            enterprise_with_primary_and_aggregation.sector_path,
            enterprise_with_primary_and_aggregation.sector_code,
            enterprise_with_primary_and_aggregation.sector_name,
            enterprise_with_primary_and_aggregation.data_source_ids,
            enterprise_with_primary_and_aggregation.data_source_codes,
            enterprise_with_primary_and_aggregation.legal_form_id,
            enterprise_with_primary_and_aggregation.legal_form_code,
            enterprise_with_primary_and_aggregation.legal_form_name,
            enterprise_with_primary_and_aggregation.physical_address_part1,
            enterprise_with_primary_and_aggregation.physical_address_part2,
            enterprise_with_primary_and_aggregation.physical_address_part3,
            enterprise_with_primary_and_aggregation.physical_postcode,
            enterprise_with_primary_and_aggregation.physical_postplace,
            enterprise_with_primary_and_aggregation.physical_region_id,
            enterprise_with_primary_and_aggregation.physical_region_path,
            enterprise_with_primary_and_aggregation.physical_region_code,
            enterprise_with_primary_and_aggregation.physical_country_id,
            enterprise_with_primary_and_aggregation.physical_country_iso_2,
            enterprise_with_primary_and_aggregation.physical_latitude,
            enterprise_with_primary_and_aggregation.physical_longitude,
            enterprise_with_primary_and_aggregation.physical_altitude,
            enterprise_with_primary_and_aggregation.postal_address_part1,
            enterprise_with_primary_and_aggregation.postal_address_part2,
            enterprise_with_primary_and_aggregation.postal_address_part3,
            enterprise_with_primary_and_aggregation.postal_postcode,
            enterprise_with_primary_and_aggregation.postal_postplace,
            enterprise_with_primary_and_aggregation.postal_region_id,
            enterprise_with_primary_and_aggregation.postal_region_path,
            enterprise_with_primary_and_aggregation.postal_region_code,
            enterprise_with_primary_and_aggregation.postal_country_id,
            enterprise_with_primary_and_aggregation.postal_country_iso_2,
            enterprise_with_primary_and_aggregation.postal_latitude,
            enterprise_with_primary_and_aggregation.postal_longitude,
            enterprise_with_primary_and_aggregation.postal_altitude,
            enterprise_with_primary_and_aggregation.web_address,
            enterprise_with_primary_and_aggregation.email_address,
            enterprise_with_primary_and_aggregation.phone_number,
            enterprise_with_primary_and_aggregation.landline,
            enterprise_with_primary_and_aggregation.mobile_number,
            enterprise_with_primary_and_aggregation.fax_number,
            enterprise_with_primary_and_aggregation.status_id,
            enterprise_with_primary_and_aggregation.status_code,
            enterprise_with_primary_and_aggregation.invalid_codes,
            enterprise_with_primary_and_aggregation.has_legal_unit,
            enterprise_with_primary_and_aggregation.establishment_ids,
            enterprise_with_primary_and_aggregation.legal_unit_ids,
            enterprise_with_primary_and_aggregation.enterprise_id,
            enterprise_with_primary_and_aggregation.primary_establishment_id,
            enterprise_with_primary_and_aggregation.primary_legal_unit_id,
            enterprise_with_primary_and_aggregation.stats_summary
           FROM enterprise_with_primary_and_aggregation
        )
 SELECT enterprise_with_primary_and_aggregation_and_derived.unit_type,
    enterprise_with_primary_and_aggregation_and_derived.unit_id,
    enterprise_with_primary_and_aggregation_and_derived.valid_after,
    enterprise_with_primary_and_aggregation_and_derived.valid_from,
    enterprise_with_primary_and_aggregation_and_derived.valid_to,
    enterprise_with_primary_and_aggregation_and_derived.name,
    enterprise_with_primary_and_aggregation_and_derived.birth_date,
    enterprise_with_primary_and_aggregation_and_derived.death_date,
    enterprise_with_primary_and_aggregation_and_derived.search,
    enterprise_with_primary_and_aggregation_and_derived.primary_activity_category_id,
    enterprise_with_primary_and_aggregation_and_derived.primary_activity_category_path,
    enterprise_with_primary_and_aggregation_and_derived.primary_activity_category_code,
    enterprise_with_primary_and_aggregation_and_derived.secondary_activity_category_id,
    enterprise_with_primary_and_aggregation_and_derived.secondary_activity_category_path,
    enterprise_with_primary_and_aggregation_and_derived.secondary_activity_category_code,
    enterprise_with_primary_and_aggregation_and_derived.activity_category_paths,
    enterprise_with_primary_and_aggregation_and_derived.sector_id,
    enterprise_with_primary_and_aggregation_and_derived.sector_path,
    enterprise_with_primary_and_aggregation_and_derived.sector_code,
    enterprise_with_primary_and_aggregation_and_derived.sector_name,
    enterprise_with_primary_and_aggregation_and_derived.data_source_ids,
    enterprise_with_primary_and_aggregation_and_derived.data_source_codes,
    enterprise_with_primary_and_aggregation_and_derived.legal_form_id,
    enterprise_with_primary_and_aggregation_and_derived.legal_form_code,
    enterprise_with_primary_and_aggregation_and_derived.legal_form_name,
    enterprise_with_primary_and_aggregation_and_derived.physical_address_part1,
    enterprise_with_primary_and_aggregation_and_derived.physical_address_part2,
    enterprise_with_primary_and_aggregation_and_derived.physical_address_part3,
    enterprise_with_primary_and_aggregation_and_derived.physical_postcode,
    enterprise_with_primary_and_aggregation_and_derived.physical_postplace,
    enterprise_with_primary_and_aggregation_and_derived.physical_region_id,
    enterprise_with_primary_and_aggregation_and_derived.physical_region_path,
    enterprise_with_primary_and_aggregation_and_derived.physical_region_code,
    enterprise_with_primary_and_aggregation_and_derived.physical_country_id,
    enterprise_with_primary_and_aggregation_and_derived.physical_country_iso_2,
    enterprise_with_primary_and_aggregation_and_derived.physical_latitude,
    enterprise_with_primary_and_aggregation_and_derived.physical_longitude,
    enterprise_with_primary_and_aggregation_and_derived.physical_altitude,
    enterprise_with_primary_and_aggregation_and_derived.postal_address_part1,
    enterprise_with_primary_and_aggregation_and_derived.postal_address_part2,
    enterprise_with_primary_and_aggregation_and_derived.postal_address_part3,
    enterprise_with_primary_and_aggregation_and_derived.postal_postcode,
    enterprise_with_primary_and_aggregation_and_derived.postal_postplace,
    enterprise_with_primary_and_aggregation_and_derived.postal_region_id,
    enterprise_with_primary_and_aggregation_and_derived.postal_region_path,
    enterprise_with_primary_and_aggregation_and_derived.postal_region_code,
    enterprise_with_primary_and_aggregation_and_derived.postal_country_id,
    enterprise_with_primary_and_aggregation_and_derived.postal_country_iso_2,
    enterprise_with_primary_and_aggregation_and_derived.postal_latitude,
    enterprise_with_primary_and_aggregation_and_derived.postal_longitude,
    enterprise_with_primary_and_aggregation_and_derived.postal_altitude,
    enterprise_with_primary_and_aggregation_and_derived.web_address,
    enterprise_with_primary_and_aggregation_and_derived.email_address,
    enterprise_with_primary_and_aggregation_and_derived.phone_number,
    enterprise_with_primary_and_aggregation_and_derived.landline,
    enterprise_with_primary_and_aggregation_and_derived.mobile_number,
    enterprise_with_primary_and_aggregation_and_derived.fax_number,
    enterprise_with_primary_and_aggregation_and_derived.status_id,
    enterprise_with_primary_and_aggregation_and_derived.status_code,
    enterprise_with_primary_and_aggregation_and_derived.invalid_codes,
    enterprise_with_primary_and_aggregation_and_derived.has_legal_unit,
    enterprise_with_primary_and_aggregation_and_derived.establishment_ids,
    enterprise_with_primary_and_aggregation_and_derived.legal_unit_ids,
    enterprise_with_primary_and_aggregation_and_derived.enterprise_id,
    enterprise_with_primary_and_aggregation_and_derived.primary_establishment_id,
    enterprise_with_primary_and_aggregation_and_derived.primary_legal_unit_id,
    enterprise_with_primary_and_aggregation_and_derived.stats_summary
   FROM enterprise_with_primary_and_aggregation_and_derived
  ORDER BY enterprise_with_primary_and_aggregation_and_derived.unit_type, enterprise_with_primary_and_aggregation_and_derived.unit_id, enterprise_with_primary_and_aggregation_and_derived.valid_after;

```
