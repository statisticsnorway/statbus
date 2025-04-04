```sql
CREATE OR REPLACE PROCEDURE admin.generate_import_establishment_current()
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    ident_type_row RECORD;
    ident_type_columns TEXT := '';
    stat_definition_row RECORD;
    stat_definition_columns TEXT := '';

    view_template TEXT := $view_template$
CREATE VIEW public.import_establishment_current WITH (security_invoker=on) AS
SELECT
{{ident_type_columns}}
       '' AS name,
       '' AS birth_date,
       '' AS death_date,
       '' AS physical_address_part1,
       '' AS physical_address_part2,
       '' AS physical_address_part3,
       '' AS physical_postcode,
       '' AS physical_postplace,
       '' AS physical_latitude,
       '' AS physical_longitude,
       '' AS physical_altitude,
       '' AS physical_region_code,
       '' AS physical_region_path,
       '' AS physical_country_iso_2,
       '' AS postal_address_part1,
       '' AS postal_address_part2,
       '' AS postal_address_part3,
       '' AS postal_postcode,
       '' AS postal_postplace,
       '' AS postal_latitude,
       '' AS postal_longitude,
       '' AS postal_altitude,
       '' AS postal_region_code,
       '' AS postal_region_path,
       '' AS postal_country_iso_2,
       '' AS web_address,
       '' AS email_address,
       '' AS phone_number,
       '' AS landline,
       '' AS mobile_number,
       '' AS fax_number,
       '' AS primary_activity_category_code,
       '' AS secondary_activity_category_code,
       '' AS sector_code,
       '' AS unit_size_code,
       '' AS status_code,
       '' AS data_source_code,
       '' AS legal_form_code,
{{stat_definition_columns}}
       '' AS tag_path
FROM public.import_establishment_era;
    $view_template$;

    ident_insert_labels TEXT := '';
    stats_insert_labels TEXT := '';
    ident_value_labels TEXT := '';
    stats_value_labels TEXT := '';

    function_template TEXT := $function_template$
CREATE FUNCTION admin.import_establishment_current_upsert()
RETURNS TRIGGER LANGUAGE plpgsql AS $import_establishment_current_upsert$
DECLARE
    new_valid_from DATE := current_date;
    new_valid_to DATE := 'infinity'::date;
BEGIN
    INSERT INTO public.import_establishment_era(
        valid_from,
        valid_to,
{{ident_insert_labels}}
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
        sector_code,
        unit_size_code,
        status_code,
        data_source_code,
        legal_form_code,
{{stats_insert_labels}}
        tag_path
        )
    VALUES (
        new_valid_from,
        new_valid_to,
{{ident_value_labels}}
        NEW.name,
        NEW.birth_date,
        NEW.death_date,
        NEW.physical_address_part1,
        NEW.physical_address_part2,
        NEW.physical_address_part3,
        NEW.physical_postcode,
        NEW.physical_postplace,
        NEW.physical_latitude,
        NEW.physical_longitude,
        NEW.physical_altitude,
        NEW.physical_region_code,
        NEW.physical_region_path,
        NEW.physical_country_iso_2,
        NEW.postal_address_part1,
        NEW.postal_address_part2,
        NEW.postal_address_part3,
        NEW.postal_postcode,
        NEW.postal_postplace,
        NEW.postal_latitude,
        NEW.postal_longitude,
        NEW.postal_altitude,
        NEW.postal_region_code,
        NEW.postal_region_path,
        NEW.postal_country_iso_2,
        NEW.web_address,
        NEW.email_address,
        NEW.phone_number,
        NEW.landline,
        NEW.mobile_number,
        NEW.fax_number,
        NEW.primary_activity_category_code,
        NEW.secondary_activity_category_code,
        NEW.sector_code,
        NEW.unit_size_code,
        NEW.status_code,
        NEW.data_source_code,
        NEW.legal_form_code,
{{stats_value_labels}}
        NEW.tag_path
        );
    RETURN NULL;
END;
$import_establishment_current_upsert$;
    $function_template$;
BEGIN
    SELECT
        string_agg(format(E'     %L AS %I,', '', code), E'\n'),
        string_agg(format(E'        %I,', code), E'\n'),
        string_agg(format(E'        NEW.%I,', code), E'\n')
    INTO
        ident_type_columns,
        ident_insert_labels,
        ident_value_labels
    FROM (SELECT code FROM public.external_ident_type_active) AS ordered;

    SELECT
        string_agg(format(E'     %L AS %I,','', code), E'\n'),
        string_agg(format(E'        %I,', code), E'\n'),
        string_agg(format(E'        NEW.%I,', code), E'\n')
    INTO
        stat_definition_columns,
        stats_insert_labels,
        stats_value_labels
    FROM (SELECT code FROM public.stat_definition_active) AS ordered;

    view_template := admin.render_template(view_template, jsonb_build_object(
        'ident_type_columns', ident_type_columns,
        'stat_definition_columns', stat_definition_columns
    ));

    function_template := admin.render_template(function_template, jsonb_build_object(
        'ident_insert_labels', ident_insert_labels,
        'ident_value_labels', ident_value_labels,
        'stats_insert_labels', stats_insert_labels,
        'stats_value_labels', stats_value_labels
    ));

    RAISE NOTICE 'Creating public.import_establishment_current';
    EXECUTE view_template;

    RAISE NOTICE 'Creating admin.import_establishment_current_upsert()';
    EXECUTE function_template;
END;
$procedure$
```
