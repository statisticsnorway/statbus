BEGIN;

CREATE OR REPLACE FUNCTION admin.import_establishment_era_upsert()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    new_jsonb JSONB := to_jsonb(NEW);
    edit_by_user RECORD;
    tag RECORD;
    physical_region RECORD;
    physical_country RECORD;
    postal_region RECORD;
    postal_country RECORD;
    legal_unit RECORD;
    is_primary_for_legal_unit BOOLEAN;
    enterprise RECORD;
    is_primary_for_enterprise BOOLEAN;
    primary_activity_category RECORD;
    secondary_activity_category RECORD;
    sector RECORD;
    unit_size RECORD;
    status RECORD;
    data_source RECORD;
    meta_data RECORD;
    new_typed RECORD;
    typed_physical_itude_fields RECORD;
    typed_postal_itude_fields RECORD;
    external_idents_to_add public.external_ident[] := ARRAY[]::public.external_ident[];
    prior_establishment_id INTEGER;
    legal_unit_ident_specified BOOL := false;
    inserted_establishment RECORD;
    inserted_location RECORD;
    inserted_activity RECORD;
    stat_def RECORD;
    inserted_stat_for_unit RECORD;
    invalid_codes JSONB := '{}'::jsonb;
    statbus_constraints_already_deferred BOOLEAN;
    stats RECORD;
