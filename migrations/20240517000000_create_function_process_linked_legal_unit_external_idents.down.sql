-- Migration: create_function_process_linked_legal_unit_external_idents (Rollback)
BEGIN;

DROP FUNCTION admin.process_linked_legal_unit_external_idents(JSONB);

COMMIT;
