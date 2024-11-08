```sql
                                        View "public.timeline_establishment"
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
 physical_postal_code             | character varying(200) |           |          |         | extended | 
 physical_postal_place            | character varying(200) |           |          |         | extended | 
 physical_region_id               | integer                |           |          |         | plain    | 
 physical_region_path             | ltree                  |           |          |         | extended | 
 physical_country_id              | integer                |           |          |         | plain    | 
 physical_country_iso_2           | text                   |           |          |         | extended | 
 postal_address_part1             | character varying(200) |           |          |         | extended | 
 postal_address_part2             | character varying(200) |           |          |         | extended | 
 postal_address_part3             | character varying(200) |           |          |         | extended | 
 postal_postal_code               | character varying(200) |           |          |         | extended | 
 postal_postal_place              | character varying(200) |           |          |         | extended | 
 postal_region_id                 | integer                |           |          |         | plain    | 
 postal_region_path               | ltree                  |           |          |         | extended | 
 postal_country_id                | integer                |           |          |         | plain    | 
 postal_country_iso_2             | text                   |           |          |         | extended | 
 invalid_codes                    | jsonb                  |           |          |         | extended | 
 establishment_id                 | integer                |           |          |         | plain    | 
 legal_unit_id                    | integer                |           |          |         | plain    | 
 enterprise_id                    | integer                |           |          |         | plain    | 
 stats                            | jsonb                  |           |          |         | extended | 
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
    NULL::text AS legal_form_code,
    NULL::text AS legal_form_name,
    phl.address_part1 AS physical_address_part1,
    phl.address_part2 AS physical_address_part2,
    phl.address_part3 AS physical_address_part3,
    phl.postal_code AS physical_postal_code,
    phl.postal_place AS physical_postal_place,
    phl.region_id AS physical_region_id,
    phr.path AS physical_region_path,
    phl.country_id AS physical_country_id,
    phc.iso_2 AS physical_country_iso_2,
    pol.address_part1 AS postal_address_part1,
    pol.address_part2 AS postal_address_part2,
    pol.address_part3 AS postal_address_part3,
    pol.postal_code AS postal_postal_code,
    pol.postal_place AS postal_postal_place,
    pol.region_id AS postal_region_id,
    por.path AS postal_region_path,
    pol.country_id AS postal_country_id,
    poc.iso_2 AS postal_country_iso_2,
    es.invalid_codes,
    es.id AS establishment_id,
    es.legal_unit_id,
    es.enterprise_id,
    COALESCE(get_jsonb_stats(es.id, NULL::integer, t.valid_after, t.valid_to), '{}'::jsonb) AS stats
   FROM timesegments t
     JOIN establishment es ON t.unit_type = 'establishment'::statistical_unit_type AND t.unit_id = es.id AND daterange(t.valid_after, t.valid_to, '(]'::text) && daterange(es.valid_after, es.valid_to, '(]'::text)
     LEFT JOIN activity pa ON pa.establishment_id = es.id AND pa.type = 'primary'::activity_type AND daterange(t.valid_after, t.valid_to, '(]'::text) && daterange(pa.valid_after, pa.valid_to, '(]'::text)
     LEFT JOIN activity_category pac ON pa.category_id = pac.id
     LEFT JOIN activity sa ON sa.establishment_id = es.id AND sa.type = 'secondary'::activity_type AND daterange(t.valid_after, t.valid_to, '(]'::text) && daterange(sa.valid_after, sa.valid_to, '(]'::text)
     LEFT JOIN activity_category sac ON sa.category_id = sac.id
     LEFT JOIN sector s ON es.sector_id = s.id
     LEFT JOIN location phl ON phl.establishment_id = es.id AND phl.type = 'physical'::location_type AND daterange(t.valid_after, t.valid_to, '(]'::text) && daterange(phl.valid_after, phl.valid_to, '(]'::text)
     LEFT JOIN region phr ON phl.region_id = phr.id
     LEFT JOIN country phc ON phl.country_id = phc.id
     LEFT JOIN location pol ON pol.establishment_id = es.id AND pol.type = 'postal'::location_type AND daterange(t.valid_after, t.valid_to, '(]'::text) && daterange(pol.valid_after, pol.valid_to, '(]'::text)
     LEFT JOIN region por ON pol.region_id = por.id
     LEFT JOIN country poc ON pol.country_id = poc.id
     LEFT JOIN LATERAL ( SELECT array_agg(DISTINCT sfu_1.data_source_id) FILTER (WHERE sfu_1.data_source_id IS NOT NULL) AS data_source_ids
           FROM stat_for_unit sfu_1
          WHERE sfu_1.establishment_id = es.id AND daterange(t.valid_after, t.valid_to, '(]'::text) && daterange(sfu_1.valid_after, sfu_1.valid_to, '(]'::text)) sfu ON true
     LEFT JOIN LATERAL ( SELECT array_agg(ds_1.id) AS ids,
            array_agg(ds_1.code) AS codes
           FROM data_source ds_1
          WHERE COALESCE(ds_1.id = es.data_source_id, false) OR COALESCE(ds_1.id = pa.data_source_id, false) OR COALESCE(ds_1.id = sa.data_source_id, false) OR COALESCE(ds_1.id = phl.data_source_id, false) OR COALESCE(ds_1.id = pol.data_source_id, false) OR COALESCE(ds_1.id = ANY (sfu.data_source_ids), false)) ds ON true
  ORDER BY t.unit_type, t.unit_id, t.valid_after;

```
