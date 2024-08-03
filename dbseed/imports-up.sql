BEGIN;

-- import structures
\echo public.import_strategy
CREATE TYPE public.import_strategy AS ENUM ('create_or_update','update');
\echo public.import_type
CREATE TYPE public.import_type AS ENUM ('legal_unit','establishment_for_legal_unit', 'establishment_without_legal_unit');

\echo public.import_definition
CREATE TABLE public.import_definition (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    type public.import_type NOT NULL,
    name varchar NOT NULL,
    label varchar NOT NULL,
    description text,
    strategy public.import_strategy NOT NULL,
    delete_missing BOOL,
    source_column_names text[],
    --csv_delimiter text,
    --csv_skip_count integer CHECK(csv_skip_count >= 0),
    data_source_id integer REFERENCES public.data_source(id) ON DELETE RESTRICT,
    user_id integer REFERENCES public.statbus_user(id) ON DELETE SET NULL,
    CHECK(CASE strategy
        WHEN 'create_or_update' THEN delete_missing IS NOT NULL
        WHEN 'update'           THEN delete_missing IS NULL
        END
        )
);
CREATE UNIQUE INDEX ix_import_definition_name ON public.import_definition USING btree (name);
CREATE INDEX ix_import_definition_user_id ON public.import_definition USING btree (user_id);

\echo public.import_mapping
CREATE TABLE public.import_mapping (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    import_definition_id integer REFERENCES public.import_definition(id) ON DELETE CASCADE,
    source_name TEXT,
    source_value TEXT,
    priority integer UNIQUE,
    target_name TEXT NOT NULL,
    CHECK( source_name IS NOT NULL AND source_value IS NULL
        OR source_name IS NULL AND source_value IS NOT NULL
        )
);
COMMENT ON COLUMN public.import_mapping.priority IS 'View ordering of the source fields';

\echo public.import_job_status
CREATE TYPE public.import_job_status AS ENUM ('waiting_for_data', 'analysing_data', 'waiting_for_approval', 'importing', 'finished');

\echo public.import_job
CREATE TABLE public.import_job (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    label varchar,
    description text,
    note text,
    analysis_start_at timestamp with time zone,
    analysis_stop_at timestamp with time zone,
    changes_approved_at timestamp with time zone,
    import_start_at timestamp with time zone,
    import_stop_at timestamp with time zone,
    import_table text NOT NULL,
    import_view text NOT NULL,
    --import_file_path_and_name text NOT NULL,
    status public.import_job_status NOT NULL,
    import_definition_id integer NOT NULL REFERENCES public.import_definition(id) ON DELETE CASCADE,
    user_id integer REFERENCES public.statbus_user(id) ON DELETE SET NULL,
    skip_lines_count integer NOT NULL
);
CREATE INDEX ix_import_job_import_definition_id ON public.import_job USING btree (import_definition_id);
CREATE INDEX ix_import_job_user_id ON public.import_job USING btree (user_id);





END;