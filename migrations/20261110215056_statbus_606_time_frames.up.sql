-- STATBUS-606: time frames replace time contexts.
--
-- A time frame is the window a user looks at the timelines through: one live
-- frame that takes every new import and edit, and the years before it. The
-- list was a hedge (26 relative period kinds, 3 enabled, two names each, a
-- query/input scope, tags as frames, a year per data year); this keeps what
-- users need and names it once:
--   * live      Live frame (YYYY): current year onwards, read as of today.
--   * relative  Previous frame (YYYY): last year, closed, moves on 1 January.
--   * fixed     Frame YYYY: one closed year, forever.
-- Existing import jobs keep their stored dates; their frame idents move to
-- the new names (r_year_curr -> live, r_year_prev -> prev).
BEGIN;

-- 1. The kinds of frame.
CREATE TYPE public.time_frame_kind AS ENUM ('live', 'relative', 'fixed');
COMMENT ON TYPE public.time_frame_kind IS
'The kind of a time frame (public.time_frame). live: the current year onwards, open-ended, read as of today; every new import and edit lands here without asking. relative: a closed year named by its position (the previous year), so it moves on 1 January; a recurring import job on it loads the right year every year. fixed: one closed year named by its number, forever. Changes that reach into a relative or fixed frame are confirmed in the UI first.';

-- 2. The frames.
DROP VIEW public.time_context;

CREATE VIEW public.time_frame
WITH (security_invoker = on) AS
WITH today AS (
    SELECT COALESCE(NULLIF(current_setting('app.current_date', true), '')::date, CURRENT_DATE) AS date
), years AS (
    SELECT EXTRACT(year FROM today.date)::integer AS current_year FROM today
), frames AS (
    SELECT 'live'::text AS ident,
           'live'::public.time_frame_kind AS kind,
           format('Live frame (%s)', y.current_year) AS name,
           make_date(y.current_year, 1, 1) AS valid_from,
           'infinity'::date AS valid_to,
           today.date AS valid_on,
           y.current_year AS year,
           NULL::text AS equals_frame_ident
    FROM years AS y CROSS JOIN today
    UNION ALL
    SELECT 'prev',
           'relative',
           format('Previous frame (%s)', y.current_year - 1),
           make_date(y.current_year - 1, 1, 1),
           make_date(y.current_year - 1, 12, 31),
           make_date(y.current_year - 1, 12, 31),
           y.current_year - 1,
           NULL
    FROM years AS y
    UNION ALL
    SELECT 'y_' || fy.year,
           'fixed',
           format('Frame %s', fy.year),
           make_date(fy.year, 1, 1),
           make_date(fy.year, 12, 31),
           make_date(fy.year, 12, 31),
           fy.year,
           CASE WHEN fy.year = y.current_year - 1 THEN 'prev' END
    FROM years AS y
    CROSS JOIN LATERAL (
        -- The previous year always, and every earlier year with data.
        SELECT ty.year FROM public.timesegments_years AS ty WHERE ty.year < y.current_year
        UNION
        SELECT y.current_year - 1
    ) AS fy
)
SELECT ident, kind, name, valid_from, valid_to, valid_on, year, equals_frame_ident
FROM frames
ORDER BY kind, valid_from DESC;

COMMENT ON VIEW public.time_frame IS
'The time frames a user looks at the timelines through, for the current date (app.current_date, else CURRENT_DATE): the live frame (ident live), the relative frame for the previous year (ident prev) and a fixed frame per closed year (ident y_YYYY) for the previous year and every earlier year with data. Ordered live, relative, fixed, newest first; the first row is the default. The frame menu leaves out a fixed frame whose equals_frame_ident is set, because it shows the same years as that relative frame today; import pages show every frame.';
COMMENT ON COLUMN public.time_frame.ident IS 'The stable name of the frame: live, prev, or y_YYYY. Import jobs and saved selections refer to it; live and prev keep their ident as the calendar moves.';
COMMENT ON COLUMN public.time_frame.kind IS 'live, relative or fixed (public.time_frame_kind).';
COMMENT ON COLUMN public.time_frame.name IS 'The name shown to users: Live frame (YYYY), Previous frame (YYYY) or Frame YYYY.';
COMMENT ON COLUMN public.time_frame.valid_from IS 'First day of the frame.';
COMMENT ON COLUMN public.time_frame.valid_to IS 'Last day of the frame, inclusive; infinity for the live frame.';
COMMENT ON COLUMN public.time_frame.valid_on IS 'The day the frame is read as of: today for the live frame, 31 December for a closed year.';
COMMENT ON COLUMN public.time_frame.year IS 'The calendar year the frame starts in.';
COMMENT ON COLUMN public.time_frame.equals_frame_ident IS 'For a fixed frame, the relative frame covering the same year today (prev for the previous year), else NULL.';

