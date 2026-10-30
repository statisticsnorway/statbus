-- Down Migration 20261030151659: PostgreSQL cannot drop an enum value, so
-- 'ignored' stays; 20261030151700's down migration removes every use of it.
BEGIN;

COMMENT ON TYPE public.import_data_column_purpose IS 'Defines the role of a column within the job-specific _data table:
- source_input: Raw data mapped directly from the source file (always TEXT).
- internal: Intermediate results from analysis (lookups, type casting, calculations).
- pk_id: Primary key of the record inserted/updated in a final Statbus table by a process step.
- metadata: Internal columns for tracking row state and errors.';

END;
