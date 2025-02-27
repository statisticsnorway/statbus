```sql
                                          View "public.timeline_legal_unit"
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
 include_unit_in_reports          | boolean                |           |          |         | plain    | 
 invalid_codes                    | jsonb                  |           |          |         | extended | 
 has_legal_unit                   | boolean                |           |          |         | plain    | 
 establishment_ids                | integer[]              |           |          |         | extended | 
 legal_unit_id                    | integer                |           |          |         | plain    | 
 enterprise_id                    | integer                |           |          |         | plain    | 
 stats                            | jsonb                  |           |          |         | extended | 
 stats_summary                    | jsonb                  |           |          |         | extended | 
View definition:
 WITH basis AS (
         SELECT t.unit_type,
            t.unit_id,
            t.valid_after,
            (t.valid_after + '1 day'::interval)::date AS valid_from,
            t.valid_to,
            lu.name,
            lu.birth_date,
            lu.death_date,
            to_tsvector('simple'::regconfig, lu.name::text) AS search,
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
            lu.status_id,
            st.code AS status_code,
            st.include_unit_in_reports,
            lu.invalid_codes,
            true AS has_legal_unit,
            lu.id AS legal_unit_id,
            lu.enterprise_id,
            COALESCE(get_jsonb_stats(NULL::integer, lu.id, t.valid_after, t.valid_to), '{}'::jsonb) AS stats
           FROM timesegments t
             JOIN legal_unit lu ON t.unit_type = 'legal_unit'::statistical_unit_type AND t.unit_id = lu.id AND daterange(t.valid_after, t.valid_to, '(]'::text) && daterange(lu.valid_after, lu.valid_to, '(]'::text)
             LEFT JOIN activity pa ON pa.legal_unit_id = lu.id AND pa.type = 'primary'::activity_type AND daterange(t.valid_after, t.valid_to, '(]'::text) && daterange(pa.valid_after, pa.valid_to, '(]'::text)
             LEFT JOIN activity_category pac ON pa.category_id = pac.id
             LEFT JOIN activity sa ON sa.legal_unit_id = lu.id AND sa.type = 'secondary'::activity_type AND daterange(t.valid_after, t.valid_to, '(]'::text) && daterange(sa.valid_after, sa.valid_to, '(]'::text)
             LEFT JOIN activity_category sac ON sa.category_id = sac.id
             LEFT JOIN sector s ON lu.sector_id = s.id
             LEFT JOIN legal_form lf ON lu.legal_form_id = lf.id
             LEFT JOIN location phl ON phl.legal_unit_id = lu.id AND phl.type = 'physical'::location_type AND daterange(t.valid_after, t.valid_to, '(]'::text) && daterange(phl.valid_after, phl.valid_to, '(]'::text)
             LEFT JOIN region phr ON phl.region_id = phr.id
             LEFT JOIN country phc ON phl.country_id = phc.id
             LEFT JOIN location pol ON pol.legal_unit_id = lu.id AND pol.type = 'postal'::location_type AND daterange(t.valid_after, t.valid_to, '(]'::text) && daterange(pol.valid_after, pol.valid_to, '(]'::text)
             LEFT JOIN region por ON pol.region_id = por.id
             LEFT JOIN country poc ON pol.country_id = poc.id
             LEFT JOIN contact c ON c.legal_unit_id = lu.id AND daterange(t.valid_after, t.valid_to, '(]'::text) && daterange(c.valid_after, c.valid_to, '(]'::text)
             LEFT JOIN status st ON lu.status_id = st.id
             LEFT JOIN LATERAL ( SELECT array_agg(DISTINCT sfu_1.data_source_id) FILTER (WHERE sfu_1.data_source_id IS NOT NULL) AS data_source_ids
                   FROM stat_for_unit sfu_1
                  WHERE sfu_1.legal_unit_id = lu.id AND daterange(t.valid_after, t.valid_to, '(]'::text) && daterange(sfu_1.valid_after, sfu_1.valid_to, '(]'::text)) sfu ON true
             LEFT JOIN LATERAL ( SELECT array_agg(ds_1.id) AS ids,
                    array_agg(ds_1.code) AS codes
                   FROM data_source ds_1
                  WHERE COALESCE(ds_1.id = lu.data_source_id, false) OR COALESCE(ds_1.id = pa.data_source_id, false) OR COALESCE(ds_1.id = sa.data_source_id, false) OR COALESCE(ds_1.id = phl.data_source_id, false) OR COALESCE(ds_1.id = pol.data_source_id, false) OR COALESCE(ds_1.id = ANY (sfu.data_source_ids), false)) ds ON true
        ), establishment_aggregation AS (
         SELECT tes.legal_unit_id,
            basis_1.valid_after,
            basis_1.valid_to,
            array_distinct_concat(tes.data_source_ids) AS data_source_ids,
            array_distinct_concat(tes.data_source_codes) AS data_source_codes,
            array_agg(DISTINCT tes.establishment_id) FILTER (WHERE tes.establishment_id IS NOT NULL) AS establishment_ids,
            jsonb_stats_to_summary_agg(tes.stats) AS stats_summary
           FROM timeline_establishment tes
             JOIN basis basis_1 ON tes.legal_unit_id = basis_1.legal_unit_id AND daterange(basis_1.valid_after, basis_1.valid_to, '(]'::text) && daterange(tes.valid_after, tes.valid_to, '(]'::text)
          WHERE tes.include_unit_in_reports = basis_1.include_unit_in_reports
          GROUP BY tes.legal_unit_id, basis_1.valid_after, basis_1.valid_to
        )
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
    basis.primary_activity_category_code,
    basis.secondary_activity_category_id,
    basis.secondary_activity_category_path,
    basis.secondary_activity_category_code,
    basis.activity_category_paths,
    basis.sector_id,
    basis.sector_path,
    basis.sector_code,
    basis.sector_name,
    ( SELECT array_agg(DISTINCT ids.id) AS array_agg
           FROM ( SELECT unnest(basis.data_source_ids) AS id
                UNION ALL
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
    basis.include_unit_in_reports,
    basis.invalid_codes,
    basis.has_legal_unit,
    COALESCE(esa.establishment_ids, ARRAY[]::integer[]) AS establishment_ids,
    basis.legal_unit_id,
    basis.enterprise_id,
    basis.stats,
    jsonb_stats_to_summary(COALESCE(esa.stats_summary, '{}'::jsonb), basis.stats) AS stats_summary
   FROM basis
     LEFT JOIN establishment_aggregation esa ON basis.legal_unit_id = esa.legal_unit_id AND basis.valid_after = esa.valid_after AND basis.valid_to = esa.valid_to
  ORDER BY basis.unit_type, basis.unit_id, basis.valid_after;

```