GRANT SELECT ON public.time_frame TO authenticated, regular_user, admin_user;

-- 3. The retired list.
DROP VIEW public.relative_period_with_time;
DROP TABLE public.relative_period;
DROP TYPE public.relative_period_code;
DROP TYPE public.relative_period_scope;
DROP TYPE public.time_context_type;

-- 4. Import jobs name a frame.
ALTER TABLE public.import_job RENAME COLUMN time_context_ident TO time_frame_ident;
COMMENT ON COLUMN public.import_job.time_frame_ident IS
'The time frame (public.time_frame.ident) whose period becomes this job''s default_valid_from/to when the job is created. A clone keeps the ident and derives the dates again, so a recurring job on live or prev follows the calendar; NULL when the job gives explicit dates or takes them from source columns.';

-- Job idents move to the new names. y_YYYY keeps its name and meaning. The
-- retired idents with no frame of their own (tag frames t_*, never used on any
-- box) are cleared; those jobs keep their stored dates.
UPDATE public.import_job SET time_frame_ident = 'live' WHERE time_frame_ident = 'r_year_curr';
UPDATE public.import_job SET time_frame_ident = 'prev' WHERE time_frame_ident IN ('r_year_prev', 'r_year_prev_only');
UPDATE public.import_job SET time_frame_ident = NULL
WHERE time_frame_ident IS NOT NULL AND time_frame_ident NOT IN ('live', 'prev') AND time_frame_ident NOT LIKE 'y\_%';

-- The snapshot taken at derive time carries the frame under the new key.
UPDATE public.import_job
SET definition_snapshot = (definition_snapshot - 'time_context')
    || jsonb_build_object('time_frame', definition_snapshot->'time_context')
WHERE definition_snapshot ? 'time_context';

ALTER TABLE public.import_job DROP CONSTRAINT snapshot_has_time_context_conditionally;
ALTER TABLE public.import_job DROP CONSTRAINT job_parameters_must_match_valid_time_from_mode;
ALTER TABLE public.import_job ADD CONSTRAINT job_parameters_must_match_valid_time_from_mode CHECK (
    CASE ((definition_snapshot -> 'import_definition') ->> 'valid_time_from')
        WHEN 'job_provided' THEN default_valid_from IS NOT NULL AND default_valid_to IS NOT NULL
        WHEN 'source_columns' THEN time_frame_ident IS NULL AND default_valid_from IS NULL AND default_valid_to IS NULL
        ELSE true
    END);

-- 5. Deriving and cloning a job use the frame.
CREATE OR REPLACE FUNCTION admin.import_job_derive()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    definition public.import_definition;
    v_snapshot JSONB;
