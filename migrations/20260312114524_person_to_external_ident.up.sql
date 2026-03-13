BEGIN;

-- ============================================================================
-- Migration E: Move person.personal_ident to external_ident system
--
-- person.personal_ident is a hardcoded single text field. Persons can have
-- multiple identifiers (national ID, passport, tax ID). All other entities
-- (ES, LU, enterprise, power_group) use external_ident + external_ident_type.
-- Person should too.
-- ============================================================================

-- ============================================================================
-- 1. Create admin.person_id_exists (same pattern as other _id_exists functions)
-- ============================================================================
CREATE OR REPLACE FUNCTION admin.person_id_exists(fk_id integer) RETURNS boolean LANGUAGE sql STABLE STRICT AS $$
    SELECT fk_id IS NULL OR EXISTS (SELECT 1 FROM public.person WHERE id = fk_id);
$$;

-- ============================================================================
-- 2. Add person_id column to external_ident
-- ============================================================================
ALTER TABLE public.external_ident ADD COLUMN person_id INTEGER
    CHECK (admin.person_id_exists(person_id));

-- ============================================================================
-- 3. Update CHECK constraint: 4 → 5 columns
-- ============================================================================
ALTER TABLE public.external_ident DROP CONSTRAINT "One and only one statistical unit id must be set";
ALTER TABLE public.external_ident ADD CONSTRAINT "One and only one statistical unit id must be set"
    CHECK (num_nonnulls(establishment_id, legal_unit_id, enterprise_id, power_group_id, person_id) = 1);

-- ============================================================================
-- 4. Update NULLS NOT DISTINCT unique index: add person_id
-- ============================================================================
DROP INDEX public.external_ident_type_unit_association_nulls_not_distinct;
CREATE UNIQUE INDEX external_ident_type_unit_association_nulls_not_distinct
    ON public.external_ident(type_id, establishment_id, legal_unit_id, enterprise_id, power_group_id, person_id)
    NULLS NOT DISTINCT;

-- ============================================================================
-- 5. Add lookup index for person_id
-- ============================================================================
CREATE INDEX external_ident_person_id_idx ON public.external_ident(person_id);

-- ============================================================================
-- 6. Add default external_ident_type for person identifiers
-- ============================================================================
INSERT INTO public.external_ident_type(code, name, priority, description, enabled)
VALUES ('person_ident', 'Person Identifier', 10,
    'Personal identification number (national ID, passport, etc.)', true);

-- ============================================================================
-- 7. Migrate existing data from person.personal_ident to external_ident
-- ============================================================================
INSERT INTO public.external_ident (type_id, person_id, ident, edit_by_user_id, edit_at)
SELECT (SELECT id FROM public.external_ident_type WHERE code = 'person_ident'),
       p.id,
       p.personal_ident,
       (SELECT id FROM auth.user LIMIT 1),  -- System user for migration
       statement_timestamp()
FROM public.person AS p
WHERE p.personal_ident IS NOT NULL;

-- ============================================================================
-- 8. Drop person.personal_ident column
-- ============================================================================
ALTER TABLE public.person DROP COLUMN personal_ident;

-- ============================================================================
-- 8b. Add edit-tracking columns and death_date to person table
--     Every other entity table has these columns. Person should match.
--     Person table currently has 0 rows, so NOT NULL is safe without defaults.
-- ============================================================================
ALTER TABLE public.person ADD COLUMN death_date DATE;
ALTER TABLE public.person ADD COLUMN edit_comment CHARACTER VARYING(512);
ALTER TABLE public.person ADD COLUMN edit_by_user_id INTEGER NOT NULL
    REFERENCES auth."user"(id) ON DELETE RESTRICT;
ALTER TABLE public.person ADD COLUMN edit_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT statement_timestamp();
CREATE INDEX ix_person_edit_by_user_id ON public.person(edit_by_user_id);

-- ============================================================================
-- 9. Update import procedure: add person_id = NULL in MERGE statements
--    The analyse_external_idents procedure hardcodes enterprise_id = NULL and
--    power_group_id = NULL in its MERGE statements. Add person_id = NULL too.
-- ============================================================================

