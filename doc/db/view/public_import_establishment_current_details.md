```sql
                            View "public.import_establishment_current"
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
 physical_postal_code             | text |           |          |         | extended | 
 physical_postal_place            | text |           |          |         | extended | 
 physical_region_code             | text |           |          |         | extended | 
 physical_region_path             | text |           |          |         | extended | 
 physical_country_iso_2           | text |           |          |         | extended | 
 postal_address_part1             | text |           |          |         | extended | 
 postal_address_part2             | text |           |          |         | extended | 
 postal_address_part3             | text |           |          |         | extended | 
 postal_postal_code               | text |           |          |         | extended | 
 postal_postal_place              | text |           |          |         | extended | 
 postal_region_code               | text |           |          |         | extended | 
 postal_region_path               | text |           |          |         | extended | 
 postal_country_iso_2             | text |           |          |         | extended | 
 primary_activity_category_code   | text |           |          |         | extended | 
 secondary_activity_category_code | text |           |          |         | extended | 
 sector_code                      | text |           |          |         | extended | 
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
    ''::text AS physical_postal_code,
    ''::text AS physical_postal_place,
    ''::text AS physical_region_code,
    ''::text AS physical_region_path,
    ''::text AS physical_country_iso_2,
    ''::text AS postal_address_part1,
    ''::text AS postal_address_part2,
    ''::text AS postal_address_part3,
    ''::text AS postal_postal_code,
    ''::text AS postal_postal_place,
    ''::text AS postal_region_code,
    ''::text AS postal_region_path,
    ''::text AS postal_country_iso_2,
    ''::text AS primary_activity_category_code,
    ''::text AS secondary_activity_category_code,
    ''::text AS sector_code,
    ''::text AS data_source_code,
    ''::text AS legal_form_code,
    ''::text AS employees,
    ''::text AS turnover,
    ''::text AS tag_path
   FROM import_establishment_era;
Options: security_invoker=on

```