BEGIN
    SELECT * INTO definition
    FROM public.import_definition
    WHERE id = NEW.definition_id;

    -- Check if definition exists and is marked as valid
    IF NOT FOUND OR NOT definition.valid THEN
        RAISE EXCEPTION 'Cannot create import job: Import definition % (%) is not valid. Error: %',
            NEW.definition_id, COALESCE(definition.name, 'N/A'), COALESCE(definition.validation_error, 'Definition not found or not marked valid');
    END IF;

    -- Validate time_frame_ident if provided on the job
    IF NEW.time_frame_ident IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.time_frame WHERE ident = NEW.time_frame_ident) THEN
        RAISE EXCEPTION 'Cannot create import job: time frame % does not exist (public.time_frame).', NEW.time_frame_ident;
    END IF;

    IF NEW.slug IS NULL THEN
        NEW.slug := format('import_job_%s', NEW.id);
    END IF;

    NEW.upload_table_name := format('%I', NEW.slug || '_upload');
    NEW.data_table_name := format('%I', NEW.slug || '_data');

    -- Populate the definition_snapshot JSONB with explicit keys matching table names
    SELECT jsonb_build_object(
        'import_definition', (SELECT row_to_json(d) FROM public.import_definition d WHERE d.id = NEW.definition_id),
        'import_step_list', (SELECT jsonb_agg(row_to_json(s) ORDER BY s.priority) FROM public.import_step s JOIN public.import_definition_step ds_link ON s.id = ds_link.step_id WHERE ds_link.definition_id = NEW.definition_id),
        'import_data_column_list', (
            SELECT jsonb_agg(row_to_json(dc) ORDER BY s_link.priority, dc.priority, dc.column_name)
            FROM public.import_data_column dc
            JOIN public.import_step s_link ON dc.step_id = s_link.id
            JOIN public.import_definition_step ds_link ON s_link.id = ds_link.step_id
            WHERE ds_link.definition_id = NEW.definition_id
        ),
        'import_source_column_list', (SELECT jsonb_agg(row_to_json(sc_list) ORDER BY sc_list.priority) FROM public.import_source_column sc_list WHERE sc_list.definition_id = NEW.definition_id),
        'import_mapping_list', (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'mapping', row_to_json(m_map),
                    'source_column', row_to_json(sc_map),
                    'target_data_column', row_to_json(dc_map)
                ) ORDER BY s_link.priority, dc_map.priority, dc_map.column_name, m_map.id
            )
            FROM public.import_mapping m_map
            LEFT JOIN public.import_source_column sc_map ON m_map.source_column_id = sc_map.id AND sc_map.definition_id = m_map.definition_id -- Ensure source_column is for the same definition
            JOIN public.import_data_column dc_map ON m_map.target_data_column_id = dc_map.id
            JOIN public.import_step s_link ON dc_map.step_id = s_link.id
            JOIN public.import_definition_step ds_map_link ON s_link.id = ds_map_link.step_id AND ds_map_link.definition_id = m_map.definition_id -- Ensure data_column's step is linked to this definition
            WHERE m_map.definition_id = NEW.definition_id
        )
    ) INTO v_snapshot;

    IF v_snapshot IS NULL OR NOT (
        v_snapshot ? 'import_definition' AND
        v_snapshot ? 'import_step_list' AND
        v_snapshot ? 'import_data_column_list' AND
        v_snapshot ? 'import_source_column_list' AND
        v_snapshot ? 'import_mapping_list'
    ) THEN
         RAISE EXCEPTION 'Failed to generate a complete definition snapshot for definition_id %. It is missing one or more required keys: import_definition, import_step_list, import_data_column_list, import_source_column_list, import_mapping_list.', NEW.definition_id;
    END IF;

    -- Validate and set default validity dates based on the definition's declarative valid_time_from
    IF definition.valid_time_from = 'job_provided' THEN
        -- Case A: The definition requires job-level dates. The user must provide EITHER a time_frame_ident OR explicit dates, but not both.
        IF NEW.time_frame_ident IS NOT NULL AND (NEW.default_valid_from IS NOT NULL OR NEW.default_valid_to IS NOT NULL) THEN
            RAISE EXCEPTION 'Cannot specify both a time_frame_ident and explicit default_valid_from/to dates for a job with definition %.', definition.name;
        END IF;
        IF NEW.time_frame_ident IS NULL AND (NEW.default_valid_from IS NULL OR NEW.default_valid_to IS NULL) THEN
            RAISE EXCEPTION 'Must specify either a time_frame_ident or explicit default_valid_from/to dates for a job with definition %.', definition.name;
        END IF;

        -- If time_frame_ident is provided, derive the default dates.
        IF NEW.time_frame_ident IS NOT NULL THEN
            SELECT tf.valid_from, tf.valid_to
            INTO NEW.default_valid_from, NEW.default_valid_to
            FROM public.time_frame tf
            WHERE tf.ident = NEW.time_frame_ident;

            SELECT v_snapshot || jsonb_build_object('time_frame', row_to_json(tf))
            INTO v_snapshot
            FROM public.time_frame tf WHERE tf.ident = NEW.time_frame_ident;
        END IF;

    ELSIF definition.valid_time_from = 'source_columns' THEN
        IF NEW.time_frame_ident IS NOT NULL THEN
            RAISE EXCEPTION 'Cannot specify a time_frame_ident for an import job when its definition (%) has valid_time_from="source_columns".', definition.name;
        END IF;
        IF NEW.default_valid_from IS NOT NULL OR NEW.default_valid_to IS NOT NULL THEN
            RAISE EXCEPTION 'Cannot specify default_valid_from/to for an import job when its definition (%) has valid_time_from="source_columns".', definition.name;
        END IF;
    END IF;

    -- Resolve unique_units: job override > definition default
    IF NEW.unique_units IS NULL THEN
        NEW.unique_units := COALESCE(
            definition.unique_units,
            (definition.valid_time_from = 'job_provided')
        );
    END IF;

    -- Validate: prevent job_provided + unique_units=FALSE
    IF definition.valid_time_from = 'job_provided' AND NEW.unique_units = FALSE THEN
        RAISE EXCEPTION 'Cannot set unique_units=FALSE for a job_provided import (definition %). All rows share the same time period, so duplicate units are nonsensical.', definition.name;
    END IF;

    IF NEW.default_data_source_code IS NULL AND definition.data_source_id IS NOT NULL THEN
        SELECT ds.code
        INTO NEW.default_data_source_code
        FROM public.data_source ds
        WHERE ds.id = definition.data_source_id;
    END IF;

    -- Set the user_id from the current authenticated user
    IF NEW.user_id IS NULL THEN
        NEW.user_id := auth.uid();
    END IF;

    -- Set expires_at based on created_at and definition's retention period
    NEW.expires_at := NEW.created_at + COALESCE(definition.default_retention_period, '18 months'::INTERVAL);

    -- Pre-calculate max priorities from the snapshot for weighted progress calculation
    SELECT MAX((s->>'priority')::int)
    INTO NEW.max_analysis_priority
    FROM jsonb_array_elements(v_snapshot->'import_step_list') s
    WHERE s->>'analyse_procedure' IS NOT NULL;


    NEW.definition_snapshot := v_snapshot;
    RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.import_job_clone(p_source_job_id integer, p_slug text DEFAULT NULL::text)
 RETURNS import_job
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_source_job public.import_job;
    v_new_job public.import_job;
    v_source_upload_table_exists BOOLEAN;
    v_source_columns text[];
    v_column_list text;
