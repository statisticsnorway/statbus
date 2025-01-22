BEGIN;

CREATE PROCEDURE admin.validate_stats_for_unit(new_jsonb JSONB)
LANGUAGE plpgsql AS $validate_stats_for_unit$
DECLARE
    stat_def_row public.stat_definition;
    stat_code TEXT;
    stat_value TEXT;
    sql_type_str TEXT;
    stat_type_check TEXT;
BEGIN
    FOR stat_def_row IN
        (SELECT * FROM public.stat_definition ORDER BY priority, code)
    LOOP
        stat_code := stat_def_row.code;
        IF new_jsonb ? stat_code THEN
            stat_value := new_jsonb ->> stat_code;
            IF stat_value IS NOT NULL AND stat_value <> '' THEN
                sql_type_str :=
                    CASE stat_def_row.type
                    WHEN 'int' THEN 'INT4'
                    WHEN 'float' THEN 'FLOAT8'
                    WHEN 'string' THEN 'TEXT'
                    WHEN 'bool' THEN 'BOOL'
                    END;
                stat_type_check := format('SELECT %L::%s', stat_value, sql_type_str);
                BEGIN -- Try to cast the stat_value into the correct type.
                    EXECUTE stat_type_check;
                EXCEPTION WHEN OTHERS THEN
                    RAISE EXCEPTION 'Invalid % type for stat % for row % with error "%"', stat_def_row.type, stat_code, new_jsonb, SQLERRM;
                END;
            END IF; -- stat_value provided
        END IF; -- stat_code in import
    END LOOP; -- public.stat_definition
END;
$validate_stats_for_unit$;

END;
