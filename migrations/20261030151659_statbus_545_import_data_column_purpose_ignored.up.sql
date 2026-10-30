-- Migration 20261030151659: STATBUS-545 import_data_column_purpose 'ignored'
--
-- Own migration because a new enum value cannot be used in the transaction
-- that adds it; 20261030151700 uses it.
BEGIN;

ALTER TYPE public.import_data_column_purpose ADD VALUE IF NOT EXISTS 'ignored';

COMMENT ON TYPE public.import_data_column_purpose IS 'Defines the role of a column within the job-specific _data table:
- source_input: Raw data mapped directly from the source file (always TEXT).
- internal: Intermediate results from analysis (lookups, type casting, calculations).
- pk_id: Primary key of the record inserted/updated in a final Statbus table by a process step.
- metadata: Internal columns for tracking row state and errors.
- ignored: A column of the uploaded file that the job''s definition does not map. It is copied to the data table as <column>_raw for display only; no import step reads it.';

END;