BEGIN
    -- 1. Get the source job record
    SELECT * INTO v_source_job FROM public.import_job WHERE id = p_source_job_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Source import job with ID % not found.', p_source_job_id;
    END IF;

    -- 2. Create a new job by inserting a copy of the old one's configuration.
    -- The BEFORE INSERT trigger `import_job_derive_trigger` will handle setting a new slug,
    -- table names, snapshot, user_id (to current user), expires_at, etc.
    INSERT INTO public.import_job (
        slug,
        description,
        note,
        time_frame_ident,
        default_valid_from,
        default_valid_to,
        default_data_source_code,
        analysis_batch_size,
        processing_batch_size,
        review,
        edit_comment,
        definition_id
    ) VALUES (
        p_slug,
        'Clone of job #' || v_source_job.id || ': ' || COALESCE(v_source_job.description, ''),
        v_source_job.note,
        v_source_job.time_frame_ident,
        CASE WHEN v_source_job.time_frame_ident IS NOT NULL THEN NULL ELSE v_source_job.default_valid_from END,
        CASE WHEN v_source_job.time_frame_ident IS NOT NULL THEN NULL ELSE v_source_job.default_valid_to END,
        v_source_job.default_data_source_code,
        v_source_job.analysis_batch_size,
        v_source_job.processing_batch_size,
        v_source_job.review,
        v_source_job.edit_comment,
        v_source_job.definition_id
    ) RETURNING * INTO v_new_job;

    -- 3. Check if the source upload table exists.
    SELECT to_regclass('public.' || v_source_job.upload_table_name) IS NOT NULL INTO v_source_upload_table_exists;

    -- 4. If it exists, copy data from old upload table to new upload table.
    -- The definition may have changed since the source job was created (for
    -- example a statistical variable disabled), so the source can have columns
    -- the new job does not map. They are kept as ignored columns
    -- (admin.import_job_keep_ignored_columns, STATBUS-545), then the rows are
    -- copied column by name.
    IF v_source_upload_table_exists THEN
        RAISE DEBUG '[Job Clone] Copying data from % to %', v_source_job.upload_table_name, v_new_job.upload_table_name;
        SELECT array_agg(c.column_name::text ORDER BY c.ordinal_position) INTO v_source_columns
        FROM information_schema.columns AS c
        WHERE c.table_schema = 'public' AND c.table_name = v_source_job.upload_table_name;
        PERFORM admin.import_job_keep_ignored_columns(v_new_job.id, v_source_columns);
        SELECT string_agg(format('%I', col), ', ') INTO v_column_list FROM unnest(v_source_columns) AS col;
        EXECUTE format('INSERT INTO public.%I (%s) SELECT %s FROM public.%I',
                       v_new_job.upload_table_name, v_column_list, v_column_list, v_source_job.upload_table_name);
        
        -- The AFTER INSERT trigger on the new upload table will automatically set the
        -- new job's state to 'upload_completed', which in turn will enqueue it for processing.
        RAISE DEBUG '[Job Clone] Data copy complete. Job % has been enqueued automatically.', v_new_job.id;
    ELSE
        RAISE DEBUG '[Job Clone] Source upload table % not found. New job % created in "waiting_for_upload" state.', v_source_job.upload_table_name, v_new_job.id;
    END IF;
    
    -- 5. Return the newly created job.
    RETURN v_new_job;
