```sql
                                       View "public.timeline_establishment_def"
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
 establishment_id                 | integer                  |           |          |         | plain    | 
 legal_unit_id                    | integer                  |           |          |         | plain    | 
 enterprise_id                    | integer                  |           |          |         | plain    | 
 primary_for_enterprise           | boolean                  |           |          |         | plain    | 
 primary_for_legal_unit           | boolean                  |           |          |         | plain    | 
 stats                            | jsonb                    |           |          |         | extended | 
View definition:
 SELECT t.unit_type,
    t.unit_id,
    t.valid_after,
    (t.valid_after + '1 day'::interval)::date AS valid_from,
    t.valid_to,
    es.name,
    es.birth_date,
    es.death_date,
    to_tsvector('simple'::regconfig, es.name::text) AS search,
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
    NULL::text AS legal_form_code,
    NULL::text AS legal_form_name,
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
    es.unit_size_id,
    us.code AS unit_size_code,
    es.status_id,
    st.code AS status_code,
    st.include_unit_in_reports,
    last_edit.edit_comment AS last_edit_comment,
    last_edit.edit_by_user_id AS last_edit_by_user_id,
    last_edit.edit_at AS last_edit_at,
    es.invalid_codes,
    es.legal_unit_id IS NOT NULL AS has_legal_unit,
    es.id AS establishment_id,
    es.legal_unit_id,
    es.enterprise_id,
    es.primary_for_enterprise,
    es.primary_for_legal_unit,
    COALESCE(get_jsonb_stats(es.id, NULL::integer, t.valid_after, t.valid_to), '{}'::jsonb) AS stats
   FROM timesegments t
     JOIN establishment es ON t.unit_type = 'establishment'::statistical_unit_type AND t.unit_id = es.id AND after_to_overlaps(t.valid_after, t.valid_to, es.valid_after, es.valid_to)
     LEFT JOIN activity pa ON pa.establishment_id = es.id AND pa.type = 'primary'::activity_type AND after_to_overlaps(t.valid_after, t.valid_to, pa.valid_after, pa.valid_to)
     LEFT JOIN activity_category pac ON pa.category_id = pac.id
     LEFT JOIN activity sa ON sa.establishment_id = es.id AND sa.type = 'secondary'::activity_type AND after_to_overlaps(t.valid_after, t.valid_to, sa.valid_after, sa.valid_to)
     LEFT JOIN activity_category sac ON sa.category_id = sac.id
     LEFT JOIN sector s ON es.sector_id = s.id
     LEFT JOIN location phl ON phl.establishment_id = es.id AND phl.type = 'physical'::location_type AND after_to_overlaps(t.valid_after, t.valid_to, phl.valid_after, phl.valid_to)
     LEFT JOIN region phr ON phl.region_id = phr.id
     LEFT JOIN country phc ON phl.country_id = phc.id
     LEFT JOIN location pol ON pol.establishment_id = es.id AND pol.type = 'postal'::location_type AND after_to_overlaps(t.valid_after, t.valid_to, pol.valid_after, pol.valid_to)
     LEFT JOIN region por ON pol.region_id = por.id
     LEFT JOIN country poc ON pol.country_id = poc.id
     LEFT JOIN contact c ON c.establishment_id = es.id AND after_to_overlaps(t.valid_after, t.valid_to, c.valid_after, c.valid_to)
     LEFT JOIN unit_size us ON es.unit_size_id = us.id
     LEFT JOIN status st ON es.status_id = st.id
     LEFT JOIN LATERAL ( SELECT array_agg(DISTINCT sfu_1.data_source_id) FILTER (WHERE sfu_1.data_source_id IS NOT NULL) AS data_source_ids
           FROM stat_for_unit sfu_1
          WHERE sfu_1.establishment_id = es.id AND after_to_overlaps(t.valid_after, t.valid_to, sfu_1.valid_after, sfu_1.valid_to)) sfu ON true
     LEFT JOIN LATERAL ( SELECT array_agg(ds_1.id) AS ids,
            array_agg(ds_1.code) AS codes
           FROM data_source ds_1
          WHERE COALESCE(ds_1.id = es.data_source_id, false) OR COALESCE(ds_1.id = pa.data_source_id, false) OR COALESCE(ds_1.id = sa.data_source_id, false) OR COALESCE(ds_1.id = phl.data_source_id, false) OR COALESCE(ds_1.id = pol.data_source_id, false) OR COALESCE(ds_1.id = ANY (sfu.data_source_ids), false)) ds ON true
     LEFT JOIN LATERAL ( SELECT all_edits.edit_comment,
            all_edits.edit_by_user_id,
            all_edits.edit_at
           FROM ( VALUES (es.edit_comment,es.edit_by_user_id,es.edit_at), (pa.edit_comment,pa.edit_by_user_id,pa.edit_at), (sa.edit_comment,sa.edit_by_user_id,sa.edit_at), (phl.edit_comment,phl.edit_by_user_id,phl.edit_at), (pol.edit_comment,pol.edit_by_user_id,pol.edit_at), (c.edit_comment,c.edit_by_user_id,c.edit_at)) all_edits(edit_comment, edit_by_user_id, edit_at)
          WHERE all_edits.edit_at IS NOT NULL
          ORDER BY all_edits.edit_at DESC
         LIMIT 1) last_edit ON true
  ORDER BY t.unit_type, t.unit_id, t.valid_after;

```