-- Note: The import system only processes external_idents for establishments
-- and legal units. Person external_idents are managed through the person UI,
-- not through bulk import. The MERGE statements need person_id = NULL to
-- satisfy the updated CHECK constraint (5 columns, exactly 1 non-null).

-- We update the helper_process_external_idents procedure which contains the
-- MERGE statements. The changes are:
--   a) external_ident_type_active → external_ident_type_enabled (Migration D renamed it)
--   b) Add person_id = NULL in both MERGE UPDATE SET clauses

CREATE OR REPLACE PROCEDURE import.helper_process_external_idents(
    p_job_id INT,
    p_batch_seq INTEGER,
    p_step_code TEXT
)
LANGUAGE plpgsql AS $helper_process_external_idents$
DECLARE
    v_job public.import_job;
    v_data_table_name TEXT;
    v_job_mode public.import_mode;
    v_ident_data_cols JSONB;
    v_step public.import_step;
    v_col_rec RECORD;
    v_sql TEXT;
    v_unit_id_col_name TEXT;
    v_unit_type TEXT;
    v_rows_affected INT;
    v_ident_type_rec RECORD;
BEGIN
    RAISE DEBUG '[Job %] helper_process_external_idents (Batch): Starting for batch_seq % for step %', p_job_id, p_batch_seq, p_step_code;

    -- Get job details
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    v_job_mode := (v_job.definition_snapshot->'import_definition'->>'mode')::public.import_mode;

    -- Determine unit type and ID column from job mode
    IF v_job_mode = 'legal_unit' THEN
        v_unit_type := 'legal_unit';
        v_unit_id_col_name := 'legal_unit_id';
    ELSIF v_job_mode IN ('establishment_formal', 'establishment_informal') THEN
        v_unit_type := 'establishment';
        v_unit_id_col_name := 'establishment_id';
    ELSE
        RAISE DEBUG '[Job %] helper_process_external_idents: Job mode is ''%'', which does not have external identifiers processed by this step. Skipping.', p_job_id, v_job_mode;
        RETURN;
    END IF;

    -- Get relevant columns for the external_idents step from snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'external_idents';
    SELECT jsonb_agg(value) INTO v_ident_data_cols
    FROM jsonb_array_elements(v_job.definition_snapshot->'import_data_column_list') value
    WHERE (value->>'step_id')::int = v_step.id
      AND value->>'purpose' IN ('source_input', 'internal');

    IF v_ident_data_cols IS NULL OR jsonb_array_length(v_ident_data_cols) = 0 THEN
        RAISE DEBUG '[Job %] helper_process_external_idents: No external ident columns found for step. Skipping.', p_job_id;
        RETURN;
    END IF;

    -- ============================================================================
    -- Process REGULAR identifiers (single column per type, uses ident field)
    -- ============================================================================
    FOR v_ident_type_rec IN
        SELECT eit.id, eit.code, eit.shape
        FROM public.external_ident_type_enabled eit
        WHERE eit.shape = 'regular'
        ORDER BY eit.priority
    LOOP
        -- Check if we have a column for this type
        IF NOT EXISTS (
            SELECT 1 FROM jsonb_array_elements(v_ident_data_cols) value
            WHERE value->>'column_name' = v_ident_type_rec.code || '_raw'
        ) THEN
            CONTINUE;
        END IF;

        RAISE DEBUG '[Job %] helper_process_external_idents: Processing regular identifier type: %', p_job_id, v_ident_type_rec.code;

        v_sql := format(
                $SQL$
                MERGE INTO public.external_ident AS t
                USING (
                    SELECT DISTINCT ON (dt.founding_row_id, dt.%3$I)
                        dt.founding_row_id,
                        dt.%1$I AS unit_id,
                        dt.edit_by_user_id,
                        dt.edit_at,
                        dt.edit_comment,
                        %2$L::integer AS type_id,
                        dt.%3$I AS ident_value
                    FROM public.%4$I dt
                    WHERE dt.batch_seq = $1
                      AND dt.action = 'use'
                      AND dt.%1$I IS NOT NULL
                      AND NULLIF(dt.%3$I, '') IS NOT NULL
                    ORDER BY dt.founding_row_id, dt.%3$I, dt.row_id
                ) AS s
                ON (t.type_id = s.type_id AND t.ident = s.ident_value)
                WHEN MATCHED AND (
                    t.legal_unit_id IS DISTINCT FROM (CASE WHEN %5$L = 'legal_unit' THEN s.unit_id ELSE NULL END) OR
                    t.establishment_id IS DISTINCT FROM (CASE WHEN %5$L = 'establishment' THEN s.unit_id ELSE NULL END)
                ) THEN
                    UPDATE SET
                        legal_unit_id = CASE WHEN %5$L = 'legal_unit' THEN s.unit_id ELSE NULL END,
                        establishment_id = CASE WHEN %5$L = 'establishment' THEN s.unit_id ELSE NULL END,
                        enterprise_id = NULL,
                        power_group_id = NULL,
                        person_id = NULL,
                        edit_by_user_id = s.edit_by_user_id,
                        edit_at = s.edit_at,
                        edit_comment = s.edit_comment
                WHEN NOT MATCHED THEN
                    INSERT (legal_unit_id, establishment_id, type_id, ident, edit_by_user_id, edit_at, edit_comment)
                    VALUES (
                        CASE WHEN %5$L = 'legal_unit' THEN s.unit_id ELSE NULL END,
                        CASE WHEN %5$L = 'establishment' THEN s.unit_id ELSE NULL END,
                        s.type_id,
                        s.ident_value,
                        s.edit_by_user_id,
                        s.edit_at,
                        s.edit_comment
                    );
                $SQL$,
                v_unit_id_col_name,                      -- %1$I
                v_ident_type_rec.id,                    -- %2$L
                v_ident_type_rec.code || '_raw',        -- %3$I
                v_data_table_name,                      -- %4$I
                v_unit_type                             -- %5$L
            );

        RAISE DEBUG '[Job %] helper_process_external_idents: Regular MERGE SQL: %', p_job_id, v_sql;
        EXECUTE v_sql USING p_batch_seq;
        GET DIAGNOSTICS v_rows_affected = ROW_COUNT;
        RAISE DEBUG '[Job %] helper_process_external_idents: Merged % rows for regular identifier type %.', p_job_id, v_rows_affected, v_ident_type_rec.code;
    END LOOP;

    -- ============================================================================
    -- Process HIERARCHICAL identifiers (uses idents field with ltree)
    -- ============================================================================
    FOR v_ident_type_rec IN
        SELECT eit.id, eit.code, eit.shape, eit.labels
        FROM public.external_ident_type_enabled eit
        WHERE eit.shape = 'hierarchical'
          AND eit.labels IS NOT NULL
        ORDER BY eit.priority
    LOOP
        -- Check if we have the path column for this type
        IF NOT EXISTS (
            SELECT 1 FROM jsonb_array_elements(v_ident_data_cols) value
            WHERE value->>'column_name' = v_ident_type_rec.code || '_path'
        ) THEN
            CONTINUE;
        END IF;

        RAISE DEBUG '[Job %] helper_process_external_idents: Processing hierarchical identifier type: % (path column: %_path)',
            p_job_id, v_ident_type_rec.code, v_ident_type_rec.code;

        v_sql := format(
                $SQL$
                MERGE INTO public.external_ident AS t
                USING (
                    SELECT DISTINCT ON (dt.founding_row_id, dt.%3$I)
                        dt.founding_row_id,
                        dt.%1$I AS unit_id,
                        dt.edit_by_user_id,
                        dt.edit_at,
                        dt.edit_comment,
                        %2$L::integer AS type_id,
                        dt.%3$I AS idents_value
                    FROM public.%4$I dt
                    WHERE dt.batch_seq = $1
                      AND dt.action = 'use'
                      AND dt.%1$I IS NOT NULL
                      AND dt.%3$I IS NOT NULL
                    ORDER BY dt.founding_row_id, dt.%3$I, dt.row_id
                ) AS s
                ON (t.type_id = s.type_id AND t.idents = s.idents_value)
                WHEN MATCHED AND (
                    t.legal_unit_id IS DISTINCT FROM (CASE WHEN %5$L = 'legal_unit' THEN s.unit_id ELSE NULL END) OR
                    t.establishment_id IS DISTINCT FROM (CASE WHEN %5$L = 'establishment' THEN s.unit_id ELSE NULL END)
                ) THEN
                    UPDATE SET
                        legal_unit_id = CASE WHEN %5$L = 'legal_unit' THEN s.unit_id ELSE NULL END,
                        establishment_id = CASE WHEN %5$L = 'establishment' THEN s.unit_id ELSE NULL END,
                        enterprise_id = NULL,
                        power_group_id = NULL,
                        person_id = NULL,
                        edit_by_user_id = s.edit_by_user_id,
                        edit_at = s.edit_at,
                        edit_comment = s.edit_comment
                WHEN NOT MATCHED THEN
                    INSERT (legal_unit_id, establishment_id, type_id, idents, edit_by_user_id, edit_at, edit_comment)
                    VALUES (
                        CASE WHEN %5$L = 'legal_unit' THEN s.unit_id ELSE NULL END,
                        CASE WHEN %5$L = 'establishment' THEN s.unit_id ELSE NULL END,
                        s.type_id,
                        s.idents_value,
                        s.edit_by_user_id,
                        s.edit_at,
                        s.edit_comment
                    );
                $SQL$,
                v_unit_id_col_name,                       -- %1$I
                v_ident_type_rec.id,                     -- %2$L
                v_ident_type_rec.code || '_path',        -- %3$I (the ltree path column)
                v_data_table_name,                       -- %4$I
                v_unit_type                              -- %5$L
            );

        RAISE DEBUG '[Job %] helper_process_external_idents: Hierarchical MERGE SQL: %', p_job_id, v_sql;
        EXECUTE v_sql USING p_batch_seq;
        GET DIAGNOSTICS v_rows_affected = ROW_COUNT;
        RAISE DEBUG '[Job %] helper_process_external_idents: Merged % rows for hierarchical identifier type %.', p_job_id, v_rows_affected, v_ident_type_rec.code;
    END LOOP;

EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '[Job %] helper_process_external_idents: Error during batch operation: %', p_job_id, SQLERRM;
    RAISE;
END;
$helper_process_external_idents$;

-- ============================================================================
-- 10. Update reset(): add person_ident + activity_category_standard baseline
-- ============================================================================

-- Migration C's reset() already handles region_version. We now update it to:
-- Fix 2: Add person_ident to the baseline external_ident_type entries
-- Fix 3: Add activity_category_standard baseline reset in 'all' scope

CREATE OR REPLACE FUNCTION public.reset(confirmed boolean, scope reset_scope)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $reset$
DECLARE
    result JSONB := '{}'::JSONB;
    changed JSONB;
    _activity_count bigint;
    _location_count bigint;
    _contact_count bigint;
    _person_for_unit_count bigint;
    _person_count bigint;
    _tag_for_unit_count bigint;
    _stat_for_unit_count bigint;
    _external_ident_count bigint;
    _legal_relationship_count bigint;
    _power_root_count bigint;
    _establishment_count bigint;
    _legal_unit_count bigint;
    _enterprise_count bigint;
    _power_group_count bigint;
    _image_count bigint;
    _unit_notes_count bigint;
BEGIN
    IF NOT confirmed THEN
        RAISE EXCEPTION 'Action not confirmed.';
    END IF;

    -- ================================================================
    -- Scope: 'units' (and all broader scopes)
    -- ================================================================

    CASE WHEN scope IN ('units', 'data', 'getting-started', 'all') THEN
        SELECT COUNT(*) FROM public.activity INTO _activity_count;
        SELECT COUNT(*) FROM public.location INTO _location_count;
        SELECT COUNT(*) FROM public.contact INTO _contact_count;
        SELECT COUNT(*) FROM public.person_for_unit INTO _person_for_unit_count;
        SELECT COUNT(*) FROM public.person INTO _person_count;
        SELECT COUNT(*) FROM public.tag_for_unit INTO _tag_for_unit_count;
        SELECT COUNT(*) FROM public.stat_for_unit INTO _stat_for_unit_count;
        SELECT COUNT(*) FROM public.external_ident INTO _external_ident_count;
        SELECT COUNT(*) FROM public.legal_relationship INTO _legal_relationship_count;
        SELECT COUNT(*) FROM public.power_root INTO _power_root_count;
        SELECT COUNT(*) FROM public.establishment INTO _establishment_count;
        SELECT COUNT(*) FROM public.legal_unit INTO _legal_unit_count;
        SELECT COUNT(*) FROM public.enterprise INTO _enterprise_count;
        SELECT COUNT(*) FROM public.power_group INTO _power_group_count;
        SELECT COUNT(*) FROM public.image INTO _image_count;
        SELECT COUNT(*) FROM public.unit_notes INTO _unit_notes_count;

        TRUNCATE
            public.activity,
            public.location,
            public.contact,
            public.stat_for_unit,
            public.external_ident,
            public.person_for_unit,
            public.person,
            public.tag_for_unit,
            public.unit_notes,
            public.legal_relationship,
            public.power_root,
            public.establishment,
            public.legal_unit,
            public.enterprise,
            public.power_group,
            public.image,
            public.timeline_establishment,
            public.timeline_legal_unit,
            public.timeline_enterprise,
            public.timeline_power_group,
            public.timepoints,
            public.timesegments,
            public.timesegments_years,
            public.statistical_unit,
            public.statistical_unit_facet,
            public.statistical_unit_facet_dirty_partitions,
            public.statistical_history,
            public.statistical_history_facet,
            public.statistical_history_facet_partitions;

        result := result
            || jsonb_build_object('activity', jsonb_build_object('deleted_count', _activity_count))
            || jsonb_build_object('location', jsonb_build_object('deleted_count', _location_count))
            || jsonb_build_object('contact', jsonb_build_object('deleted_count', _contact_count))
            || jsonb_build_object('person_for_unit', jsonb_build_object('deleted_count', _person_for_unit_count))
            || jsonb_build_object('person', jsonb_build_object('deleted_count', _person_count))
            || jsonb_build_object('tag_for_unit', jsonb_build_object('deleted_count', _tag_for_unit_count))
            || jsonb_build_object('stat_for_unit', jsonb_build_object('deleted_count', _stat_for_unit_count))
            || jsonb_build_object('external_ident', jsonb_build_object('deleted_count', _external_ident_count))
            || jsonb_build_object('legal_relationship', jsonb_build_object('deleted_count', _legal_relationship_count))
            || jsonb_build_object('power_root', jsonb_build_object('deleted_count', _power_root_count))
            || jsonb_build_object('establishment', jsonb_build_object('deleted_count', _establishment_count))
            || jsonb_build_object('legal_unit', jsonb_build_object('deleted_count', _legal_unit_count))
            || jsonb_build_object('enterprise', jsonb_build_object('deleted_count', _enterprise_count))
            || jsonb_build_object('power_group', jsonb_build_object('deleted_count', _power_group_count))
            || jsonb_build_object('image', jsonb_build_object('deleted_count', _image_count))
            || jsonb_build_object('unit_notes', jsonb_build_object('deleted_count', _unit_notes_count));
    ELSE END CASE;

    -- ================================================================
    -- Scope: 'data' (adds import cleanup)
    -- ================================================================

    CASE WHEN scope IN ('data', 'getting-started', 'all') THEN
        WITH deleted_import_job AS (
            DELETE FROM public.import_job WHERE id > 0 RETURNING *
        )
        SELECT jsonb_build_object(
            'import_job', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_import_job)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    -- ================================================================
    -- Scope: 'getting-started' (adds config/reference cleanup)
    -- ================================================================

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_import_definition AS (
            DELETE FROM public.import_definition WHERE id > 0 RETURNING *
        )
        SELECT jsonb_build_object(
            'import_definition', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_import_definition)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_region AS (
            DELETE FROM public.region WHERE id > 0 RETURNING *
        )
        SELECT jsonb_build_object(
            'region', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_region)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_settings AS (
            DELETE FROM public.settings WHERE only_one_setting = TRUE RETURNING *
        )
        SELECT jsonb_build_object(
            'settings', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_settings)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_rv AS (
            DELETE FROM public.region_version WHERE custom RETURNING *
        ), changed_rv AS (
            UPDATE public.region_version SET enabled = TRUE
             WHERE NOT custom AND NOT enabled RETURNING *
        )
        SELECT jsonb_build_object('region_version', jsonb_build_object(
            'deleted_count', (SELECT COUNT(*) FROM deleted_rv),
            'changed_count', (SELECT COUNT(*) FROM changed_rv)
        )) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH activity_category_to_delete AS (
            SELECT to_delete.id AS id_to_delete
                 , replacement.id AS replacement_id
            FROM public.activity_category AS to_delete
            LEFT JOIN public.activity_category AS replacement
              ON to_delete.path = replacement.path
             AND NOT replacement.custom
            WHERE to_delete.custom
              AND to_delete.enabled
            ORDER BY to_delete.path
        ), updated_child AS (
            UPDATE public.activity_category AS child
               SET parent_id = to_delete.replacement_id
              FROM activity_category_to_delete AS to_delete
               WHERE to_delete.replacement_id IS NOT NULL
                 AND NOT child.custom
                 AND parent_id = to_delete.id_to_delete
            RETURNING *
        ), deleted_activity_category AS (
            DELETE FROM public.activity_category
             WHERE id in (SELECT id_to_delete FROM activity_category_to_delete)
            RETURNING *
        )
        SELECT jsonb_build_object(
            'deleted_count', (SELECT COUNT(*) FROM deleted_activity_category),
            'changed_children_count', (SELECT COUNT(*) FROM updated_child)
        ) INTO changed;

        WITH changed_activity_category AS (
            UPDATE public.activity_category
            SET enabled = TRUE
            WHERE NOT custom
              AND NOT enabled
            RETURNING *
        )
        SELECT changed || jsonb_build_object(
            'changed_count', (SELECT COUNT(*) FROM changed_activity_category)
        ) INTO changed;
        SELECT jsonb_build_object('activity_category', changed) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_sector AS (
            DELETE FROM public.sector WHERE custom RETURNING *
        ), changed_sector AS (
            UPDATE public.sector
               SET enabled = TRUE
             WHERE NOT custom
               AND NOT enabled
             RETURNING *
        )
        SELECT jsonb_build_object(
            'sector', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_sector),
                'changed_count', (SELECT COUNT(*) FROM changed_sector)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_legal_form AS (
            DELETE FROM public.legal_form WHERE custom RETURNING *
        ), changed_legal_form AS (
            UPDATE public.legal_form
               SET enabled = TRUE
             WHERE NOT custom
               AND NOT enabled
             RETURNING *
        )
        SELECT jsonb_build_object(
            'legal_form', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_legal_form),
                'changed_count', (SELECT COUNT(*) FROM changed_legal_form)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_unit_size AS (
            DELETE FROM public.unit_size WHERE custom RETURNING *
        ), changed_unit_size AS (
            UPDATE public.unit_size
               SET enabled = TRUE
             WHERE NOT custom
               AND NOT enabled
             RETURNING *
        )
        SELECT jsonb_build_object(
            'unit_size', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_unit_size),
                'changed_count', (SELECT COUNT(*) FROM changed_unit_size)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_data_source AS (
            DELETE FROM public.data_source WHERE custom RETURNING *
        ), changed_data_source AS (
            UPDATE public.data_source
               SET enabled = TRUE
             WHERE NOT custom
               AND NOT enabled
             RETURNING *
        )
        SELECT jsonb_build_object(
            'data_source', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_data_source),
                'changed_count', (SELECT COUNT(*) FROM changed_data_source)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_status AS (
            DELETE FROM public.status WHERE custom RETURNING *
        ), changed_status AS (
            UPDATE public.status
               SET enabled = TRUE
             WHERE NOT custom
               AND NOT enabled
             RETURNING *
        )
        SELECT jsonb_build_object(
            'status', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_status),
                'changed_count', (SELECT COUNT(*) FROM changed_status)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_foreign_participation AS (
            DELETE FROM public.foreign_participation WHERE custom RETURNING *
        ), changed_foreign_participation AS (
            UPDATE public.foreign_participation
               SET enabled = TRUE
             WHERE NOT custom
               AND NOT enabled
             RETURNING *
        )
        SELECT jsonb_build_object(
            'foreign_participation', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_foreign_participation),
                'changed_count', (SELECT COUNT(*) FROM changed_foreign_participation)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_legal_reorg_type AS (
            DELETE FROM public.legal_reorg_type WHERE custom RETURNING *
        ), changed_legal_reorg_type AS (
            UPDATE public.legal_reorg_type
               SET enabled = TRUE
             WHERE NOT custom
               AND NOT enabled
             RETURNING *
        )
        SELECT jsonb_build_object(
            'legal_reorg_type', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_legal_reorg_type),
                'changed_count', (SELECT COUNT(*) FROM changed_legal_reorg_type)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_power_group_type AS (
            DELETE FROM public.power_group_type WHERE custom RETURNING *
        ), changed_power_group_type AS (
            UPDATE public.power_group_type
               SET enabled = TRUE
             WHERE NOT custom
               AND NOT enabled
             RETURNING *
        )
        SELECT jsonb_build_object(
            'power_group_type', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_power_group_type),
                'changed_count', (SELECT COUNT(*) FROM changed_power_group_type)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_legal_rel_type AS (
            DELETE FROM public.legal_rel_type WHERE custom RETURNING *
        ), changed_legal_rel_type AS (
            UPDATE public.legal_rel_type
               SET enabled = TRUE
             WHERE NOT custom
               AND NOT enabled
             RETURNING *
        )
        SELECT jsonb_build_object(
            'legal_rel_type', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_legal_rel_type),
                'changed_count', (SELECT COUNT(*) FROM changed_legal_rel_type)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    -- ================================================================
    -- Scope: 'all' (adds configuration reset)
    -- ================================================================

    CASE WHEN scope IN ('all') THEN
        WITH deleted_tag AS (
            DELETE FROM public.tag WHERE custom RETURNING *
        ), changed_tag AS (
            UPDATE public.tag
               SET enabled = TRUE
             WHERE NOT custom
               AND NOT enabled
             RETURNING *
        )
        SELECT jsonb_build_object(
            'tag', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_tag),
                'changed_count', (SELECT COUNT(*) FROM changed_tag)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('all') THEN
        WITH deleted_stat_definition AS (
            DELETE FROM public.stat_definition WHERE true RETURNING *
        )
        SELECT jsonb_build_object(
            'stat_definition', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_stat_definition WHERE code NOT IN ('employees','turnover'))
            )
        ) INTO changed;
        result := result || changed;

        INSERT INTO public.stat_definition(code, type, frequency, name, description, priority, enabled)
        VALUES
            ('employees', 'int', 'yearly', 'Employees', 'The number of people receiving an official salary with government reporting.', 1, true),
            ('turnover', 'float', 'yearly', 'Turnover', 'The amount (Local Currency)', 2, true);
    ELSE END CASE;

    CASE WHEN scope IN ('all') THEN
        WITH deleted_external_ident_type AS (
            DELETE FROM public.external_ident_type WHERE true RETURNING *
        )
        SELECT jsonb_build_object(
            'external_ident_type', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_external_ident_type WHERE code NOT IN ('stat_ident','tax_ident','person_ident'))
            )
        ) INTO changed;
        result := result || changed;

        -- Fix 2: Include person_ident in baseline entries
        INSERT INTO public.external_ident_type(code, name, priority, description, enabled)
        VALUES
            ('tax_ident', 'Tax Identifier', 1, 'Stable and country unique identifier used for tax reporting.', true),
            ('stat_ident', 'Statistical Identifier', 2, 'Stable identifier generated by Statbus', true),
            ('person_ident', 'Person Identifier', 10, 'Personal identification number (national ID, passport, etc.)', true);
    ELSE END CASE;

    -- activity_category_standard is system seed data (isic_v4, nace_v2.1) and must
    -- never be deleted by reset(). Custom activity_categories are already handled
    -- by the 'getting-started' scope block above.

    RETURN result;
END;
$reset$;

END;