END;
$function$
;

-- The retired relative_period table no longer gets the regular-user read policy.
CREATE OR REPLACE FUNCTION admin.apply_rls_to_all_tables()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- To list all tables in public schema, run in psql:
    -- SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;
    --
    -- ########### add_rls_regular_user_can_read ###########
    PERFORM admin.add_rls_regular_user_can_read('public.activity_category'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.region'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.sector'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.legal_form'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.activity_category_standard'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.settings'::regclass);
    -- We don't need to apply the standard RLS function to activity_category_access
    -- as it has custom policies that only allow admin_user to modify it
    -- PERFORM admin.add_rls_regular_user_can_read('public.activity_category_access'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.country'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.data_source'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.tag'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.unit_size'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.power_group_type'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.legal_reorg_type'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.legal_rel_type'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.foreign_participation'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.status'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.external_ident_type'::regclass);

    PERFORM admin.add_rls_regular_user_can_read('public.person_role'::regclass);
    -- We don't need to apply the standard RLS function to region_access
    -- as it has custom policies that only allow admin_user to modify it
    -- PERFORM admin.add_rls_regular_user_can_read('public.region_access'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.stat_definition'::regclass);
    -- Is updated by the statbus worker, using authorized functions.
    PERFORM admin.add_rls_regular_user_can_read('public.timepoints'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.timesegments'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.timesegments_years'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.timeline_establishment'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.timeline_legal_unit'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.timeline_enterprise'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.statistical_unit'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.activity_category_used'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.region_used'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.sector_used'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.data_source_used'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.legal_form_used'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.country_used'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.statistical_unit_facet'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.statistical_history_facet_delta'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.statistical_history_period'::regclass);
    --
    -- ########### add_rls_regular_user_can_edit ###########
    PERFORM admin.add_rls_regular_user_can_edit('public.image'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.establishment'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.legal_unit'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.enterprise'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.power_group'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.power_root'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.external_ident'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.activity'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.contact'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.unit_notes'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.tag_for_unit'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.stat_for_unit'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.person_for_unit'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.person'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.location'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.legal_relationship'::regclass);
    --
END;
$function$
;

END;
