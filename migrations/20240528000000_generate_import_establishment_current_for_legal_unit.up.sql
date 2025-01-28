BEGIN;

CREATE PROCEDURE admin.generate_import_establishment_current_for_legal_unit()
LANGUAGE plpgsql AS $generate_import_establishment_current_for_legal_unit$
DECLARE
    ident_type_row RECORD;
    stat_definition_row RECORD;
    ident_type_columns TEXT := '';
    legal_unit_ident_type_columns TEXT := '';
    stat_definition_columns TEXT := '';
    legal_unit_ident_missing_check TEXT := '';
    ident_insert_labels TEXT := '';
    legal_unit_ident_insert_labels TEXT := '';
    stats_insert_labels TEXT := '';
    ident_value_labels TEXT := '';
    legal_unit_ident_value_labels TEXT := '';
    stats_value_labels TEXT := '';

    view_template TEXT := $view_template$
CREATE VIEW public.import_establishment_current_for_legal_unit
WITH (security_invoker=on) AS
SELECT {{ident_type_columns}}
{{legal_unit_ident_type_columns}}
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
     -- sector_code is Disabled because the legal unit provides the sector_code
       status_code,
       data_source_code,
{{stat_definition_columns}}
       tag_path
FROM public.import_establishment_era;
    $view_template$;

    function_template TEXT := $function_template$
CREATE FUNCTION admin.import_establishment_current_for_legal_unit_upsert()
RETURNS TRIGGER LANGUAGE plpgsql AS $import_establishment_current_for_legal_unit_upsert$
DECLARE
    new_valid_from DATE := current_date;
    new_valid_to DATE := 'infinity'::date;
BEGIN
    IF {{legal_unit_ident_missing_check}}
    THEN
      RAISE EXCEPTION 'Missing legal_unit identifier for row %', to_json(NEW);
    END IF;
    INSERT INTO public.import_establishment_era(
        valid_from,
        valid_to,
{{ident_insert_labels}}
{{legal_unit_ident_insert_labels}}
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
        status_code,
        data_source_code,
{{stats_insert_labels}}
        tag_path
    ) VALUES (
        new_valid_from,
        new_valid_to,
{{ident_value_labels}}
{{legal_unit_ident_value_labels}}
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
        NEW.status_code,
        NEW.data_source_code,
{{stats_value_labels}}
        NEW.tag_path
        );
    RETURN NULL;
END;
$import_establishment_current_for_legal_unit_upsert$;
    $function_template$;
    view_sql TEXT;
    function_sql TEXT;
BEGIN
    SELECT
        string_agg(format('(NEW.%1$I IS NULL OR NEW.%1$I = %2$L)',
                          'legal_unit_' || code, ''), ' AND '),
        string_agg(format(E'     %I,', code), E'\n'),
        string_agg(format(E'     %I,', 'legal_unit_' || code), E'\n'),
        string_agg(format(E'        %I,', code), E'\n'),
        string_agg(format(E'        %I,', 'legal_unit_' || code), E'\n'),
        string_agg(format(E'        NEW.%I,', code), E'\n'),
        string_agg(format(E'        NEW.%I,', 'legal_unit_' || code), E'\n')
    INTO
        legal_unit_ident_missing_check,
        ident_type_columns,
        legal_unit_ident_type_columns,
        ident_insert_labels,
        legal_unit_ident_insert_labels,
        ident_value_labels,
        legal_unit_ident_value_labels
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

    -- Render the view template
    view_sql := admin.render_template(view_template, jsonb_build_object(
        'ident_type_columns', ident_type_columns,
        'legal_unit_ident_type_columns', legal_unit_ident_type_columns,
        'stat_definition_columns', stat_definition_columns
    ));

    -- Render the function template
    function_sql := admin.render_template(function_template, jsonb_build_object(
        'legal_unit_ident_missing_check', COALESCE(legal_unit_ident_missing_check,'true'),
        'ident_insert_labels', ident_insert_labels,
        'legal_unit_ident_insert_labels', legal_unit_ident_insert_labels,
        'stats_insert_labels', stats_insert_labels,
        'ident_value_labels', ident_value_labels,
        'legal_unit_ident_value_labels', legal_unit_ident_value_labels,
        'stats_value_labels', stats_value_labels
    ));

    -- Continue with the rest of your procedure logic
    RAISE NOTICE 'Creating public.import_establishment_current_for_legal_unit';
    EXECUTE view_sql;
    COMMENT ON VIEW public.import_establishment_current_for_legal_unit IS 'Upload of establishment from today and forwards that must connect to a legal_unit';

    RAISE NOTICE 'Creating admin.import_establishment_current_for_legal_unit_upsert()';
    EXECUTE function_sql;

    CREATE TRIGGER import_establishment_current_for_legal_unit_upsert_trigger
    INSTEAD OF INSERT ON public.import_establishment_current_for_legal_unit
    FOR EACH ROW
    EXECUTE FUNCTION admin.import_establishment_current_for_legal_unit_upsert();
END;
$generate_import_establishment_current_for_legal_unit$;

CREATE PROCEDURE admin.cleanup_import_establishment_current_for_legal_unit()
LANGUAGE plpgsql AS $$
BEGIN
    RAISE NOTICE 'Deleting public.import_establishment_current_for_legal_unit';
    DROP VIEW public.import_establishment_current_for_legal_unit;
    RAISE NOTICE 'Deleting admin.import_establishment_current_for_legal_unit_upsert';
    DROP FUNCTION admin.import_establishment_current_for_legal_unit_upsert();
END;
$$;

CALL lifecycle_callbacks.add(
    'import_establishment_current_for_legal_unit',
    ARRAY['public.external_ident_type','public.stat_definition']::regclass[],
    'admin.generate_import_establishment_current_for_legal_unit',
    'admin.cleanup_import_establishment_current_for_legal_unit'
    );

CALL admin.generate_import_establishment_current_for_legal_unit();

END;
