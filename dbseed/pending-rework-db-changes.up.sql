\echo public.analysis_queue
CREATE TABLE public.analysis_queue (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_start_period timestamp with time zone NOT NULL,
    user_end_period timestamp with time zone NOT NULL,
    user_id integer NOT NULL REFERENCES public.statbus_user(id) ON DELETE CASCADE,
    comment text,
    server_start_period timestamp with time zone,
    server_end_period timestamp with time zone
);
CREATE INDEX ix_analysis_queue_user_id ON public.analysis_queue USING btree (user_id);

\echo public.custom_analysis_check
CREATE TABLE public.custom_analysis_check (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name character varying(64),
    query character varying(2048),
    target_unit_types character varying(16)
);


-- This is not in use currently, as it is slated to be replaced by specific reports using the /search functionality
-- on statistical_unit
\echo public.analysis_log
CREATE TABLE public.analysis_log (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    analysis_queue_id integer NOT NULL REFERENCES public.analysis_queue(id) ON DELETE CASCADE,
    establishment_id integer check (admin.establishment_id_exists(establishment_id)),
    legal_unit_id integer check (admin.legal_unit_id_exists(legal_unit_id)),
    enterprise_id integer REFERENCES public.enterprise(id) ON DELETE CASCADE,
    enterprise_group_id integer check (admin.enterprise_group_id_exists(enterprise_group_id)),
    issued_at timestamp with time zone NOT NULL,
    resolved_at timestamp with time zone,
    summary_messages text,
    error_values text,
    CONSTRAINT "One and only one statistical unit id must be set"
    CHECK( establishment_id IS NOT NULL AND legal_unit_id IS     NULL AND enterprise_id IS     NULL AND enterprise_group_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS NOT NULL AND enterprise_id IS     NULL AND enterprise_group_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS     NULL AND enterprise_id IS NOT NULL AND enterprise_group_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS     NULL AND enterprise_id IS     NULL AND enterprise_group_id IS NOT NULL
        )
);
CREATE INDEX ix_analysis_log_analysis_queue_id_analyzed_queue_id ON public.analysis_log USING btree (analysis_queue_id);
CREATE INDEX ix_analysis_log_analysis_queue_id_establishment_id ON public.analysis_log USING btree (establishment_id);
CREATE INDEX ix_analysis_log_analysis_queue_id_legal_unit_id ON public.analysis_log USING btree (legal_unit_id);
CREATE INDEX ix_analysis_log_analysis_queue_id_enterprise_id ON public.analysis_log USING btree (enterprise_id);
CREATE INDEX ix_analysis_log_analysis_queue_id_enterprise_group_id ON public.analysis_log USING btree (enterprise_group_id);


-- Currently unused.
\echo public.postal_index
CREATE TABLE public.postal_index (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name text,
    archived boolean NOT NULL DEFAULT false,
    name_language1 text,
    name_language2 text
);


-- Currently unused
\echo public.report_tree
CREATE TABLE public.report_tree (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    title text,
    type text,
    report_id integer,
    parent_node_id integer,
    archived boolean NOT NULL DEFAULT false,
    resource_group text,
    report_url text
);


-- Currently unused, replaced by the temporal tables.
\echo public.sample_frame
CREATE TABLE public.sample_frame (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name text NOT NULL,
    description text,
    predicate text NOT NULL,
    fields text NOT NULL,
    user_id integer REFERENCES public.statbus_user(id) ON DELETE SET NULL,
    status integer NOT NULL,
    file_path text,
    generated_date_time timestamp with time zone,
    creation_date timestamp with time zone NOT NULL,
    editing_date timestamp with time zone
);
CREATE INDEX ix_sample_frame_user_id ON public.sample_frame USING btree (user_id);



-- TODO: Create a view to see an establishment with statistics
-- TODO: allow upsert on statistics view according to stat_definition

---- Example dynamic generation of view for each active stat_definition
-- CREATE OR REPLACE FUNCTION generate_legal_unit_history_with_stats_view()
-- RETURNS VOID LANGUAGE plpgsql AS $$
-- DECLARE
--     dyn_query TEXT;
--     stat_code RECORD;
-- BEGIN
--     -- Start building the dynamic query
--     dyn_query := 'CREATE OR REPLACE VIEW legal_unit_history_with_stats AS SELECT id, unit_ident, name, edit_comment, valid_from, valid_to';
--
--     -- For each code in stat_definition, add it as a column
--     FOR stat_code IN (SELECT code FROM stat_definition WHERE archived = false ORDER BY priority)
--     LOOP
--         dyn_query := dyn_query || ', stats ->> ''' || stat_code.code || ''' AS "' || stat_code.code || '"';
--     END LOOP;
--
--     dyn_query := dyn_query || ' FROM legal_unit_history';
--
--     -- Execute the dynamic query
--     EXECUTE dyn_query;
--     -- Reload PostgREST to expose the new view
--     NOTIFY pgrst, 'reload config';
-- END;
-- $$;
-- --
-- CREATE OR REPLACE FUNCTION generate_legal_unit_history_with_stats_view_trigger()
-- RETURNS TRIGGER LANGUAGE plpgsql AS $$
-- BEGIN
--     -- Call the view generation function
--     PERFORM generate_legal_unit_history_with_stats_view();
--
--     -- As this is an AFTER trigger, we don't need to return any specific row.
--     RETURN NULL;
-- END;
-- $$;
-- --
-- CREATE TRIGGER regenerate_stats_view_trigger
-- AFTER INSERT OR UPDATE OR DELETE ON stat_definition
-- FOR EACH ROW
-- EXECUTE FUNCTION generate_legal_unit_history_with_stats_view_trigger();
-- --
-- SELECT generate_legal_unit_history_with_stats_view();
--



-- TODO: Use pg_audit.
