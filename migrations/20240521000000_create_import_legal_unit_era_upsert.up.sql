BEGIN;

CREATE FUNCTION admin.import_legal_unit_era_upsert()
RETURNS TRIGGER LANGUAGE plpgsql AS $import_legal_unit_era_upsert$
DECLARE
    new_jsonb JSONB := to_jsonb(NEW);
    edit_by_user RECORD;
    tag RECORD;
    physical_region RECORD;
    physical_country RECORD;
    postal_region RECORD;
    postal_country RECORD;
    primary_activity_category RECORD;
    secondary_activity_category RECORD;
    sector RECORD;
    status RECORD;
    data_source RECORD;
    legal_form RECORD;
    meta_data RECORD;
    new_typed RECORD;
    external_idents_to_add public.external_ident[] := ARRAY[]::public.external_ident[];
    prior_legal_unit_id INTEGER;
    enterprise RECORD;
    is_primary_for_enterprise BOOLEAN;
    inserted_legal_unit RECORD;
    inserted_location RECORD;
    inserted_activity RECORD;
    invalid_codes JSONB := '{}'::jsonb;
    statbus_constraints_already_deferred BOOLEAN;
BEGIN
    SELECT COALESCE(NULLIF(current_setting('statbus.constraints_already_deferred', true),'')::boolean,false) INTO statbus_constraints_already_deferred;

    -- Ensure that id exists and can be referenced
    -- without getting either error
    --   record "physical_region" is not assigned yet
    --   record "physical_region" has no field "id"
    -- Since it always has the correct fallback of NULL for id
    --
    SELECT NULL::DATE AS birth_date
         , NULL::DATE AS death_date
         , NULL::DATE AS valid_from
         , NULL::DATE AS valid_to
        INTO new_typed;
    SELECT NULL::int AS id INTO enterprise;
    SELECT NULL::int AS id INTO physical_region;
    SELECT NULL::int AS id INTO physical_country;
    SELECT NULL::int AS id INTO postal_region;
    SELECT NULL::int AS id INTO postal_country;
    SELECT NULL::int AS id INTO primary_activity_category;
    SELECT NULL::int AS id INTO secondary_activity_category;
    SELECT NULL::int AS id INTO sector;
    SELECT NULL::int AS id INTO status;
    SELECT NULL::int AS id INTO data_source;
    SELECT NULL::int AS id INTO legal_form;
    SELECT NULL::int AS id INTO tag;

    SELECT * INTO edit_by_user
    FROM public.statbus_user
    WHERE uuid = auth.uid()
    LIMIT 1;

    SELECT tag_id INTO tag.id FROM admin.import_lookup_tag(new_jsonb);

    SELECT country_id          , updated_invalid_codes
    INTO   physical_country.id , invalid_codes
    FROM admin.import_lookup_country(new_jsonb, 'physical', invalid_codes);

    SELECT region_id          , updated_invalid_codes
    INTO   physical_region.id , invalid_codes
    FROM admin.import_lookup_region(new_jsonb, 'physical', invalid_codes);

    SELECT country_id        , updated_invalid_codes
    INTO   postal_country.id , invalid_codes
    FROM admin.import_lookup_country(new_jsonb, 'postal', invalid_codes);

    SELECT region_id        , updated_invalid_codes
    INTO   postal_region.id , invalid_codes
    FROM admin.import_lookup_region(new_jsonb, 'postal', invalid_codes);

    SELECT activity_category_id, updated_invalid_codes
    INTO primary_activity_category.id, invalid_codes
    FROM admin.import_lookup_activity_category(new_jsonb, 'primary', invalid_codes);

    SELECT activity_category_id, updated_invalid_codes
    INTO secondary_activity_category.id, invalid_codes
    FROM admin.import_lookup_activity_category(new_jsonb, 'secondary', invalid_codes);

    SELECT sector_id , updated_invalid_codes
    INTO   sector.id , invalid_codes
    FROM admin.import_lookup_sector(new_jsonb, invalid_codes);

    SELECT status_id , updated_invalid_codes
    INTO   status.id , invalid_codes
    FROM admin.import_lookup_status(new_jsonb, invalid_codes);

    SELECT data_source_id , updated_invalid_codes
    INTO   data_source.id , invalid_codes
    FROM admin.import_lookup_data_source(new_jsonb, invalid_codes);

    SELECT legal_form_id , updated_invalid_codes
    INTO   legal_form.id , invalid_codes
    FROM admin.import_lookup_legal_form(new_jsonb, invalid_codes);

    SELECT date_value           , updated_invalid_codes
    INTO   new_typed.birth_date , invalid_codes
    FROM admin.type_date_field(new_jsonb,'birth_date',invalid_codes);

    SELECT date_value           , updated_invalid_codes
    INTO   new_typed.death_date , invalid_codes
    FROM admin.type_date_field(new_jsonb,'death_date',invalid_codes);

    SELECT date_value           , updated_invalid_codes
    INTO   new_typed.valid_from , invalid_codes
    FROM admin.type_date_field(new_jsonb,'valid_from',invalid_codes);

    SELECT date_value           , updated_invalid_codes
    INTO   new_typed.valid_to   , invalid_codes
    FROM admin.type_date_field(new_jsonb,'valid_to',invalid_codes);

    CALL admin.validate_stats_for_unit(new_jsonb);

    SELECT external_idents        , prior_id
    INTO   external_idents_to_add , prior_legal_unit_id
    FROM admin.process_external_idents(new_jsonb,'legal_unit') AS r;

    SELECT true AS active
         , 'Batch import' AS edit_comment
         , CASE WHEN invalid_codes <@ '{}'::jsonb THEN NULL ELSE invalid_codes END AS invalid_codes
      INTO meta_data;

    IF NOT statbus_constraints_already_deferred THEN
        SET CONSTRAINTS ALL DEFERRED;
    END IF;

    SELECT r.enterprise_id, r.is_primary_for_enterprise
    INTO     enterprise.id,   is_primary_for_enterprise
    FROM admin.process_enterprise_connection(
        prior_legal_unit_id, 'legal_unit',
        new_typed.valid_from, new_typed.valid_to,
        edit_by_user.id) AS r;

    INSERT INTO public.legal_unit_era
        ( valid_from
        , valid_to
        , id
        , name
        , birth_date
        , death_date
        , active
        , edit_comment
        , sector_id
        , status_id
        , legal_form_id
        , invalid_codes
        , enterprise_id
        , primary_for_enterprise
        , data_source_id
        , edit_by_user_id
        , edit_at
        )
    VALUES
        ( new_typed.valid_from
        , new_typed.valid_to
        , prior_legal_unit_id
        , NEW.name
        , new_typed.birth_date
        , new_typed.death_date
        , meta_data.active
        , meta_data.edit_comment
        , sector.id
        , status.id
        , legal_form.id
        , meta_data.invalid_codes
        , enterprise.id
        , is_primary_for_enterprise
        , data_source.id
        , edit_by_user.id
        , statement_timestamp()
        )
     RETURNING *
     INTO inserted_legal_unit;
    RAISE DEBUG 'inserted_legal_unit %', to_json(inserted_legal_unit);

    IF NOT statbus_constraints_already_deferred THEN
        IF current_setting('client_min_messages') ILIKE 'debug%' THEN
            DECLARE
                row RECORD;
            BEGIN
                RAISE DEBUG 'DEBUG: Selecting from public.legal_unit where id = %', inserted_legal_unit.id;
                FOR row IN
                    SELECT * FROM public.legal_unit WHERE id = inserted_legal_unit.id
                LOOP
                    RAISE DEBUG 'legal_unit row: %', to_json(row);
                END LOOP;
            END;
        END IF;
        SET CONSTRAINTS ALL IMMEDIATE;
        SET CONSTRAINTS ALL DEFERRED;
    END IF;

    PERFORM admin.insert_external_idents(
      new_jsonb,
      external_idents_to_add,
      p_legal_unit_id => inserted_legal_unit.id,
      p_establishment_id => null::INTEGER,
      p_edit_by_user_id => edit_by_user.id
      );

    IF physical_region.id IS NOT NULL OR physical_country.id IS NOT NULL THEN
        INSERT INTO public.location_era
            ( valid_from
            , valid_to
            , legal_unit_id
            , type
            , address_part1
            , address_part2
            , address_part3
            , postcode
            , postplace
            , latitude
            , longitude
            , altitude
            , region_id
            , country_id
            , data_source_id
            , edit_by_user_id
            , edit_at
            )
        VALUES
            ( new_typed.valid_from
            , new_typed.valid_to
            , inserted_legal_unit.id
            , 'physical'
            , NULLIF(NEW.physical_address_part1,'')
            , NULLIF(NEW.physical_address_part2,'')
            , NULLIF(NEW.physical_address_part3,'')
            , NULLIF(NEW.physical_postcode,'')
            , NULLIF(NEW.physical_postplace,'')
            , NULLIF(NEW.physical_latitude,'')
            , NULLIF(NEW.physical_longitude,'')
            , NULLIF(NEW.physical_altitude,'')
            , physical_region.id
            , physical_country.id
            , data_source.id
            , edit_by_user.id
            , statement_timestamp()
            )
        RETURNING *
        INTO inserted_location;
    END IF;

    IF NOT statbus_constraints_already_deferred THEN
        IF current_setting('client_min_messages') ILIKE 'debug%' THEN
            DECLARE
                row RECORD;
            BEGIN
                RAISE DEBUG 'DEBUG: Selecting from public.location where id = %', inserted_location.id;
                FOR row IN
                    SELECT * FROM public.location WHERE id = inserted_location.id
                LOOP
                    RAISE DEBUG 'location row: %', to_json(row);
                END LOOP;
            END;
        END IF;
        SET CONSTRAINTS ALL IMMEDIATE;
        SET CONSTRAINTS ALL DEFERRED;
    END IF;

    IF postal_region.id IS NOT NULL OR postal_country.id IS NOT NULL THEN
        INSERT INTO public.location_era
            ( valid_from
            , valid_to
            , legal_unit_id
            , type
            , address_part1
            , address_part2
            , address_part3
            , postcode
            , postplace
            , latitude
            , longitude
            , altitude
            , region_id
            , country_id
            , data_source_id
            , edit_by_user_id
            , edit_at
            )
        VALUES
            ( new_typed.valid_from
            , new_typed.valid_to
            , inserted_legal_unit.id
            , 'postal'
            , NULLIF(NEW.postal_address_part1,'')
            , NULLIF(NEW.postal_address_part2,'')
            , NULLIF(NEW.postal_address_part3,'')
            , NULLIF(NEW.postal_postcode,'')
            , NULLIF(NEW.postal_postplace,'')
            , NULLIF(NEW.postal_latitude,'')
            , NULLIF(NEW.postal_longitude,'')
            , NULLIF(NEW.postal_altitude,'')
            , postal_region.id
            , postal_country.id
            , data_source.id
            , edit_by_user.id
            , statement_timestamp()
            )
        RETURNING *
        INTO inserted_location;
    END IF;

    IF NOT statbus_constraints_already_deferred THEN
        IF current_setting('client_min_messages') ILIKE 'debug%' THEN
            DECLARE
                row RECORD;
            BEGIN
                RAISE DEBUG 'DEBUG: Selecting from public.location where id = %', inserted_location.id;
                FOR row IN
                    SELECT * FROM public.location WHERE id = inserted_location.id
                LOOP
                    RAISE DEBUG 'location row: %', to_json(row);
                END LOOP;
            END;
        END IF;
        SET CONSTRAINTS ALL IMMEDIATE;
        SET CONSTRAINTS ALL DEFERRED;
    END IF;

    IF primary_activity_category.id IS NOT NULL THEN
        INSERT INTO public.activity_era
            ( valid_from
            , valid_to
            , legal_unit_id
            , type
            , category_id
            , data_source_id
            , edit_by_user_id
            , edit_at
            )
        VALUES
            ( new_typed.valid_from
            , new_typed.valid_to
            , inserted_legal_unit.id
            , 'primary'
            , primary_activity_category.id
            , data_source.id
            , edit_by_user.id
            , statement_timestamp()
            )
        RETURNING *
        INTO inserted_activity;
    END IF;

    IF NOT statbus_constraints_already_deferred THEN
        IF current_setting('client_min_messages') ILIKE 'debug%' THEN
            DECLARE
                row RECORD;
            BEGIN
                RAISE DEBUG 'DEBUG: Selecting from public.activity where id = %', inserted_activity.id;
                FOR row IN
                    SELECT * FROM public.activity WHERE id = inserted_activity.id
                LOOP
                    RAISE DEBUG 'activity row: %', to_json(row);
                END LOOP;
            END;
        END IF;
        SET CONSTRAINTS ALL IMMEDIATE;
        SET CONSTRAINTS ALL DEFERRED;
    END IF;

    IF secondary_activity_category.id IS NOT NULL THEN
        INSERT INTO public.activity_era
            ( valid_from
            , valid_to
            , legal_unit_id
            , type
            , category_id
            , data_source_id
            , edit_by_user_id
            , edit_at
            )
        VALUES
            ( new_typed.valid_from
            , new_typed.valid_to
            , inserted_legal_unit.id
            , 'secondary'
            , secondary_activity_category.id
            , data_source.id
            , edit_by_user.id
            , statement_timestamp()
            )
        RETURNING *
        INTO inserted_activity;
    END IF;

    IF NOT statbus_constraints_already_deferred THEN
        IF current_setting('client_min_messages') ILIKE 'debug%' THEN
            DECLARE
                row RECORD;
            BEGIN
                RAISE DEBUG 'DEBUG: Selecting from public.activity where id = %', inserted_activity.id;
                FOR row IN
                    SELECT * FROM public.activity WHERE id = inserted_activity.id
                LOOP
                    RAISE DEBUG 'activity row: %', to_json(row);
                END LOOP;
            END;
        END IF;
        SET CONSTRAINTS ALL IMMEDIATE;
        SET CONSTRAINTS ALL DEFERRED;
    END IF;

    CALL admin.process_stats_for_unit(
        new_jsonb,
        'legal_unit',
        inserted_legal_unit.id,
        new_typed.valid_from,
        new_typed.valid_to,
        data_source.id
        );

    IF tag.id IS NOT NULL THEN
        INSERT INTO public.tag_for_unit
            ( tag_id
            , legal_unit_id
            , edit_by_user_id
            , edit_at
            )
        VALUES
            ( tag.id
            , inserted_legal_unit.id
            , edit_by_user.id
            , statement_timestamp()
            )
        ON CONFLICT (tag_id, legal_unit_id)
        DO UPDATE SET edit_by_user_id = EXCLUDED.edit_by_user_id
                    , edit_at         = EXCLUDED.edit_at
        ;
    END IF;

    IF NOT statbus_constraints_already_deferred THEN
        SET CONSTRAINTS ALL IMMEDIATE;
    END IF;

    RETURN NULL;
END;
$import_legal_unit_era_upsert$;

END;
