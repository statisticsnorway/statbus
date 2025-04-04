```sql
                     View "public.import_establishment_current_for_legal_unit"
              Column              | Type | Collation | Nullable | Default | Storage  | Description 
----------------------------------+------+-----------+----------+---------+----------+-------------
 tax_ident                        | text |           |          |         | extended | 
 stat_ident                       | text |           |          |         | extended | 
 legal_unit_tax_ident             | text |           |          |         | extended | 
 legal_unit_stat_ident            | text |           |          |         | extended | 
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
 unit_size_code                   | text |           |          |         | extended | 
 status_code                      | text |           |          |         | extended | 
 data_source_code                 | text |           |          |         | extended | 
 employees                        | text |           |          |         | extended | 
 turnover                         | text |           |          |         | extended | 
 tag_path                         | text |           |          |         | extended | 
View definition:
 SELECT tax_ident,
    stat_ident,
    legal_unit_tax_ident,
    legal_unit_stat_ident,
    name,
    birth_date,
    death_date,
    physical_address_part1,
    physical_address_part2,
    physical_address_part3,
    physical_postcode,
    physical_postplace,
    physical_latitude,
    physical_longitude,
    physical_altitude,
    physical_region_code,
    physical_region_path,
    physical_country_iso_2,
    postal_address_part1,
    postal_address_part2,
    postal_address_part3,
    postal_postcode,
    postal_postplace,
    postal_latitude,
    postal_longitude,
    postal_altitude,
    postal_region_code,
    postal_region_path,
    postal_country_iso_2,
    web_address,
    email_address,
    phone_number,
    landline,
    mobile_number,
    fax_number,
    primary_activity_category_code,
    secondary_activity_category_code,
    unit_size_code,
    status_code,
    data_source_code,
    ''::text AS employees,
    ''::text AS turnover,
    tag_path
   FROM import_establishment_era;
Triggers:
    import_establishment_current_for_legal_unit_upsert_trigger INSTEAD OF INSERT ON import_establishment_current_for_legal_unit FOR EACH ROW EXECUTE FUNCTION admin.import_establishment_current_for_legal_unit_upsert()
Options: security_invoker=on

```
