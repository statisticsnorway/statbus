BEGIN;

-- =================================================================
-- BEGIN: Render template with consistency checking.
-- =================================================================
CREATE FUNCTION admin.render_template(template TEXT, vars JSONB)
RETURNS TEXT AS $$
DECLARE
    required_variables TEXT[];
    provided_variables TEXT[];
    missing_variables TEXT[];
    excess_variables TEXT[];
    key TEXT;
BEGIN
    -- Extract all placeholders from the template using a capture group
    SELECT array_agg(DISTINCT match[1])
    INTO required_variables
    FROM regexp_matches(template, '\{\{([a-zA-Z_][a-zA-Z0-9_]*)\}\}', 'g') AS match;

    -- Extract all keys from the provided JSONB object
    SELECT array_agg(var)
    INTO provided_variables
    FROM jsonb_object_keys(vars) AS var;

    -- Check variables.
    WITH
    required AS (SELECT unnest(required_variables) AS variable),
    provided AS (SELECT unnest(provided_variables) AS variable),
    missing AS (
        SELECT array_agg(variable) AS variables
        FROM required
        WHERE variable NOT IN (SELECT variable FROM provided)
    ),
    excess AS (
        SELECT array_agg(variable) AS variables
        FROM provided
        WHERE variable NOT IN (SELECT variable FROM required)
    )
    SELECT missing.variables, excess.variables
    INTO missing_variables, excess_variables
    FROM missing, excess;

    -- Raise exception if there are missing variables
    IF array_length(missing_variables, 1) IS NOT NULL THEN
        RAISE EXCEPTION 'Missing variables: %', array_to_string(missing_variables, ', ');
    END IF;

    -- Raise exception if there are excess variables
    IF array_length(excess_variables, 1) IS NOT NULL THEN
        RAISE EXCEPTION 'Unsupported variables: %', array_to_string(excess_variables, ', ');
    END IF;

    -- Perform the replacement
    FOREACH key IN ARRAY provided_variables LOOP
        template := REPLACE(template, '{{' || key || '}}', COALESCE(vars->>key,''));
    END LOOP;

    RETURN template;
END;
$$ LANGUAGE plpgsql;

-- =================================================================
-- END: Render template with consistency checking.
-- =================================================================

END;
