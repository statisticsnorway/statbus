BEGIN;

CREATE PROCEDURE admin.generate_import_legal_unit_era()
LANGUAGE plpgsql AS $generate_import_legal_unit_era$
DECLARE
    result TEXT := '';
    ident_type_row RECORD;
    ident_type_columns TEXT := '';
    stat_definition_row RECORD;
    stat_definition_columns TEXT := '';

    view_template TEXT := $view_template$
CREATE VIEW public.import_legal_unit_era WITH (security_invoker=on) AS
SELECT '' AS valid_from,
       '' AS valid_to,
{{ident_type_columns}}
       '' AS name,
       '' AS birth_date,
       '' AS death_date,
       '' AS physical_address_part1,
       '' AS physical_address_part2,
       '' AS physical_address_part3,
       '' AS physical_postcode,
       '' AS physical_postplace,
       '' AS physical_region_code,
       '' AS physical_region_path,
       '' AS physical_country_iso_2,
       '' AS postal_address_part1,
       '' AS postal_address_part2,
       '' AS postal_address_part3,
       '' AS postal_postcode,
       '' AS postal_postplace,
       '' AS postal_region_code,
       '' AS postal_region_path,
       '' AS postal_country_iso_2,
       '' AS primary_activity_category_code,
       '' AS secondary_activity_category_code,
       '' AS sector_code,
       '' AS data_source_code,
       '' AS legal_form_code,
{{stat_definition_columns}}
       '' AS tag_path
;
    $view_template$;
BEGIN
    SELECT string_agg(format(E'       %L AS %I,', '', code), E'\n')
    INTO ident_type_columns
    FROM (SELECT code FROM public.external_ident_type_active) AS ordered;

    SELECT string_agg(format(E'       %L AS %I,', '', code), E'\n')
    INTO stat_definition_columns
    FROM (SELECT code FROM public.stat_definition_active) AS ordered;

    view_template := admin.render_template(view_template, jsonb_build_object(
        'ident_type_columns', ident_type_columns,
        'stat_definition_columns', stat_definition_columns
    ));

    RAISE NOTICE 'Creating public.import_legal_unit_era';
    EXECUTE view_template;

    CREATE TRIGGER import_legal_unit_era_upsert_trigger
    INSTEAD OF INSERT ON public.import_legal_unit_era
    FOR EACH ROW
    EXECUTE FUNCTION admin.import_legal_unit_era_upsert();
END;
$generate_import_legal_unit_era$;

CREATE PROCEDURE admin.cleanup_import_legal_unit_era()
LANGUAGE plpgsql AS $$
BEGIN
    RAISE NOTICE 'Deleting public.import_legal_unit_era';
    DROP VIEW public.import_legal_unit_era;
END;
$$;


CALL lifecycle_callbacks.add(
    'import_legal_unit_era',
    ARRAY['public.external_ident_type','public.stat_definition']::regclass[],
    'admin.generate_import_legal_unit_era',
    'admin.cleanup_import_legal_unit_era'
    );
-- Call the generate function once to generate the view with the currently
-- defined external_ident_type's.
CALL admin.generate_import_legal_unit_era();

END;
