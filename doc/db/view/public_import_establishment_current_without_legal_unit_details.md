```sql
                   View "public.import_establishment_current_without_legal_unit"
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
 status_code                      | text |           |          |         | extended | 
 data_source_code                 | text |           |          |         | extended | 
 employees                        | text |           |          |         | extended | 
 turnover                         | text |           |          |         | extended | 
 tag_path                         | text |           |          |         | extended | 
View definition:
 SELECT import_establishment_era.tax_ident,
    import_establishment_era.stat_ident,
    import_establishment_era.name,
    import_establishment_era.birth_date,
    import_establishment_era.death_date,
    import_establishment_era.physical_address_part1,
    import_establishment_era.physical_address_part2,
    import_establishment_era.physical_address_part3,
    import_establishment_era.physical_postcode,
    import_establishment_era.physical_postplace,
    import_establishment_era.physical_latitude,
    import_establishment_era.physical_longitude,
    import_establishment_era.physical_altitude,
    import_establishment_era.physical_region_code,
    import_establishment_era.physical_region_path,
    import_establishment_era.physical_country_iso_2,
    import_establishment_era.postal_address_part1,
    import_establishment_era.postal_address_part2,
    import_establishment_era.postal_address_part3,
    import_establishment_era.postal_postcode,
    import_establishment_era.postal_postplace,
    import_establishment_era.postal_latitude,
    import_establishment_era.postal_longitude,
    import_establishment_era.postal_altitude,
    import_establishment_era.postal_region_code,
    import_establishment_era.postal_region_path,
    import_establishment_era.postal_country_iso_2,
    import_establishment_era.web_address,
    import_establishment_era.email_address,
    import_establishment_era.phone_number,
    import_establishment_era.landline,
    import_establishment_era.mobile_number,
    import_establishment_era.fax_number,
    import_establishment_era.primary_activity_category_code,
    import_establishment_era.secondary_activity_category_code,
    import_establishment_era.sector_code,
    import_establishment_era.status_code,
    import_establishment_era.data_source_code,
    ''::text AS employees,
    ''::text AS turnover,
    import_establishment_era.tag_path
   FROM import_establishment_era;
Triggers:
    import_establishment_current_without_legal_unit_upsert_trigger INSTEAD OF INSERT ON import_establishment_current_without_legal_unit FOR EACH ROW EXECUTE FUNCTION admin.import_establishment_current_without_legal_unit_upsert()
Options: security_invoker=on

```
