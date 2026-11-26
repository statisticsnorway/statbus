-- Migration 20261126094102: codes are csv column names
BEGIN;

ALTER TABLE public.stat_definition
    ADD CONSTRAINT stat_definition_code_is_csv_column_name CHECK (code ~ '^[a-z0-9_]+$');
COMMENT ON CONSTRAINT stat_definition_code_is_csv_column_name ON public.stat_definition IS
    'A statistical variable''s code is the column name for its values in import CSV files and the target of import mappings, so it is lower-case letters, digits and underscores only: the same rule the admin form applies.';

ALTER TABLE public.external_ident_type
    ADD CONSTRAINT external_ident_type_code_is_csv_column_name CHECK (code ~ '^[a-z0-9_]+$');
COMMENT ON CONSTRAINT external_ident_type_code_is_csv_column_name ON public.external_ident_type IS
    'An external identifier type''s code is the column name for its identifiers in import CSV files and the target of import mappings, so it is lower-case letters, digits and underscores only: the same rule the admin form applies.';

END;
