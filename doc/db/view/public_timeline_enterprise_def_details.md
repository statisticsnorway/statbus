```sql
                                         View "public.timeline_enterprise_def"
              Column              |           Type           | Collation | Nullable | Default | Storage  | Description 
----------------------------------+--------------------------+-----------+----------+---------+----------+-------------
 unit_type                        | statistical_unit_type    |           |          |         | plain    | 
 unit_id                          | integer                  |           |          |         | plain    | 
 valid_from                       | date                     |           |          |         | plain    | 
 valid_to                         | date                     |           |          |         | plain    | 
 valid_until                      | date                     |           |          |         | plain    | 
 name                             | text                     |           |          |         | extended | 
 birth_date                       | date                     |           |          |         | plain    | 
 death_date                       | date                     |           |          |         | plain    | 
 search                           | tsvector                 |           |          |         | extended | 
 primary_activity_category_id     | integer                  |           |          |         | plain    | 
 primary_activity_category_path   | ltree                    |           |          |         | extended | 
 primary_activity_category_code   | character varying        |           |          |         | extended | 
 secondary_activity_category_id   | integer                  |           |          |         | plain    | 
 secondary_activity_category_path | ltree                    |           |          |         | extended | 
 secondary_activity_category_code | character varying        |           |          |         | extended | 
 activity_category_paths          | ltree[]                  |           |          |         | extended | 
 sector_id                        | integer                  |           |          |         | plain    | 
 sector_path                      | ltree                    |           |          |         | extended | 
 sector_code                      | character varying        |           |          |         | extended | 
 sector_name                      | text                     |           |          |         | extended | 
 data_source_ids                  | integer[]                |           |          |         | extended | 
 data_source_codes                | text[]                   |           |          |         | extended | 
 legal_form_id                    | integer                  |           |          |         | plain    | 
 legal_form_code                  | text                     |           |          |         | extended | 
 legal_form_name                  | text                     |           |          |         | extended | 
 physical_address_part1           | character varying(200)   |           |          |         | extended | 
 physical_address_part2           | character varying(200)   |           |          |         | extended | 
 physical_address_part3           | character varying(200)   |           |          |         | extended | 
 physical_postcode                | character varying(200)   |           |          |         | extended | 
 physical_postplace               | character varying(200)   |           |          |         | extended | 
 physical_region_id               | integer                  |           |          |         | plain    | 
 physical_region_path             | ltree                    |           |          |         | extended | 
 physical_region_code             | character varying        |           |          |         | extended | 
 physical_country_id              | integer                  |           |          |         | plain    | 
 physical_country_iso_2           | text                     |           |          |         | extended | 
 physical_latitude                | numeric(9,6)             |           |          |         | main     | 
 physical_longitude               | numeric(9,6)             |           |          |         | main     | 
 physical_altitude                | numeric(6,1)             |           |          |         | main     | 
 domestic                         | boolean                  |           |          |         | plain    | 
 postal_address_part1             | character varying(200)   |           |          |         | extended | 
 postal_address_part2             | character varying(200)   |           |          |         | extended | 
 postal_address_part3             | character varying(200)   |           |          |         | extended | 
 postal_postcode                  | character varying(200)   |           |          |         | extended | 
 postal_postplace                 | character varying(200)   |           |          |         | extended | 
 postal_region_id                 | integer                  |           |          |         | plain    | 
 postal_region_path               | ltree                    |           |          |         | extended | 
 postal_region_code               | character varying        |           |          |         | extended | 
 postal_country_id                | integer                  |           |          |         | plain    | 
 postal_country_iso_2             | text                     |           |          |         | extended | 
 postal_latitude                  | numeric(9,6)             |           |          |         | main     | 
 postal_longitude                 | numeric(9,6)             |           |          |         | main     | 
 postal_altitude                  | numeric(6,1)             |           |          |         | main     | 
 web_address                      | character varying(256)   |           |          |         | extended | 
 email_address                    | character varying(50)    |           |          |         | extended | 
 phone_number                     | character varying(50)    |           |          |         | extended | 
 landline                         | character varying(50)    |           |          |         | extended | 
 mobile_number                    | character varying(50)    |           |          |         | extended | 
 fax_number                       | character varying(50)    |           |          |         | extended | 
 unit_size_id                     | integer                  |           |          |         | plain    | 
 unit_size_code                   | text                     |           |          |         | extended | 
 status_id                        | integer                  |           |          |         | plain    | 
 status_code                      | character varying        |           |          |         | extended | 
 used_for_counting                | boolean                  |           |          |         | plain    | 
 last_edit_comment                | character varying(512)   |           |          |         | extended | 
 last_edit_by_user_id             | integer                  |           |          |         | plain    | 
 last_edit_at                     | timestamp with time zone |           |          |         | plain    | 
 invalid_codes                    | jsonb                    |           |          |         | extended | 
 has_legal_unit                   | boolean                  |           |          |         | plain    | 
 related_establishment_ids        | integer[]                |           |          |         | extended | 
 excluded_establishment_ids       | integer[]                |           |          |         | extended | 
 included_establishment_ids       | integer[]                |           |          |         | extended | 
 related_legal_unit_ids           | integer[]                |           |          |         | extended | 
 excluded_legal_unit_ids          | integer[]                |           |          |         | extended | 
 included_legal_unit_ids          | integer[]                |           |          |         | extended | 
 related_enterprise_ids           | integer[]                |           |          |         | extended | 
 excluded_enterprise_ids          | integer[]                |           |          |         | extended | 
 included_enterprise_ids          | integer[]                |           |          |         | extended | 
 enterprise_id                    | integer                  |           |          |         | plain    | 
 primary_establishment_id         | integer                  |           |          |         | plain    | 
 primary_legal_unit_id            | integer                  |           |          |         | plain    | 
 stats_summary                    | jsonb                    |           |          |         | extended | 
View definition:
 WITH aggregation AS (
         SELECT ten.enterprise_id,
            ten.valid_from,
            ten.valid_until,
            array_distinct_concat(COALESCE(array_cat(tlu.data_source_ids, tes.data_source_ids), tlu.data_source_ids, tes.data_source_ids)) AS data_source_ids,
            array_distinct_concat(COALESCE(array_cat(tlu.data_source_codes, tes.data_source_codes), tlu.data_source_codes, tes.data_source_codes)) AS data_source_codes,
            array_distinct_concat(COALESCE(array_cat(tlu.related_establishment_ids, tes.related_establishment_ids), tlu.related_establishment_ids, tes.related_establishment_ids)) AS related_establishment_ids,
            array_distinct_concat(COALESCE(array_cat(tlu.excluded_establishment_ids, tes.excluded_establishment_ids), tlu.excluded_establishment_ids, tes.excluded_establishment_ids)) AS excluded_establishment_ids,
            array_distinct_concat(COALESCE(array_cat(tlu.included_establishment_ids, tes.included_establishment_ids), tlu.included_establishment_ids, tes.included_establishment_ids)) AS included_establishment_ids,
            array_distinct_concat(tlu.related_legal_unit_ids) AS related_legal_unit_ids,
            array_distinct_concat(tlu.excluded_legal_unit_ids) AS excluded_legal_unit_ids,
            array_distinct_concat(tlu.included_legal_unit_ids) AS included_legal_unit_ids,
            COALESCE(jsonb_stats_summary_merge_agg(COALESCE(jsonb_stats_summary_merge(tlu.stats_summary, tes.stats_summary), tlu.stats_summary, tes.stats_summary)), '{}'::jsonb) AS stats_summary
           FROM ( SELECT t.unit_type,
                    t.unit_id,
                    t.valid_from,
                    t.valid_until,
                    en.id,
                    en.active,
                    en.short_name,
                    en.edit_comment,
                    en.edit_by_user_id,
                    en.edit_at,
                    en.id AS enterprise_id
                   FROM timesegments t
                     JOIN enterprise en ON t.unit_type = 'enterprise'::statistical_unit_type AND t.unit_id = en.id) ten
             LEFT JOIN LATERAL ( SELECT timeline_legal_unit.enterprise_id,
                    ten.valid_from,
                    ten.valid_until,
                    array_distinct_concat(timeline_legal_unit.data_source_ids) AS data_source_ids,
                    array_distinct_concat(timeline_legal_unit.data_source_codes) AS data_source_codes,
                    array_distinct_concat(timeline_legal_unit.related_establishment_ids) AS related_establishment_ids,
                    array_distinct_concat(timeline_legal_unit.excluded_establishment_ids) AS excluded_establishment_ids,
                    array_distinct_concat(timeline_legal_unit.included_establishment_ids) AS included_establishment_ids,
                    array_agg(DISTINCT timeline_legal_unit.legal_unit_id) AS related_legal_unit_ids,
                    array_agg(DISTINCT timeline_legal_unit.legal_unit_id) FILTER (WHERE NOT timeline_legal_unit.used_for_counting) AS excluded_legal_unit_ids,
                    array_agg(DISTINCT timeline_legal_unit.legal_unit_id) FILTER (WHERE timeline_legal_unit.used_for_counting) AS included_legal_unit_ids,
                    jsonb_stats_summary_merge_agg(timeline_legal_unit.stats_summary) FILTER (WHERE timeline_legal_unit.used_for_counting) AS stats_summary
                   FROM timeline_legal_unit
                  WHERE timeline_legal_unit.enterprise_id = ten.enterprise_id AND from_until_overlaps(ten.valid_from, ten.valid_until, timeline_legal_unit.valid_from, timeline_legal_unit.valid_until)
                  GROUP BY timeline_legal_unit.enterprise_id, ten.valid_from, ten.valid_until) tlu ON true
             LEFT JOIN LATERAL ( SELECT timeline_establishment.enterprise_id,
                    ten.valid_from,
                    ten.valid_until,
                    array_distinct_concat(timeline_establishment.data_source_ids) AS data_source_ids,
                    array_distinct_concat(timeline_establishment.data_source_codes) AS data_source_codes,
                    array_agg(DISTINCT timeline_establishment.establishment_id) AS related_establishment_ids,
                    array_agg(DISTINCT timeline_establishment.establishment_id) FILTER (WHERE NOT timeline_establishment.used_for_counting) AS excluded_establishment_ids,
                    array_agg(DISTINCT timeline_establishment.establishment_id) FILTER (WHERE timeline_establishment.used_for_counting) AS included_establishment_ids,
                    jsonb_stats_summary_merge_agg(timeline_establishment.stats_summary) FILTER (WHERE timeline_establishment.used_for_counting) AS stats_summary
                   FROM timeline_establishment
                  WHERE timeline_establishment.enterprise_id = ten.enterprise_id AND from_until_overlaps(ten.valid_from, ten.valid_until, timeline_establishment.valid_from, timeline_establishment.valid_until)
                  GROUP BY timeline_establishment.enterprise_id, ten.valid_from, ten.valid_until) tes ON true
          GROUP BY ten.enterprise_id, ten.valid_from, ten.valid_until
        ), enterprise_with_primary_and_aggregation AS (
         SELECT ( SELECT array_agg(DISTINCT ids.id) AS array_agg
                   FROM ( SELECT unnest(basis.data_source_ids) AS id
                        UNION
                         SELECT unnest(aggregation.data_source_ids) AS id) ids) AS data_source_ids,
            ( SELECT array_agg(DISTINCT codes.code) AS array_agg
                   FROM ( SELECT unnest(basis.data_source_codes) AS code
                        UNION ALL
                         SELECT unnest(aggregation.data_source_codes) AS code) codes) AS data_source_codes,
            basis.unit_type,
            basis.unit_id,
            basis.valid_from,
            basis.valid_until,
            basis.enterprise_id,
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
            basis.domestic,
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
            basis.unit_size_id,
            basis.unit_size_code,
            basis.status_id,
            basis.status_code,
            basis.used_for_counting,
            basis.last_edit_comment,
            basis.last_edit_by_user_id,
            basis.last_edit_at,
            basis.invalid_codes,
            basis.has_legal_unit,
            basis.primary_legal_unit_id,
            basis.primary_establishment_id,
            aggregation.related_establishment_ids,
            aggregation.excluded_establishment_ids,
            aggregation.included_establishment_ids,
            aggregation.related_legal_unit_ids,
            aggregation.excluded_legal_unit_ids,
            aggregation.included_legal_unit_ids,
            aggregation.stats_summary
           FROM ( SELECT ten.unit_type,
                    ten.unit_id,
                    ten.valid_from,
                    ten.valid_until,
                    ten.enterprise_id,
                    COALESCE(NULLIF(ten.short_name::text, ''::text), enplu.name::text, enpes.name::text) AS name,
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
                    COALESCE(enplu.domestic, enpes.domestic) AS domestic,
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
                    COALESCE(enplu.unit_size_id, enpes.unit_size_id) AS unit_size_id,
                    COALESCE(enplu.unit_size_code, enpes.unit_size_code) AS unit_size_code,
                    COALESCE(enplu.status_id, enpes.status_id) AS status_id,
                    COALESCE(enplu.status_code, enpes.status_code) AS status_code,
                    COALESCE(enplu.used_for_counting, enpes.used_for_counting) AS used_for_counting,
                    last_edit.edit_comment AS last_edit_comment,
                    last_edit.edit_by_user_id AS last_edit_by_user_id,
                    last_edit.edit_at AS last_edit_at,
                    COALESCE(enplu.invalid_codes || enpes.invalid_codes, enplu.invalid_codes, enpes.invalid_codes) AS invalid_codes,
                    GREATEST(enplu.has_legal_unit, enpes.has_legal_unit) AS has_legal_unit,
                    enplu.legal_unit_id AS primary_legal_unit_id,
                    enpes.establishment_id AS primary_establishment_id
                   FROM ( SELECT t.unit_type,
                            t.unit_id,
                            t.valid_from,
                            t.valid_until,
                            en.id,
                            en.active,
                            en.short_name,
                            en.edit_comment,
                            en.edit_by_user_id,
                            en.edit_at,
                            en.id AS enterprise_id
                           FROM timesegments t
                             JOIN enterprise en ON t.unit_type = 'enterprise'::statistical_unit_type AND t.unit_id = en.id) ten
                     LEFT JOIN LATERAL ( SELECT enplu_1.unit_type,
                            enplu_1.unit_id,
                            enplu_1.valid_from,
                            enplu_1.valid_to,
                            enplu_1.valid_until,
                            enplu_1.name,
                            enplu_1.birth_date,
                            enplu_1.death_date,
                            enplu_1.search,
                            enplu_1.primary_activity_category_id,
                            enplu_1.primary_activity_category_path,
                            enplu_1.primary_activity_category_code,
                            enplu_1.secondary_activity_category_id,
                            enplu_1.secondary_activity_category_path,
                            enplu_1.secondary_activity_category_code,
                            enplu_1.activity_category_paths,
                            enplu_1.sector_id,
                            enplu_1.sector_path,
                            enplu_1.sector_code,
                            enplu_1.sector_name,
                            enplu_1.data_source_ids,
                            enplu_1.data_source_codes,
                            enplu_1.legal_form_id,
                            enplu_1.legal_form_code,
                            enplu_1.legal_form_name,
                            enplu_1.physical_address_part1,
                            enplu_1.physical_address_part2,
                            enplu_1.physical_address_part3,
                            enplu_1.physical_postcode,
                            enplu_1.physical_postplace,
                            enplu_1.physical_region_id,
                            enplu_1.physical_region_path,
                            enplu_1.physical_region_code,
                            enplu_1.physical_country_id,
                            enplu_1.physical_country_iso_2,
                            enplu_1.physical_latitude,
                            enplu_1.physical_longitude,
                            enplu_1.physical_altitude,
                            enplu_1.domestic,
                            enplu_1.postal_address_part1,
                            enplu_1.postal_address_part2,
                            enplu_1.postal_address_part3,
                            enplu_1.postal_postcode,
                            enplu_1.postal_postplace,
                            enplu_1.postal_region_id,
                            enplu_1.postal_region_path,
                            enplu_1.postal_region_code,
                            enplu_1.postal_country_id,
                            enplu_1.postal_country_iso_2,
                            enplu_1.postal_latitude,
                            enplu_1.postal_longitude,
                            enplu_1.postal_altitude,
                            enplu_1.web_address,
                            enplu_1.email_address,
                            enplu_1.phone_number,
                            enplu_1.landline,
                            enplu_1.mobile_number,
                            enplu_1.fax_number,
                            enplu_1.unit_size_id,
                            enplu_1.unit_size_code,
                            enplu_1.status_id,
                            enplu_1.status_code,
                            enplu_1.used_for_counting,
                            enplu_1.last_edit_comment,
                            enplu_1.last_edit_by_user_id,
                            enplu_1.last_edit_at,
                            enplu_1.invalid_codes,
                            enplu_1.has_legal_unit,
                            enplu_1.related_establishment_ids,
                            enplu_1.excluded_establishment_ids,
                            enplu_1.included_establishment_ids,
                            enplu_1.related_legal_unit_ids,
                            enplu_1.excluded_legal_unit_ids,
                            enplu_1.included_legal_unit_ids,
                            enplu_1.related_enterprise_ids,
                            enplu_1.excluded_enterprise_ids,
                            enplu_1.included_enterprise_ids,
                            enplu_1.legal_unit_id,
                            enplu_1.enterprise_id,
                            enplu_1.primary_for_enterprise,
                            enplu_1.stats,
                            enplu_1.stats_summary
                           FROM timeline_legal_unit enplu_1
                          WHERE enplu_1.enterprise_id = ten.enterprise_id AND enplu_1.primary_for_enterprise = true AND from_until_overlaps(ten.valid_from, ten.valid_until, enplu_1.valid_from, enplu_1.valid_until)
                          ORDER BY enplu_1.valid_from DESC, enplu_1.legal_unit_id DESC
                         LIMIT 1) enplu ON true
                     LEFT JOIN LATERAL ( SELECT enpes_1.unit_type,
                            enpes_1.unit_id,
                            enpes_1.valid_from,
                            enpes_1.valid_to,
                            enpes_1.valid_until,
                            enpes_1.name,
                            enpes_1.birth_date,
                            enpes_1.death_date,
                            enpes_1.search,
                            enpes_1.primary_activity_category_id,
                            enpes_1.primary_activity_category_path,
                            enpes_1.primary_activity_category_code,
                            enpes_1.secondary_activity_category_id,
                            enpes_1.secondary_activity_category_path,
                            enpes_1.secondary_activity_category_code,
                            enpes_1.activity_category_paths,
                            enpes_1.sector_id,
                            enpes_1.sector_path,
                            enpes_1.sector_code,
                            enpes_1.sector_name,
                            enpes_1.data_source_ids,
                            enpes_1.data_source_codes,
                            enpes_1.legal_form_id,
                            enpes_1.legal_form_code,
                            enpes_1.legal_form_name,
                            enpes_1.physical_address_part1,
                            enpes_1.physical_address_part2,
                            enpes_1.physical_address_part3,
                            enpes_1.physical_postcode,
                            enpes_1.physical_postplace,
                            enpes_1.physical_region_id,
                            enpes_1.physical_region_path,
                            enpes_1.physical_region_code,
                            enpes_1.physical_country_id,
                            enpes_1.physical_country_iso_2,
                            enpes_1.physical_latitude,
                            enpes_1.physical_longitude,
                            enpes_1.physical_altitude,
                            enpes_1.domestic,
                            enpes_1.postal_address_part1,
                            enpes_1.postal_address_part2,
                            enpes_1.postal_address_part3,
                            enpes_1.postal_postcode,
                            enpes_1.postal_postplace,
                            enpes_1.postal_region_id,
                            enpes_1.postal_region_path,
                            enpes_1.postal_region_code,
                            enpes_1.postal_country_id,
                            enpes_1.postal_country_iso_2,
                            enpes_1.postal_latitude,
                            enpes_1.postal_longitude,
                            enpes_1.postal_altitude,
                            enpes_1.web_address,
                            enpes_1.email_address,
                            enpes_1.phone_number,
                            enpes_1.landline,
                            enpes_1.mobile_number,
                            enpes_1.fax_number,
                            enpes_1.unit_size_id,
                            enpes_1.unit_size_code,
                            enpes_1.status_id,
                            enpes_1.status_code,
                            enpes_1.used_for_counting,
                            enpes_1.last_edit_comment,
                            enpes_1.last_edit_by_user_id,
                            enpes_1.last_edit_at,
                            enpes_1.invalid_codes,
                            enpes_1.has_legal_unit,
                            enpes_1.establishment_id,
                            enpes_1.legal_unit_id,
                            enpes_1.enterprise_id,
                            enpes_1.primary_for_enterprise,
                            enpes_1.primary_for_legal_unit,
                            enpes_1.stats,
                            enpes_1.stats_summary,
                            enpes_1.related_establishment_ids,
                            enpes_1.excluded_establishment_ids,
                            enpes_1.included_establishment_ids,
                            enpes_1.related_legal_unit_ids,
                            enpes_1.excluded_legal_unit_ids,
                            enpes_1.included_legal_unit_ids,
                            enpes_1.related_enterprise_ids,
                            enpes_1.excluded_enterprise_ids,
                            enpes_1.included_enterprise_ids
                           FROM timeline_establishment enpes_1
                          WHERE enpes_1.enterprise_id = ten.enterprise_id AND enpes_1.primary_for_enterprise = true AND from_until_overlaps(ten.valid_from, ten.valid_until, enpes_1.valid_from, enpes_1.valid_until)
                          ORDER BY enpes_1.valid_from DESC, enpes_1.establishment_id DESC
                         LIMIT 1) enpes ON true
                     LEFT JOIN LATERAL ( SELECT all_edits.edit_comment,
                            all_edits.edit_by_user_id,
                            all_edits.edit_at
                           FROM ( VALUES (ten.edit_comment,ten.edit_by_user_id,ten.edit_at), (enplu.last_edit_comment,enplu.last_edit_by_user_id,enplu.last_edit_at), (enpes.last_edit_comment,enpes.last_edit_by_user_id,enpes.last_edit_at)) all_edits(edit_comment, edit_by_user_id, edit_at)
                          WHERE all_edits.edit_at IS NOT NULL
                          ORDER BY all_edits.edit_at DESC
                         LIMIT 1) last_edit ON true) basis
             LEFT JOIN aggregation ON basis.enterprise_id = aggregation.enterprise_id AND basis.valid_from = aggregation.valid_from AND basis.valid_until = aggregation.valid_until
        )
 SELECT unit_type,
    unit_id,
    valid_from,
    (valid_until - '1 day'::interval)::date AS valid_to,
    valid_until,
    name,
    birth_date,
    death_date,
    to_tsvector('simple'::regconfig, name) AS search,
    primary_activity_category_id,
    primary_activity_category_path,
    primary_activity_category_code,
    secondary_activity_category_id,
    secondary_activity_category_path,
    secondary_activity_category_code,
    NULLIF(array_remove(ARRAY[primary_activity_category_path, secondary_activity_category_path], NULL::ltree), '{}'::ltree[]) AS activity_category_paths,
    sector_id,
    sector_path,
    sector_code,
    sector_name,
    data_source_ids,
    data_source_codes,
    legal_form_id,
    legal_form_code,
    legal_form_name,
    physical_address_part1,
    physical_address_part2,
    physical_address_part3,
    physical_postcode,
    physical_postplace,
    physical_region_id,
    physical_region_path,
    physical_region_code,
    physical_country_id,
    physical_country_iso_2,
    physical_latitude,
    physical_longitude,
    physical_altitude,
    domestic,
    postal_address_part1,
    postal_address_part2,
    postal_address_part3,
    postal_postcode,
    postal_postplace,
    postal_region_id,
    postal_region_path,
    postal_region_code,
    postal_country_id,
    postal_country_iso_2,
    postal_latitude,
    postal_longitude,
    postal_altitude,
    web_address,
    email_address,
    phone_number,
    landline,
    mobile_number,
    fax_number,
    unit_size_id,
    unit_size_code,
    status_id,
    status_code,
    used_for_counting,
    last_edit_comment,
    last_edit_by_user_id,
    last_edit_at,
    invalid_codes,
    has_legal_unit,
    related_establishment_ids,
    excluded_establishment_ids,
    included_establishment_ids,
    related_legal_unit_ids,
    excluded_legal_unit_ids,
    included_legal_unit_ids,
    ARRAY[unit_id] AS related_enterprise_ids,
    ARRAY[]::integer[] AS excluded_enterprise_ids,
        CASE
            WHEN used_for_counting THEN ARRAY[unit_id]
            ELSE '{}'::integer[]
        END AS included_enterprise_ids,
    enterprise_id,
    primary_establishment_id,
    primary_legal_unit_id,
    stats_summary
   FROM enterprise_with_primary_and_aggregation
  ORDER BY unit_type, unit_id, valid_from;

```
