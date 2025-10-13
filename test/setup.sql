-- While the datestyle is set for the database, the pg_regress tool sets the MDY format
-- to ensure consistent date formatting, so we must manually override this
SET datestyle TO 'ISO, DMY';

\if :{?DEBUG}
SET client_min_messages TO debug1;
\else
SET client_min_messages TO NOTICE;
\endif

-- Create temporary function to execute queries as system user
CREATE OR REPLACE FUNCTION test.sudo_exec(
    sql text,
    OUT results jsonb
) RETURNS jsonb
SECURITY DEFINER LANGUAGE plpgsql AS $sudo_exec$
DECLARE
    result_rows jsonb;
BEGIN
    -- Check if the SQL starts with common DDL keywords
    IF sql ~* '^\s*(CREATE|DROP|ALTER|TRUNCATE|GRANT|REVOKE|ANALYZE)' THEN
        -- For DDL statements, execute directly
        EXECUTE sql;
        results := '[]'::jsonb;
    ELSE
        -- For DML/queries, wrap in a SELECT to capture results
        EXECUTE format('
            SELECT COALESCE(
                jsonb_agg(row_to_json(t)),
                ''[]''::jsonb
            )
            FROM (%s) t',
            sql
        ) INTO result_rows;
        results := result_rows;
    END IF;
END;
$sudo_exec$;

-- Grant execute to public since this is for testing
GRANT EXECUTE ON FUNCTION test.sudo_exec(text) TO PUBLIC;

\echo Add users for testing purposes
SELECT * FROM public.user_create(p_display_name => 'Test Admin', p_email => 'test.admin@statbus.org', p_statbus_role => 'admin_user'::statbus_role, p_password => 'Admin#123!');
SELECT * FROM public.user_create(p_display_name => 'Test Regular', p_email => 'test.regular@statbus.org', p_statbus_role => 'regular_user'::statbus_role, p_password => 'Regular#123!');
SELECT * FROM public.user_create(p_display_name => 'Test Restricted', p_email => 'test.restricted@statbus.org', p_statbus_role => 'restricted_user'::statbus_role, p_password => 'Restricted#123!');
