-- Down Migration 20250210091825: Create admin.validate_contact_fields
BEGIN;

DROP FUNCTION admin.validate_itude_fields;

END;