BEGIN
    SELECT COALESCE(NULLIF(current_setting('statbus.constraints_already_deferred', true),'')::boolean,false) INTO statbus_constraints_already_deferred;

    -- Ensure that id exists and can be referenced
    -- without getting either error
    --   record "enterprise" is not assigned yet
    --   record "enterprise" has no field "id"
    -- Since it always has the correct fallback of NULL for id
    --
    SELECT NULL::DATE AS birth_date
         , NULL::DATE AS death_date
         , NULL::DATE AS valid_from
         , NULL::DATE AS valid_to
        INTO new_typed;
    SELECT NULL::numeric(9,6) AS latitude,
                NULL::numeric(9,6) AS longitude,
                NULL::numeric(6,1) AS altitude
        INTO typed_physical_itude_fields;

        SELECT NULL::numeric(9,6) AS latitude,
                NULL::numeric(9,6) AS longitude,
                NULL::numeric(6,1) AS altitude
        INTO typed_postal_itude_fields;
    SELECT NULL::int AS id INTO tag;
    SELECT NULL::int AS id INTO legal_unit;
    SELECT NULL::int AS id INTO enterprise;
    SELECT NULL::int AS id INTO physical_region;
    SELECT NULL::int AS id INTO physical_country;
    SELECT NULL::int AS id INTO postal_region;
    SELECT NULL::int AS id INTO postal_country;
    SELECT NULL::int AS id INTO primary_activity_category;
    SELECT NULL::int AS id INTO secondary_activity_category;
    SELECT NULL::int AS id INTO sector;
    SELECT NULL::int AS id INTO unit_size;
    SELECT NULL::int AS id INTO status;
    SELECT NULL::int AS id INTO data_source;
    SELECT NULL::int AS employees
         , NULL::int AS turnover
        INTO stats;
    SELECT NULL::int AS id INTO inserted_establishment;
    SELECT NULL::int AS id INTO inserted_location;
    SELECT NULL::int AS id INTO inserted_activity;
    SELECT NULL::int AS id INTO inserted_stat_for_unit;

    SELECT * INTO edit_by_user
    FROM public.statbus_user
    WHERE uuid = auth.uid()
    LIMIT 1;

    SELECT tag_id INTO tag.id FROM admin.import_lookup_tag(new_jsonb);

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

    SELECT latitude
         , longitude
         , altitude
    INTO typed_physical_itude_fields.latitude
       , typed_physical_itude_fields.longitude
       , typed_physical_itude_fields.altitude
    FROM admin.validate_itude_fields('physical'::public.location_type, new_jsonb) AS r;

    SELECT latitude
         , longitude
         , altitude
    INTO typed_postal_itude_fields.latitude
       , typed_postal_itude_fields.longitude
       , typed_postal_itude_fields.altitude
    FROM admin.validate_itude_fields('postal'::public.location_type, new_jsonb) AS r;

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

    SELECT unit_size_id , updated_invalid_codes
    INTO   unit_size.id , invalid_codes
    FROM admin.import_lookup_unit_size(new_jsonb, invalid_codes);

    SELECT status_id , updated_invalid_codes
    INTO   status.id , invalid_codes
    FROM admin.import_lookup_status(new_jsonb, invalid_codes);

    SELECT data_source_id , updated_invalid_codes
    INTO   data_source.id , invalid_codes
    FROM admin.import_lookup_data_source(new_jsonb, invalid_codes);

    SELECT external_idents        , prior_id
    INTO   external_idents_to_add , prior_establishment_id
    FROM admin.process_external_idents(new_jsonb,'establishment') AS r;

    SELECT r.legal_unit_id, r.linked_ident_specified
    INTO legal_unit.id, legal_unit_ident_specified
    FROM admin.process_linked_legal_unit_external_idents(new_jsonb) AS r;

    IF NOT legal_unit_ident_specified THEN
        SELECT r.enterprise_id, r.legal_unit_id, r.is_primary_for_enterprise
        INTO     enterprise.id, legal_unit.id  , is_primary_for_enterprise
        FROM admin.process_enterprise_connection(
            prior_establishment_id, 'establishment',
            new_typed.valid_from, new_typed.valid_to,
            edit_by_user.id) AS r;
    END IF;

    -- If no legal_unit is specified, but there was an existing entry connected to
    -- a legal unit, then update of values is ok, and we must decide if this is primary.
    IF legal_unit.id IS NOT NULL THEN
        DECLARE
          sql_query TEXT :=  format(
            'SELECT NOT EXISTS(
                  SELECT 1
                  FROM public.establishment
                  WHERE legal_unit_id = %L
                  AND primary_for_legal_unit
                  AND COALESCE(id <> %L,true)
                  AND daterange(valid_from, valid_to, ''[]'')
                  && daterange(%L, %L, ''[]'')
              )',
              legal_unit.id, prior_establishment_id, new_typed.valid_from, new_typed.valid_to
          );
        BEGIN
          RAISE DEBUG 'Executing SQL: %', sql_query;
          EXECUTE sql_query
          INTO is_primary_for_legal_unit;
          RAISE DEBUG 'is_primary_for_legal_unit=%', is_primary_for_legal_unit;
        END;
    END IF;

    SELECT true AS active
         , 'Batch import' AS edit_comment
         , CASE WHEN invalid_codes <@ '{}'::jsonb THEN NULL ELSE invalid_codes END AS invalid_codes
      INTO meta_data;

    IF NOT statbus_constraints_already_deferred THEN
        SET CONSTRAINTS ALL DEFERRED;
    END IF;

    INSERT INTO public.establishment_era
        ( valid_from
        , valid_to
        , id
        , name
        , birth_date
        , death_date
        , active
        , edit_comment
        , sector_id
        , unit_size_id
        , status_id
        , invalid_codes
        , enterprise_id
        , legal_unit_id
        , primary_for_legal_unit
        , primary_for_enterprise
        , data_source_id
        , edit_by_user_id
        , edit_at
        )
    VALUES
        ( new_typed.valid_from
        , new_typed.valid_to
        , prior_establishment_id
        , NEW.name
        , new_typed.birth_date
        , new_typed.death_date
        , meta_data.active
        , meta_data.edit_comment
        , sector.id
        , unit_size.id
        , status.id
        , meta_data.invalid_codes
        , enterprise.id
        , legal_unit.id
        , is_primary_for_legal_unit
        , is_primary_for_enterprise
        , data_source.id
        , edit_by_user.id
        , statement_timestamp()
        )
     RETURNING *
     INTO inserted_establishment;
    RAISE DEBUG 'inserted_establishment %', to_json(inserted_establishment);

    IF NOT statbus_constraints_already_deferred THEN
        IF current_setting('client_min_messages') ILIKE 'debug%' THEN
            DECLARE
                row RECORD;
            BEGIN
                RAISE DEBUG 'DEBUG: Selecting from public.establishment where id = %', inserted_establishment.id;
                FOR row IN
                    SELECT * FROM public.establishment WHERE id = inserted_establishment.id
                LOOP
                    RAISE DEBUG 'establishment row: %', to_json(row);
                END LOOP;
            END;
        END IF;
        SET CONSTRAINTS ALL IMMEDIATE;
        SET CONSTRAINTS ALL DEFERRED;
    END IF;

    PERFORM admin.insert_external_idents(
      new_jsonb,
      external_idents_to_add,
      p_legal_unit_id => null::INTEGER,
      p_establishment_id => inserted_establishment.id,
      p_edit_by_user_id => edit_by_user.id
      );

    PERFORM admin.process_contact_columns(
        new_jsonb,
        inserted_establishment.id,
        NULL,
        new_typed.valid_from,
        new_typed.valid_to,
        data_source.id,
        edit_by_user.id
    );

    IF physical_region.id IS NOT NULL OR physical_country.id IS NOT NULL THEN
        INSERT INTO public.location_era
            ( valid_from
            , valid_to
            , establishment_id
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
            , inserted_establishment.id
            , 'physical'
            , NULLIF(NEW.physical_address_part1,'')
            , NULLIF(NEW.physical_address_part2,'')
            , NULLIF(NEW.physical_address_part3,'')
            , NULLIF(NEW.physical_postcode,'')
            , NULLIF(NEW.physical_postplace,'')
            , typed_physical_itude_fields.latitude
            , typed_physical_itude_fields.longitude
            , typed_physical_itude_fields.altitude
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
            , establishment_id
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
            , inserted_establishment.id
            , 'postal'
            , NULLIF(NEW.postal_address_part1,'')
            , NULLIF(NEW.postal_address_part2,'')
            , NULLIF(NEW.postal_address_part3,'')
            , NULLIF(NEW.postal_postcode,'')
            , NULLIF(NEW.postal_postplace,'')
            , typed_postal_itude_fields.latitude
            , typed_postal_itude_fields.longitude
            , typed_postal_itude_fields.altitude
            , postal_region.id
            , postal_country.id
            , data_source.id
            , edit_by_user.id
            , statement_timestamp()
            )
        RETURNING * INTO inserted_location;
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
            , establishment_id
            , type
            , category_id
            , data_source_id
            , edit_by_user_id
            , edit_at
            )
        VALUES
            ( new_typed.valid_from
            , new_typed.valid_to
            , inserted_establishment.id
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
            , establishment_id
            , type
            , category_id
            , data_source_id
            , edit_by_user_id
            , edit_at
            )
        VALUES
            ( new_typed.valid_from
            , new_typed.valid_to
            , inserted_establishment.id
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
        'establishment',
        inserted_establishment.id,
        new_typed.valid_from,
        new_typed.valid_to,
        data_source.id
        );

    IF tag.id IS NOT NULL THEN
        -- UPSERT to avoid multiple tags for different parts of a timeline.
        INSERT INTO public.tag_for_unit
            ( tag_id
            , establishment_id
            , edit_by_user_id
            , edit_at
            )
        VALUES
            ( tag.id
            , inserted_establishment.id
            , edit_by_user.id
            , statement_timestamp()
            )
        ON CONFLICT (tag_id, establishment_id)
        DO UPDATE SET edit_by_user_id = EXCLUDED.edit_by_user_id
                    , edit_at         = EXCLUDED.edit_at
        ;
    END IF;

    IF NOT statbus_constraints_already_deferred THEN
        SET CONSTRAINTS ALL IMMEDIATE;
    END IF;

    RETURN NULL;
END;
$$;

END;
