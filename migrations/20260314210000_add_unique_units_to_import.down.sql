BEGIN;

-- Restore original trigger without unique_units column
DROP TRIGGER IF EXISTS trg_validate_import_definition_after_change ON public.import_definition;
CREATE TRIGGER trg_validate_import_definition_after_change
  AFTER INSERT OR DELETE OR UPDATE OF slug, data_source_id, strategy, mode, valid_time_from, default_retention_period
  ON public.import_definition
  FOR EACH ROW
  EXECUTE FUNCTION admin.trigger_validate_import_definition();

-- Drop the CHECK constraint
ALTER TABLE public.import_definition
  DROP CONSTRAINT IF EXISTS valid_time_unique_units_matrix;

-- Drop columns
ALTER TABLE public.import_job
  DROP COLUMN IF EXISTS unique_units;

ALTER TABLE public.import_definition
  DROP COLUMN IF EXISTS unique_units;

END;
