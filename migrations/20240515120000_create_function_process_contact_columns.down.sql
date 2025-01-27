-- Down Migration 20250127211049: create_function_process_contact_columns
BEGIN;

DROP FUNCTION IF EXISTS admin.process_contact_columns(
    JSONB,
    INTEGER,
    INTEGER,
    DATE,
    DATE,
    INTEGER,
    INTEGER
);

END;
