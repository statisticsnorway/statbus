```sql
CREATE OR REPLACE PROCEDURE admin.generate_import_establishment_era_for_legal_unit()
 LANGUAGE plpgsql
AS $procedure$
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
CREATE VIEW public.import_establishment_era_for_legal_unit
WITH (security_invoker=on) AS
SELECT valid_from,
       valid_to,
{{ident_type_columns}}
     -- One of these are required - it must connect to an existing legal_unit
{{legal_unit_ident_type_columns}}
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
       data_source_code,
     -- sector_code is Disabled because the legal unit provides the sector_code
{{stat_definition_columns}}
       tag_path
FROM public.import_establishment_era;
    $view_template$;

    function_template TEXT := $function_template$
CREATE FUNCTION admin.import_establishment_era_for_legal_unit_upsert()
RETURNS TRIGGER LANGUAGE plpgsql AS $import_establishment_era_for_legal_unit_upsert$
BEGIN
    IF {{legal_unit_ident_missing_check}}
    THEN
      RAISE EXCEPTION 'Missing legal_unit identifier for row %', to_json(NEW);
    END IF;
    INSERT INTO public.import_establishment_era(
        valid_from,
        valid_to,
        --
{{ident_insert_labels}}
        --
{{legal_unit_ident_insert_labels}}
        --
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
        data_source_code,
{{stats_insert_labels}}
        tag_path
    ) VALUES (
        NEW.valid_from,
        NEW.valid_to,
        --
{{ident_value_labels}}
        --
{{legal_unit_ident_value_labels}}
        --
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
        NEW.data_source_code,
{{stats_value_labels}}
        NEW.tag_path
        );
    RETURN NULL;
END;
$import_establishment_era_for_legal_unit_upsert$;
    $function_template$;
    view_sql TEXT;
    function_sql TEXT;
BEGIN
    SELECT
        string_agg(format('(NEW.%1$I IS NULL OR NEW.%1$I = %2$L)',
                          'legal_unit_' || code, ''), ' AND '),
        string_agg(format(E'       %I,', code), E'\n'),
        string_agg(format(E'       %I,', 'legal_unit_' || code), E'\n'),
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

    -- Process stat_definition_columns and related fields
    SELECT
        string_agg(format(E'       %L AS %I,','', code), E'\n'),
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
    RAISE NOTICE 'Creating public.import_establishment_era_for_legal_unit';
    EXECUTE view_sql;
    COMMENT ON VIEW public.import_establishment_era_for_legal_unit IS 'Upload of establishment era (any timeline) that must connect to a legal_unit';

    RAISE NOTICE 'Creating admin.import_establishment_era_for_legal_unit_upsert()';
    EXECUTE function_sql;

    CREATE TRIGGER import_establishment_era_for_legal_unit_upsert_trigger
    INSTEAD OF INSERT ON public.import_establishment_era_for_legal_unit
    FOR EACH ROW
    EXECUTE FUNCTION admin.import_establishment_era_for_legal_unit_upsert();
END;
$procedure$
```
