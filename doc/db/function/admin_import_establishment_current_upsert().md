```sql
CREATE OR REPLACE FUNCTION admin.import_establishment_current_upsert()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    new_valid_from DATE := current_date;
    new_valid_to DATE := 'infinity'::date;
BEGIN
    INSERT INTO public.import_establishment_era(
        valid_from,
        valid_to,
        tax_ident,
        stat_ident,
        name,
        birth_date,
        death_date,
        physical_address_part1,
        physical_address_part2,
        physical_address_part3,
        physical_postcode,
        physical_postplace,
        physical_region_code,
        physical_region_path,
        physical_country_iso_2,
        postal_address_part1,
        postal_address_part2,
        postal_address_part3,
        postal_postcode,
        postal_postplace,
        postal_region_code,
        postal_region_path,
        postal_country_iso_2,
        primary_activity_category_code,
        secondary_activity_category_code,
        sector_code,
        data_source_code,
        legal_form_code,
        employees,
        turnover,
        tag_path
        )
    VALUES (
        new_valid_from,
        new_valid_to,
        NEW.tax_ident,
        NEW.stat_ident,
        NEW.name,
        NEW.birth_date,
        NEW.death_date,
        NEW.physical_address_part1,
        NEW.physical_address_part2,
        NEW.physical_address_part3,
        NEW.physical_postcode,
        NEW.physical_postplace,
        NEW.physical_region_code,
        NEW.physical_region_path,
        NEW.physical_country_iso_2,
        NEW.postal_address_part1,
        NEW.postal_address_part2,
        NEW.postal_address_part3,
        NEW.postal_postcode,
        NEW.postal_postplace,
        NEW.postal_region_code,
        NEW.postal_region_path,
        NEW.postal_country_iso_2,
        NEW.primary_activity_category_code,
        NEW.secondary_activity_category_code,
        NEW.sector_code,
        NEW.data_source_code,
        NEW.legal_form_code,
        NEW.employees,
        NEW.turnover,
        NEW.tag_path
        );
    RETURN NULL;
END;
$function$
```
