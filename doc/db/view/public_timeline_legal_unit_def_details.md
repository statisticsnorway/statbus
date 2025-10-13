```sql
                                         View "public.timeline_legal_unit_def"
              Column              |           Type           | Collation | Nullable | Default | Storage  | Description 
----------------------------------+--------------------------+-----------+----------+---------+----------+-------------
 unit_type                        | statistical_unit_type    |           |          |         | plain    | 
 unit_id                          | integer                  |           |          |         | plain    | 
 valid_from                       | date                     |           |          |         | plain    | 
 valid_to                         | date                     |           |          |         | plain    | 
 valid_until                      | date                     |           |          |         | plain    | 
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
 legal_unit_id                    | integer                  |           |          |         | plain    | 
 enterprise_id                    | integer                  |           |          |         | plain    | 
 primary_for_enterprise           | boolean                  |           |          |         | plain    | 
 stats                            | jsonb                    |           |          |         | extended | 
 stats_summary                    | jsonb                    |           |          |         | extended | 
View definition:
 WITH legal_unit_stats AS (
         SELECT t.unit_id,
            t.valid_from,
            jsonb_object_agg(sd.code,
                CASE
                    WHEN sfu.value_float IS NOT NULL THEN to_jsonb(sfu.value_float)
                    WHEN sfu.value_int IS NOT NULL THEN to_jsonb(sfu.value_int)
                    WHEN sfu.value_string IS NOT NULL THEN to_jsonb(sfu.value_string)
                    WHEN sfu.value_bool IS NOT NULL THEN to_jsonb(sfu.value_bool)
                    ELSE NULL::jsonb
                END) FILTER (WHERE sd.code IS NOT NULL) AS stats
           FROM timesegments t
             JOIN stat_for_unit sfu ON sfu.legal_unit_id = t.unit_id AND from_until_overlaps(t.valid_from, t.valid_until, sfu.valid_from, sfu.valid_until)
             JOIN stat_definition sd ON sfu.stat_definition_id = sd.id
          WHERE t.unit_type = 'legal_unit'::statistical_unit_type
          GROUP BY t.unit_id, t.valid_from
        ), basis AS (
         SELECT t.unit_type,
            t.unit_id,
            t.valid_from,
            (t.valid_until - '1 day'::interval)::date AS valid_to,
            t.valid_until,
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
            lu.unit_size_id,
            us.code AS unit_size_code,
            lu.status_id,
            st.code AS status_code,
            st.used_for_counting,
            last_edit.edit_comment AS last_edit_comment,
            last_edit.edit_by_user_id AS last_edit_by_user_id,
            last_edit.edit_at AS last_edit_at,
            lu.invalid_codes,
            true AS has_legal_unit,
            lu.id AS legal_unit_id,
            lu.enterprise_id,
            lu.primary_for_enterprise,
            COALESCE(lu_stats.stats, '{}'::jsonb) AS stats,
            jsonb_stats_to_summary('{}'::jsonb, COALESCE(lu_stats.stats, '{}'::jsonb)) AS stats_summary
           FROM timesegments t
             JOIN LATERAL ( SELECT lu_1.id,
                    lu_1.valid_from,
                    lu_1.valid_to,
                    lu_1.valid_until,
                    lu_1.short_name,
                    lu_1.name,
                    lu_1.birth_date,
                    lu_1.death_date,
                    lu_1.free_econ_zone,
                    lu_1.sector_id,
                    lu_1.status_id,
                    lu_1.legal_form_id,
                    lu_1.edit_comment,
                    lu_1.edit_by_user_id,
                    lu_1.edit_at,
                    lu_1.unit_size_id,
                    lu_1.foreign_participation_id,
                    lu_1.data_source_id,
                    lu_1.enterprise_id,
                    lu_1.primary_for_enterprise,
                    lu_1.invalid_codes
                   FROM legal_unit lu_1
                  WHERE lu_1.id = t.unit_id AND from_until_overlaps(t.valid_from, t.valid_until, lu_1.valid_from, lu_1.valid_until)
                  ORDER BY lu_1.id DESC, lu_1.valid_from DESC
                 LIMIT 1) lu ON true
             LEFT JOIN legal_unit_stats lu_stats ON lu_stats.unit_id = t.unit_id AND lu_stats.valid_from = t.valid_from
             LEFT JOIN LATERAL ( SELECT a.id,
                    a.valid_from,
                    a.valid_to,
                    a.valid_until,
                    a.type,
                    a.category_id,
                    a.data_source_id,
                    a.edit_comment,
                    a.edit_by_user_id,
                    a.edit_at,
                    a.establishment_id,
                    a.legal_unit_id
                   FROM activity a
                  WHERE a.legal_unit_id = lu.id AND a.type = 'primary'::activity_type AND from_until_overlaps(t.valid_from, t.valid_until, a.valid_from, a.valid_until)
                  ORDER BY a.id DESC
                 LIMIT 1) pa ON true
             LEFT JOIN activity_category pac ON pa.category_id = pac.id
             LEFT JOIN LATERAL ( SELECT a.id,
                    a.valid_from,
                    a.valid_to,
                    a.valid_until,
                    a.type,
                    a.category_id,
                    a.data_source_id,
                    a.edit_comment,
                    a.edit_by_user_id,
                    a.edit_at,
                    a.establishment_id,
                    a.legal_unit_id
                   FROM activity a
                  WHERE a.legal_unit_id = lu.id AND a.type = 'secondary'::activity_type AND from_until_overlaps(t.valid_from, t.valid_until, a.valid_from, a.valid_until)
                  ORDER BY a.id DESC
                 LIMIT 1) sa ON true
             LEFT JOIN activity_category sac ON sa.category_id = sac.id
             LEFT JOIN sector s ON lu.sector_id = s.id
             LEFT JOIN legal_form lf ON lu.legal_form_id = lf.id
             LEFT JOIN LATERAL ( SELECT l.id,
                    l.valid_from,
                    l.valid_to,
                    l.valid_until,
                    l.type,
                    l.address_part1,
                    l.address_part2,
                    l.address_part3,
                    l.postcode,
                    l.postplace,
                    l.region_id,
                    l.country_id,
                    l.latitude,
                    l.longitude,
                    l.altitude,
                    l.establishment_id,
                    l.legal_unit_id,
                    l.data_source_id,
                    l.edit_comment,
                    l.edit_by_user_id,
                    l.edit_at
                   FROM location l
                  WHERE l.legal_unit_id = lu.id AND l.type = 'physical'::location_type AND from_until_overlaps(t.valid_from, t.valid_until, l.valid_from, l.valid_until)
                  ORDER BY l.id DESC
                 LIMIT 1) phl ON true
             LEFT JOIN region phr ON phl.region_id = phr.id
             LEFT JOIN country phc ON phl.country_id = phc.id
             LEFT JOIN LATERAL ( SELECT l.id,
                    l.valid_from,
                    l.valid_to,
                    l.valid_until,
                    l.type,
                    l.address_part1,
                    l.address_part2,
                    l.address_part3,
                    l.postcode,
                    l.postplace,
                    l.region_id,
                    l.country_id,
                    l.latitude,
                    l.longitude,
                    l.altitude,
                    l.establishment_id,
                    l.legal_unit_id,
                    l.data_source_id,
                    l.edit_comment,
                    l.edit_by_user_id,
                    l.edit_at
                   FROM location l
                  WHERE l.legal_unit_id = lu.id AND l.type = 'postal'::location_type AND from_until_overlaps(t.valid_from, t.valid_until, l.valid_from, l.valid_until)
                  ORDER BY l.id DESC
                 LIMIT 1) pol ON true
             LEFT JOIN region por ON pol.region_id = por.id
             LEFT JOIN country poc ON pol.country_id = poc.id
             LEFT JOIN LATERAL ( SELECT c_1.id,
                    c_1.valid_from,
                    c_1.valid_to,
                    c_1.valid_until,
                    c_1.web_address,
                    c_1.email_address,
                    c_1.phone_number,
                    c_1.landline,
                    c_1.mobile_number,
                    c_1.fax_number,
                    c_1.establishment_id,
                    c_1.legal_unit_id,
                    c_1.data_source_id,
                    c_1.edit_comment,
                    c_1.edit_by_user_id,
                    c_1.edit_at
                   FROM contact c_1
                  WHERE c_1.legal_unit_id = lu.id AND from_until_overlaps(t.valid_from, t.valid_until, c_1.valid_from, c_1.valid_until)
                  ORDER BY c_1.id DESC
                 LIMIT 1) c ON true
             LEFT JOIN unit_size us ON lu.unit_size_id = us.id
             LEFT JOIN status st ON lu.status_id = st.id
             LEFT JOIN LATERAL ( SELECT array_agg(DISTINCT sfu_1.data_source_id) FILTER (WHERE sfu_1.data_source_id IS NOT NULL) AS data_source_ids
                   FROM stat_for_unit sfu_1
                  WHERE sfu_1.legal_unit_id = lu.id AND from_until_overlaps(t.valid_from, t.valid_until, sfu_1.valid_from, sfu_1.valid_until)) sfu ON true
             LEFT JOIN LATERAL ( SELECT array_agg(ds_1.id) AS ids,
                    array_agg(ds_1.code) AS codes
                   FROM data_source ds_1
                  WHERE COALESCE(ds_1.id = lu.data_source_id, false) OR COALESCE(ds_1.id = pa.data_source_id, false) OR COALESCE(ds_1.id = sa.data_source_id, false) OR COALESCE(ds_1.id = phl.data_source_id, false) OR COALESCE(ds_1.id = pol.data_source_id, false) OR COALESCE(ds_1.id = ANY (sfu.data_source_ids), false)) ds ON true
             LEFT JOIN LATERAL ( SELECT all_edits.edit_comment,
                    all_edits.edit_by_user_id,
                    all_edits.edit_at
                   FROM ( VALUES (lu.edit_comment,lu.edit_by_user_id,lu.edit_at), (pa.edit_comment,pa.edit_by_user_id,pa.edit_at), (sa.edit_comment,sa.edit_by_user_id,sa.edit_at), (phl.edit_comment,phl.edit_by_user_id,phl.edit_at), (pol.edit_comment,pol.edit_by_user_id,pol.edit_at), (c.edit_comment,c.edit_by_user_id,c.edit_at)) all_edits(edit_comment, edit_by_user_id, edit_at)
                  WHERE all_edits.edit_at IS NOT NULL
                  ORDER BY all_edits.edit_at DESC
                 LIMIT 1) last_edit ON true
        )
 SELECT basis.unit_type,
    basis.unit_id,
    basis.valid_from,
    basis.valid_to,
    basis.valid_until,
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
    COALESCE(esa.related_establishment_ids, ARRAY[]::integer[]) AS related_establishment_ids,
    COALESCE(esa.excluded_establishment_ids, ARRAY[]::integer[]) AS excluded_establishment_ids,
    COALESCE(esa.included_establishment_ids, ARRAY[]::integer[]) AS included_establishment_ids,
    ARRAY[basis.unit_id] AS related_legal_unit_ids,
    ARRAY[]::integer[] AS excluded_legal_unit_ids,
        CASE
            WHEN basis.used_for_counting THEN ARRAY[basis.unit_id]
            ELSE '{}'::integer[]
        END AS included_legal_unit_ids,
        CASE
            WHEN basis.enterprise_id IS NOT NULL THEN ARRAY[basis.enterprise_id]
            ELSE ARRAY[]::integer[]
        END AS related_enterprise_ids,
    ARRAY[]::integer[] AS excluded_enterprise_ids,
    ARRAY[]::integer[] AS included_enterprise_ids,
    basis.legal_unit_id,
    basis.enterprise_id,
    basis.primary_for_enterprise,
    basis.stats,
        CASE
            WHEN basis.used_for_counting THEN COALESCE(jsonb_stats_summary_merge(esa.stats_summary, basis.stats_summary), basis.stats_summary, esa.stats_summary, '{}'::jsonb)
            ELSE '{}'::jsonb
        END AS stats_summary
   FROM basis
     LEFT JOIN LATERAL ( SELECT tes.legal_unit_id,
            array_distinct_concat(tes.data_source_ids) AS data_source_ids,
            array_distinct_concat(tes.data_source_codes) AS data_source_codes,
            array_agg(DISTINCT tes.establishment_id) FILTER (WHERE tes.establishment_id IS NOT NULL) AS related_establishment_ids,
            array_agg(DISTINCT tes.establishment_id) FILTER (WHERE tes.establishment_id IS NOT NULL AND NOT tes.used_for_counting) AS excluded_establishment_ids,
            array_agg(DISTINCT tes.establishment_id) FILTER (WHERE tes.establishment_id IS NOT NULL AND tes.used_for_counting) AS included_establishment_ids,
            jsonb_stats_summary_merge_agg(tes.stats_summary) FILTER (WHERE tes.used_for_counting) AS stats_summary
           FROM timeline_establishment tes
          WHERE tes.legal_unit_id = basis.legal_unit_id AND from_until_overlaps(basis.valid_from, basis.valid_until, tes.valid_from, tes.valid_until)
          GROUP BY tes.legal_unit_id) esa ON true
  ORDER BY basis.unit_type, basis.unit_id, basis.valid_from;

```
