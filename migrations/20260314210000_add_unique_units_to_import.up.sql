BEGIN;

-- Add unique_units to import_definition with a smart default
ALTER TABLE public.import_definition
  ADD COLUMN unique_units BOOLEAN NOT NULL DEFAULT TRUE;

-- Set existing definitions: source_columns → FALSE, job_provided → TRUE
UPDATE public.import_definition
  SET unique_units = (valid_time_from = 'job_provided');

-- Prevent nonsensical combination: job_provided + unique_units=FALSE
-- (multiple rows for same unit in same period would just overwrite each other)
ALTER TABLE public.import_definition
  ADD CONSTRAINT valid_time_unique_units_matrix CHECK (
    NOT (valid_time_from = 'job_provided' AND unique_units = FALSE)
  );

-- Add to import_job for per-job override (NULL = use definition default)
ALTER TABLE public.import_job
  ADD COLUMN unique_units BOOLEAN;

-- Add the validation trigger column update list
-- The trigger on import_definition fires on changes to certain columns;
-- we need to add unique_units to that list via DROP+CREATE.
DROP TRIGGER IF EXISTS trg_validate_import_definition_after_change ON public.import_definition;
CREATE TRIGGER trg_validate_import_definition_after_change
  AFTER INSERT OR DELETE OR UPDATE OF slug, data_source_id, strategy, mode, valid_time_from, default_retention_period, unique_units
  ON public.import_definition
  FOR EACH ROW
  EXECUTE FUNCTION admin.trigger_validate_import_definition();

END;
