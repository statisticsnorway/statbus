```sql
                   View "public.import_legal_unit_era"
              Column              | Type | Collation | Nullable | Default 
----------------------------------+------+-----------+----------+---------
 valid_from                       | text |           |          | 
 valid_to                         | text |           |          | 
 tax_ident                        | text |           |          | 
 stat_ident                       | text |           |          | 
 name                             | text |           |          | 
 birth_date                       | text |           |          | 
 death_date                       | text |           |          | 
 physical_address_part1           | text |           |          | 
 physical_address_part2           | text |           |          | 
 physical_address_part3           | text |           |          | 
 physical_postal_code             | text |           |          | 
 physical_postal_place            | text |           |          | 
 physical_region_code             | text |           |          | 
 physical_region_path             | text |           |          | 
 physical_country_iso_2           | text |           |          | 
 postal_address_part1             | text |           |          | 
 postal_address_part2             | text |           |          | 
 postal_address_part3             | text |           |          | 
 postal_postal_code               | text |           |          | 
 postal_postal_place              | text |           |          | 
 postal_region_code               | text |           |          | 
 postal_region_path               | text |           |          | 
 postal_country_iso_2             | text |           |          | 
 primary_activity_category_code   | text |           |          | 
 secondary_activity_category_code | text |           |          | 
 sector_code                      | text |           |          | 
 data_source_code                 | text |           |          | 
 legal_form_code                  | text |           |          | 
 employees                        | text |           |          | 
 turnover                         | text |           |          | 
 tag_path                         | text |           |          | 
Triggers:
    import_legal_unit_era_upsert_trigger INSTEAD OF INSERT ON import_legal_unit_era FOR EACH ROW EXECUTE FUNCTION admin.import_legal_unit_era_upsert()

```
