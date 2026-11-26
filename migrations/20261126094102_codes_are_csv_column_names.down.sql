-- Down Migration 20261126094102: codes are csv column names
BEGIN;

ALTER TABLE public.external_ident_type DROP CONSTRAINT external_ident_type_code_is_csv_column_name;
ALTER TABLE public.stat_definition DROP CONSTRAINT stat_definition_code_is_csv_column_name;

END;
