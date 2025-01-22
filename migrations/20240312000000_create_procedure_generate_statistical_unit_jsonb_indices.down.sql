BEGIN;

CALL lifecycle_callbacks.del('statistical_unit_jsonb_indices');
CALL admin.cleanup_statistical_unit_jsonb_indices();

DROP PROCEDURE admin.cleanup_statistical_unit_jsonb_indices();

DROP PROCEDURE admin.generate_statistical_unit_jsonb_indices();

END;
