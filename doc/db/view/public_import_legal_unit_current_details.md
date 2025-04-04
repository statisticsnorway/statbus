```sql
                              View "public.import_legal_unit_current"
              Column              | Type | Collation | Nullable | Default | Storage  | Description 
----------------------------------+------+-----------+----------+---------+----------+-------------
 tax_ident                        | text |           |          |         | extended | 
 stat_ident                       | text |           |          |         | extended | 
 name                             | text |           |          |         | extended | 
 birth_date                       | text |           |          |         | extended | 
 death_date                       | text |           |          |         | extended | 
 physical_address_part1           | text |           |          |         | extended | 
 physical_address_part2           | text |           |          |         | extended | 
 physical_address_part3           | text |           |          |         | extended | 
 physical_postcode                | text |           |          |         | extended | 
 physical_postplace               | text |           |          |         | extended | 
 physical_latitude                | text |           |          |         | extended | 
 physical_longitude               | text |           |          |         | extended | 
 physical_altitude                | text |           |          |         | extended | 
 physical_region_code             | text |           |          |         | extended | 
 physical_region_path             | text |           |          |         | extended | 
 physical_country_iso_2           | text |           |          |         | extended | 
 postal_address_part1             | text |           |          |         | extended | 
 postal_address_part2             | text |           |          |         | extended | 
 postal_address_part3             | text |           |          |         | extended | 
 postal_postcode                  | text |           |          |         | extended | 
 postal_postplace                 | text |           |          |         | extended | 
 postal_latitude                  | text |           |          |         | extended | 
 postal_longitude                 | text |           |          |         | extended | 
 postal_altitude                  | text |           |          |         | extended | 
 postal_region_code               | text |           |          |         | extended | 
 postal_region_path               | text |           |          |         | extended | 
 postal_country_iso_2             | text |           |          |         | extended | 
 web_address                      | text |           |          |         | extended | 
 email_address                    | text |           |          |         | extended | 
 phone_number                     | text |           |          |         | extended | 
 landline                         | text |           |          |         | extended | 
 mobile_number                    | text |           |          |         | extended | 
 fax_number                       | text |           |          |         | extended | 
 primary_activity_category_code   | text |           |          |         | extended | 
 secondary_activity_category_code | text |           |          |         | extended | 
 sector_code                      | text |           |          |         | extended | 
 unit_size_code                   | text |           |          |         | extended | 
 status_code                      | text |           |          |         | extended | 
 data_source_code                 | text |           |          |         | extended | 
 legal_form_code                  | text |           |          |         | extended | 
 employees                        | text |           |          |         | extended | 
 turnover                         | text |           |          |         | extended | 
 tag_path                         | text |           |          |         | extended | 
View definition:
 SELECT ''::text AS tax_ident,
    ''::text AS stat_ident,
    ''::text AS name,
    ''::text AS birth_date,
    ''::text AS death_date,
    ''::text AS physical_address_part1,
    ''::text AS physical_address_part2,
    ''::text AS physical_address_part3,
    ''::text AS physical_postcode,
    ''::text AS physical_postplace,
    ''::text AS physical_latitude,
    ''::text AS physical_longitude,
    ''::text AS physical_altitude,
    ''::text AS physical_region_code,
    ''::text AS physical_region_path,
    ''::text AS physical_country_iso_2,
    ''::text AS postal_address_part1,
    ''::text AS postal_address_part2,
    ''::text AS postal_address_part3,
    ''::text AS postal_postcode,
    ''::text AS postal_postplace,
    ''::text AS postal_latitude,
    ''::text AS postal_longitude,
    ''::text AS postal_altitude,
    ''::text AS postal_region_code,
    ''::text AS postal_region_path,
    ''::text AS postal_country_iso_2,
    ''::text AS web_address,
    ''::text AS email_address,
    ''::text AS phone_number,
    ''::text AS landline,
    ''::text AS mobile_number,
    ''::text AS fax_number,
    ''::text AS primary_activity_category_code,
    ''::text AS secondary_activity_category_code,
    ''::text AS sector_code,
    ''::text AS unit_size_code,
    ''::text AS status_code,
    ''::text AS data_source_code,
    ''::text AS legal_form_code,
    ''::text AS employees,
    ''::text AS turnover,
    ''::text AS tag_path
   FROM import_legal_unit_era;
Triggers:
    import_legal_unit_current_upsert_trigger INSTEAD OF INSERT ON import_legal_unit_current FOR EACH ROW EXECUTE FUNCTION admin.import_legal_unit_current_upsert()
Options: security_invoker=on

```
