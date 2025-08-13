```sql
                                         View "public.timeline_enterprise_def"
              Column              |           Type           | Collation | Nullable | Default | Storage  | Description 
----------------------------------+--------------------------+-----------+----------+---------+----------+-------------
 unit_type                        | statistical_unit_type    |           |          |         | plain    | 
 unit_id                          | integer                  |           |          |         | plain    | 
 valid_after                      | date                     |           |          |         | plain    | 
 valid_from                       | date                     |           |          |         | plain    | 
 valid_to                         | date                     |           |          |         | plain    | 
 name                             | character varying(256)   |           |          |         | extended | 
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
 include_unit_in_reports          | boolean                  |           |          |         | plain    | 
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
 enterprise_id                    | integer                  |           |          |         | plain    | 
 primary_establishment_id         | integer                  |           |          |         | plain    | 
 primary_legal_unit_id            | integer                  |           |          |         | plain    | 
 stats_summary                    | jsonb                    |           |          |         | extended | 
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
            tlu.name,
            tlu.birth_date,
            tlu.death_date,
            tlu.search,
            tlu.primary_activity_category_id,
            tlu.primary_activity_category_path,
            tlu.primary_activity_category_code,
            tlu.secondary_activity_category_id,
            tlu.secondary_activity_category_path,
            tlu.secondary_activity_category_code,
            tlu.activity_category_paths,
            tlu.sector_id,
            tlu.sector_path,
            tlu.sector_code,
            tlu.sector_name,
            tlu.data_source_ids,
            tlu.data_source_codes,
            tlu.legal_form_id,
            tlu.legal_form_code,
            tlu.legal_form_name,
            tlu.physical_address_part1,
            tlu.physical_address_part2,
            tlu.physical_address_part3,
            tlu.physical_postcode,
            tlu.physical_postplace,
            tlu.physical_region_id,
            tlu.physical_region_path,
            tlu.physical_region_code,
            tlu.physical_country_id,
            tlu.physical_country_iso_2,
            tlu.physical_latitude,
            tlu.physical_longitude,
            tlu.physical_altitude,
            tlu.postal_address_part1,
            tlu.postal_address_part2,
            tlu.postal_address_part3,
            tlu.postal_postcode,
            tlu.postal_postplace,
            tlu.postal_region_id,
            tlu.postal_region_path,
            tlu.postal_region_code,
            tlu.postal_country_id,
            tlu.postal_country_iso_2,
            tlu.postal_latitude,
            tlu.postal_longitude,
            tlu.postal_altitude,
            tlu.web_address,
            tlu.email_address,
            tlu.phone_number,
            tlu.landline,
            tlu.mobile_number,
            tlu.fax_number,
            tlu.unit_size_id,
            tlu.unit_size_code,
            tlu.status_id,
            tlu.status_code,
            tlu.include_unit_in_reports,
            last_edit.edit_comment AS last_edit_comment,
            last_edit.edit_by_user_id AS last_edit_by_user_id,
            last_edit.edit_at AS last_edit_at,
            tlu.invalid_codes,
            tlu.has_legal_unit,
            ten.enterprise_id,
            tlu.legal_unit_id AS primary_legal_unit_id
           FROM timesegments_enterprise ten
             JOIN timeline_legal_unit tlu ON tlu.enterprise_id = ten.enterprise_id AND tlu.primary_for_enterprise = true AND public.after_to_overlaps(ten.valid_after, ten.valid_to, tlu.valid_after, tlu.valid_to)
             LEFT JOIN LATERAL ( SELECT all_edits.edit_comment,
                    all_edits.edit_by_user_id,
                    all_edits.edit_at
                   FROM ( VALUES (ten.edit_comment,ten.edit_by_user_id,ten.edit_at), (tlu.last_edit_comment,tlu.last_edit_by_user_id,tlu.last_edit_at)) all_edits(edit_comment, edit_by_user_id, edit_at)
                  WHERE all_edits.edit_at IS NOT NULL
                  ORDER BY all_edits.edit_at DESC
                 LIMIT 1) last_edit ON true
        ), enterprise_with_primary_establishment AS (
         SELECT ten.unit_type,
            ten.unit_id,
            ten.valid_after,
            ten.valid_to,
            tes.name,
            tes.birth_date,
            tes.death_date,
            tes.search,
            tes.primary_activity_category_id,
            tes.primary_activity_category_path,
            tes.primary_activity_category_code,
            tes.secondary_activity_category_id,
            tes.secondary_activity_category_path,
            tes.secondary_activity_category_code,
            tes.activity_category_paths,
            tes.sector_id,
            tes.sector_path,
            tes.sector_code,
            tes.sector_name,
            tes.data_source_ids,
            tes.data_source_codes,
            tes.legal_form_id,
            tes.legal_form_code,
            tes.legal_form_name,
            tes.physical_address_part1,
            tes.physical_address_part2,
            tes.physical_address_part3,
            tes.physical_postcode,
            tes.physical_postplace,
            tes.physical_region_id,
            tes.physical_region_path,
            tes.physical_region_code,
            tes.physical_country_id,
            tes.physical_country_iso_2,
            tes.physical_latitude,
            tes.physical_longitude,
            tes.physical_altitude,
            tes.postal_address_part1,
            tes.postal_address_part2,
            tes.postal_address_part3,
            tes.postal_postcode,
            tes.postal_postplace,
            tes.postal_region_id,
            tes.postal_region_path,
            tes.postal_region_code,
            tes.postal_country_id,
            tes.postal_country_iso_2,
            tes.postal_latitude,
            tes.postal_longitude,
            tes.postal_altitude,
            tes.web_address,
            tes.email_address,
            tes.phone_number,
            tes.landline,
            tes.mobile_number,
            tes.fax_number,
            tes.unit_size_id,
            tes.unit_size_code,
            tes.status_id,
            tes.status_code,
            tes.include_unit_in_reports,
            last_edit.edit_comment AS last_edit_comment,
            last_edit.edit_by_user_id AS last_edit_by_user_id,
            last_edit.edit_at AS last_edit_at,
            tes.invalid_codes,
            tes.has_legal_unit,
            ten.enterprise_id,
            tes.establishment_id AS primary_establishment_id
           FROM timesegments_enterprise ten
             JOIN timeline_establishment tes ON tes.enterprise_id = ten.enterprise_id AND tes.primary_for_enterprise = true AND public.after_to_overlaps(ten.valid_after, ten.valid_to, tes.valid_after, tes.valid_to)
             LEFT JOIN LATERAL ( SELECT all_edits.edit_comment,
                    all_edits.edit_by_user_id,
                    all_edits.edit_at
                   FROM ( VALUES (ten.edit_comment,ten.edit_by_user_id,ten.edit_at), (tes.last_edit_comment,tes.last_edit_by_user_id,tes.last_edit_at)) all_edits(edit_comment, edit_by_user_id, edit_at)
                  WHERE all_edits.edit_at IS NOT NULL
                  ORDER BY all_edits.edit_at DESC
                 LIMIT 1) last_edit ON true
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
            COALESCE(enplu.unit_size_id, enpes.unit_size_id) AS unit_size_id,
            COALESCE(enplu.unit_size_code, enpes.unit_size_code) AS unit_size_code,
            COALESCE(enplu.status_id, enpes.status_id) AS status_id,
            COALESCE(enplu.status_code, enpes.status_code) AS status_code,
            COALESCE(enplu.include_unit_in_reports, enpes.include_unit_in_reports) AS include_unit_in_reports,
            last_edit.edit_comment AS last_edit_comment,
            last_edit.edit_by_user_id AS last_edit_by_user_id,
            last_edit.edit_at AS last_edit_at,
            COALESCE(enplu.invalid_codes || enpes.invalid_codes, enplu.invalid_codes, enpes.invalid_codes) AS invalid_codes,
            GREATEST(enplu.has_legal_unit, enpes.has_legal_unit) AS has_legal_unit,
            ten.enterprise_id,
            enplu.primary_legal_unit_id,
            enpes.primary_establishment_id
           FROM timesegments_enterprise ten
             LEFT JOIN enterprise_with_primary_legal_unit enplu ON enplu.enterprise_id = ten.enterprise_id AND ten.valid_after = enplu.valid_after AND ten.valid_to = enplu.valid_to
             LEFT JOIN enterprise_with_primary_establishment enpes ON enpes.enterprise_id = ten.enterprise_id AND ten.valid_after = enpes.valid_after AND ten.valid_to = enpes.valid_to
             LEFT JOIN LATERAL ( SELECT all_edits.edit_comment,
                    all_edits.edit_by_user_id,
                    all_edits.edit_at
                   FROM ( VALUES (ten.edit_comment,ten.edit_by_user_id,ten.edit_at), (enplu.last_edit_comment,enplu.last_edit_by_user_id,enplu.last_edit_at), (enpes.last_edit_comment,enpes.last_edit_by_user_id,enpes.last_edit_at)) all_edits(edit_comment, edit_by_user_id, edit_at)
                  WHERE all_edits.edit_at IS NOT NULL
                  ORDER BY all_edits.edit_at DESC
                 LIMIT 1) last_edit ON true
        ), aggregation AS (
         SELECT ten.enterprise_id,
            ten.valid_after,
            ten.valid_to,
            array_distinct_concat(COALESCE(array_cat(tlu.data_source_ids, tes.data_source_ids), tlu.data_source_ids, tes.data_source_ids)) AS data_source_ids,
            array_distinct_concat(COALESCE(array_cat(tlu.data_source_codes, tes.data_source_codes), tlu.data_source_codes, tes.data_source_codes)) AS data_source_codes,
            array_distinct_concat(COALESCE(array_cat(tlu.related_establishment_ids, tes.related_establishment_ids), tlu.related_establishment_ids, tes.related_establishment_ids)) AS related_establishment_ids,
            array_distinct_concat(COALESCE(array_cat(tlu.excluded_establishment_ids, tes.excluded_establishment_ids), tlu.excluded_establishment_ids, tes.excluded_establishment_ids)) AS excluded_establishment_ids,
            array_distinct_concat(COALESCE(array_cat(tlu.included_establishment_ids, tes.included_establishment_ids), tlu.included_establishment_ids, tes.included_establishment_ids)) AS included_establishment_ids,
            array_distinct_concat(tlu.related_legal_unit_ids) AS related_legal_unit_ids,
            array_distinct_concat(tlu.excluded_legal_unit_ids) AS excluded_legal_unit_ids,
            array_distinct_concat(tlu.included_legal_unit_ids) AS included_legal_unit_ids,
            COALESCE(jsonb_stats_summary_merge_agg(COALESCE(jsonb_stats_summary_merge(tlu.stats_summary, tes.stats_summary), tlu.stats_summary, tes.stats_summary)), '{}'::jsonb) AS stats_summary
           FROM timesegments_enterprise ten
             LEFT JOIN LATERAL ( SELECT timeline_legal_unit.enterprise_id,
                    ten.valid_after,
                    ten.valid_to,
                    array_distinct_concat(timeline_legal_unit.data_source_ids) AS data_source_ids,
                    array_distinct_concat(timeline_legal_unit.data_source_codes) AS data_source_codes,
                    array_distinct_concat(timeline_legal_unit.related_establishment_ids) AS related_establishment_ids,
                    array_distinct_concat(timeline_legal_unit.excluded_establishment_ids) AS excluded_establishment_ids,
                    array_distinct_concat(timeline_legal_unit.included_establishment_ids) AS included_establishment_ids,
                    array_agg(DISTINCT timeline_legal_unit.legal_unit_id) AS related_legal_unit_ids,
                    array_agg(DISTINCT timeline_legal_unit.legal_unit_id) FILTER (WHERE NOT timeline_legal_unit.include_unit_in_reports) AS excluded_legal_unit_ids,
                    array_agg(DISTINCT timeline_legal_unit.legal_unit_id) FILTER (WHERE timeline_legal_unit.include_unit_in_reports) AS included_legal_unit_ids,
                    jsonb_stats_summary_merge_agg(timeline_legal_unit.stats_summary) FILTER (WHERE timeline_legal_unit.include_unit_in_reports) AS stats_summary
                   FROM timeline_legal_unit
                  WHERE timeline_legal_unit.enterprise_id = ten.enterprise_id AND public.after_to_overlaps(ten.valid_after, ten.valid_to, timeline_legal_unit.valid_after, timeline_legal_unit.valid_to)
                  GROUP BY timeline_legal_unit.enterprise_id, ten.valid_after, ten.valid_to) tlu ON true
             LEFT JOIN LATERAL ( SELECT timeline_establishment.enterprise_id,
                    ten.valid_after,
                    ten.valid_to,
                    array_distinct_concat(timeline_establishment.data_source_ids) AS data_source_ids,
                    array_distinct_concat(timeline_establishment.data_source_codes) AS data_source_codes,
                    array_agg(DISTINCT timeline_establishment.establishment_id) AS related_establishment_ids,
                    array_agg(DISTINCT timeline_establishment.establishment_id) FILTER (WHERE NOT timeline_establishment.include_unit_in_reports) AS excluded_establishment_ids,
                    array_agg(DISTINCT timeline_establishment.establishment_id) FILTER (WHERE timeline_establishment.include_unit_in_reports) AS included_establishment_ids,
                    jsonb_stats_to_summary_agg(timeline_establishment.stats) FILTER (WHERE timeline_establishment.include_unit_in_reports) AS stats_summary
                   FROM timeline_establishment
                  WHERE timeline_establishment.enterprise_id = ten.enterprise_id AND public.after_to_overlaps(ten.valid_after, ten.valid_to, timeline_establishment.valid_after, timeline_establishment.valid_to)
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
            basis.unit_size_id,
            basis.unit_size_code,
            basis.status_id,
            basis.status_code,
            basis.include_unit_in_reports,
            basis.last_edit_comment,
            basis.last_edit_by_user_id,
            basis.last_edit_at,
            basis.invalid_codes,
            basis.has_legal_unit,
            COALESCE(aggregation.related_establishment_ids, ARRAY[]::integer[]) AS related_establishment_ids,
            COALESCE(aggregation.excluded_establishment_ids, ARRAY[]::integer[]) AS excluded_establishment_ids,
            COALESCE(aggregation.included_establishment_ids, ARRAY[]::integer[]) AS included_establishment_ids,
            COALESCE(aggregation.related_legal_unit_ids, ARRAY[]::integer[]) AS related_legal_unit_ids,
            COALESCE(aggregation.excluded_legal_unit_ids, ARRAY[]::integer[]) AS excluded_legal_unit_ids,
            COALESCE(aggregation.included_legal_unit_ids, ARRAY[]::integer[]) AS included_legal_unit_ids,
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
            enterprise_with_primary_and_aggregation.unit_size_id,
            enterprise_with_primary_and_aggregation.unit_size_code,
            enterprise_with_primary_and_aggregation.status_id,
            enterprise_with_primary_and_aggregation.status_code,
            enterprise_with_primary_and_aggregation.include_unit_in_reports,
            enterprise_with_primary_and_aggregation.last_edit_comment,
            enterprise_with_primary_and_aggregation.last_edit_by_user_id,
            enterprise_with_primary_and_aggregation.last_edit_at,
            enterprise_with_primary_and_aggregation.invalid_codes,
            enterprise_with_primary_and_aggregation.has_legal_unit,
            enterprise_with_primary_and_aggregation.related_establishment_ids,
            enterprise_with_primary_and_aggregation.excluded_establishment_ids,
            enterprise_with_primary_and_aggregation.included_establishment_ids,
            enterprise_with_primary_and_aggregation.related_legal_unit_ids,
            enterprise_with_primary_and_aggregation.excluded_legal_unit_ids,
            enterprise_with_primary_and_aggregation.included_legal_unit_ids,
            enterprise_with_primary_and_aggregation.enterprise_id,
            enterprise_with_primary_and_aggregation.primary_establishment_id,
            enterprise_with_primary_and_aggregation.primary_legal_unit_id,
            enterprise_with_primary_and_aggregation.stats_summary
           FROM enterprise_with_primary_and_aggregation
        )
 SELECT unit_type,
    unit_id,
    valid_after,
    valid_from,
    valid_to,
    name,
    birth_date,
    death_date,
    search,
    primary_activity_category_id,
    primary_activity_category_path,
    primary_activity_category_code,
    secondary_activity_category_id,
    secondary_activity_category_path,
    secondary_activity_category_code,
    activity_category_paths,
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
    include_unit_in_reports,
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
    enterprise_id,
    primary_establishment_id,
    primary_legal_unit_id,
    stats_summary
   FROM enterprise_with_primary_and_aggregation_and_derived
  ORDER BY unit_type, unit_id, valid_after;

```
