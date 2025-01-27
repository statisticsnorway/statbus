-- Down Migration 20250127145918: create function import lookup status
BEGIN;

DROP FUNCTION IF EXISTS admin.import_lookup_status;

END;
