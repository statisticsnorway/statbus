\echo admin.process_stats_for_unit
CREATE PROCEDURE admin.process_stats_for_unit(
    new_jsonb JSONB,
    unit_type TEXT,
    unit_id INTEGER,
    valid_from DATE,
    valid_to DATE,
    data_source_id INTEGER
) LANGUAGE plpgsql AS $process_stats_for_unit$
DECLARE
    stat_code TEXT;
    stat_value TEXT;
    stat_type public.stat_type;
    stat_jsonb JSONB;
    stat_row public.stat_for_unit;
    stat_def_row public.stat_definition;
    stat_codes TEXT[] := '{}';
    unit_fk_field TEXT;
    statbus_constraints_already_deferred BOOLEAN;
BEGIN
    SELECT COALESCE(NULLIF(current_setting('statbus.constraints_already_deferred', true),'')::boolean,false) INTO statbus_constraints_already_deferred;

    IF unit_type NOT IN ('legal_unit', 'establishment') THEN
        RAISE EXCEPTION 'Invalid unit_type: %', unit_type;
    END IF;

    unit_fk_field := unit_type || '_id';

    FOR stat_def_row IN
        (SELECT * FROM public.stat_definition ORDER BY priority, code)
    LOOP
        stat_code := stat_def_row.code;
        stat_type := stat_def_row.type;
        IF new_jsonb ? stat_code THEN
            stat_value := new_jsonb ->> stat_code;
            IF stat_value IS NOT NULL AND stat_value <> '' THEN
                stat_jsonb := jsonb_build_object(
                    'stat_definition_id', stat_def_row.id,
                    'valid_from', valid_from,
                    'valid_to', valid_to,
                    'data_source_id', data_source_id,
                    unit_fk_field, unit_id,
                    'value_' || stat_type, stat_value
                );
                stat_row := ROW(NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
                BEGIN
                    -- Assign jsonb to the row - casting the fields as required,
                    -- possibly throwing an error message.
                    stat_row := jsonb_populate_record(NULL::public.stat_for_unit,stat_jsonb);
                EXCEPTION WHEN OTHERS THEN
                    RAISE EXCEPTION 'Invalid % for row % with error "%"',stat_code, new_jsonb, SQLERRM;
                END;
                INSERT INTO public.stat_for_unit_era
                    ( stat_definition_id
                    , valid_after
                    , valid_from
                    , valid_to
                    , data_source_id
                    , establishment_id
                    , legal_unit_id
                    , value_int
                    , value_float
                    , value_string
                    , value_bool
                    )
                 SELECT stat_row.stat_definition_id
                      , stat_row.valid_after
                      , stat_row.valid_from
                      , stat_row.valid_to
                      , stat_row.data_source_id
                      , stat_row.establishment_id
                      , stat_row.legal_unit_id
                      , stat_row.value_int
                      , stat_row.value_float
                      , stat_row.value_string
                      , stat_row.value_bool
                RETURNING *
                INTO stat_row
                ;
                IF NOT statbus_constraints_already_deferred THEN
                    IF current_setting('client_min_messages') ILIKE 'debug%' THEN
                        DECLARE
                            row RECORD;
                        BEGIN
                            RAISE DEBUG 'DEBUG: Selecting from public.stat_for_unit where id = %', stat_row.id;
                            FOR row IN
                                SELECT * FROM public.stat_for_unit WHERE id = stat_row.id
                            LOOP
                                RAISE DEBUG 'stat_for_unit row: %', to_json(row);
                            END LOOP;
                        END;
                    END IF;
                    SET CONSTRAINTS ALL IMMEDIATE;
                    SET CONSTRAINTS ALL DEFERRED;
                END IF;

                RAISE DEBUG 'inserted_stat_for_unit: %', to_jsonb(stat_row);
            END IF; -- stat_value provided
        END IF; -- stat_code in import
    END LOOP; -- public.stat_definition
END;
$process_stats_for_unit$;