-- Down Migration 20261127104238: quality row checks on statistical_unit and relation checks in their own tables
BEGIN;

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
    PERFORM admin.add_rls_regular_user_can_read('public.quality_finding'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.quality_check_switched_on'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.quality_check_catalogue'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.quality_establishment_activity_differs'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.quality_legal_unit_establishment_stat'::regclass);
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
$function$;

CREATE OR REPLACE FUNCTION public.reset(confirmed boolean, scope reset_scope)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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

    -- Scope: units (and every broader scope): the statistical units and the import jobs that made them
    -- ================================================================

    CASE WHEN scope IN ('units', 'getting-started', 'customisation') THEN
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

        -- statistical_unit is emptied together with public.quality_finding, which
        -- references it by a NOT ENFORCED foreign key: TRUNCATE refuses such a key without CASCADE,
        -- even with both tables listed. CASCADE is kept to this statement so that a new enforced
        -- key to any table in the list below still stops reset instead of emptying its table.
        TRUNCATE public.statistical_unit, public.quality_finding CASCADE;

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
            public.quality_establishment_activity_differs,
            public.quality_legal_unit_establishment_stat,
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
            public.statistical_unit_facet,
            public.statistical_unit_facet_staging,
            public.statistical_unit_facet_dirty_hash_slots,
            public.statistical_history_facet_delta,
            public.statistical_history_facet_delta_staging,
            public.statistical_history_period;

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

    CASE WHEN scope IN ('units', 'getting-started', 'customisation') THEN
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
    -- Scope: getting-started: the steps of the Getting started menu
    -- ================================================================

    CASE WHEN scope IN ('getting-started', 'customisation') THEN
        -- Transient: delete custom definitions before data_source due to RESTRICT FK. See doc/data-model.md
        WITH deleted_import_definition AS (
            DELETE FROM public.import_definition WHERE custom RETURNING *
        )
        SELECT jsonb_build_object(
            'import_definition', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_import_definition)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'customisation') THEN
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

    CASE WHEN scope IN ('getting-started', 'customisation') THEN
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

    CASE WHEN scope IN ('getting-started', 'customisation') THEN
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

    CASE WHEN scope IN ('getting-started', 'customisation') THEN
        WITH activity_category_to_delete AS (
            SELECT to_delete.id AS id_to_delete
                 , replacement.id AS replacement_id
            FROM public.activity_category AS to_delete
            LEFT JOIN public.activity_category AS replacement
              ON to_delete.path = replacement.path
             AND to_delete.standard_id = replacement.standard_id
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

    CASE WHEN scope IN ('getting-started', 'customisation') THEN
        -- The activity category standards as shipped; restoring code_pattern
        -- re-derives the codes (trigger recalculate_activity_category_codes).
        WITH restored AS (
            UPDATE public.activity_category_standard AS t
               SET name = fd.name, description = fd.description, code_pattern = fd.code_pattern,
                   enabled = fd.enabled, lasts_to = fd.lasts_to
              FROM public.activity_category_standard_factory_default AS fd
             WHERE t.code = fd.code
               AND (t.name IS DISTINCT FROM fd.name OR t.description IS DISTINCT FROM fd.description
                    OR t.code_pattern IS DISTINCT FROM fd.code_pattern OR t.enabled IS DISTINCT FROM fd.enabled
                    OR t.lasts_to IS DISTINCT FROM fd.lasts_to)
            RETURNING 1
        )
        SELECT jsonb_build_object('activity_category_standard', jsonb_build_object(
            'changed_count', (SELECT count(*) FROM restored)
        )) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'customisation') THEN
        -- sector: custom rows removed; system rows restored as shipped
        -- (public.sector_factory_default): edited ones updated, missing ones added.
        WITH deleted AS (
            DELETE FROM public.sector WHERE custom RETURNING 1
        ), restored AS (
            UPDATE public.sector AS t
               SET name = fd.name, enabled = TRUE
              FROM public.sector_factory_default AS fd
             WHERE NOT t.custom AND t.path = fd.path
               AND (NOT t.enabled OR t.name IS DISTINCT FROM fd.name)
            RETURNING 1
        ), added AS (
            INSERT INTO public.sector(path, name, enabled, custom)
            SELECT fd.path, fd.name, TRUE, FALSE
              FROM public.sector_factory_default AS fd
             WHERE NOT EXISTS (SELECT 1 FROM public.sector AS t WHERE t.path = fd.path AND NOT t.custom)
            RETURNING 1
        )
        SELECT jsonb_build_object('sector', jsonb_build_object(
            'deleted_count', (SELECT count(*) FROM deleted),
            'changed_count', (SELECT count(*) FROM restored),
            'added_count', (SELECT count(*) FROM added)
        )) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'customisation') THEN
        -- legal_form: custom rows removed; system rows restored as shipped
        -- (public.legal_form_factory_default): edited ones updated, missing ones added.
        WITH deleted AS (
            DELETE FROM public.legal_form WHERE custom RETURNING 1
        ), restored AS (
            UPDATE public.legal_form AS t
               SET name = fd.name, enabled = TRUE
              FROM public.legal_form_factory_default AS fd
             WHERE NOT t.custom AND t.code = fd.code
               AND (NOT t.enabled OR t.name IS DISTINCT FROM fd.name)
            RETURNING 1
        ), added AS (
            INSERT INTO public.legal_form(code, name, enabled, custom)
            SELECT fd.code, fd.name, TRUE, FALSE
              FROM public.legal_form_factory_default AS fd
             WHERE NOT EXISTS (SELECT 1 FROM public.legal_form AS t WHERE t.code = fd.code AND NOT t.custom)
            RETURNING 1
        )
        SELECT jsonb_build_object('legal_form', jsonb_build_object(
            'deleted_count', (SELECT count(*) FROM deleted),
            'changed_count', (SELECT count(*) FROM restored),
            'added_count', (SELECT count(*) FROM added)
        )) INTO changed;
        result := result || changed;
    ELSE END CASE;

    -- ================================================================
    -- Scope: customisation: the /admin Customisation section restored to
    -- its factory defaults. Users are never touched.
    -- ================================================================

    CASE WHEN scope = 'customisation' THEN
        -- unit_size: custom rows removed; system rows restored as shipped
        -- (public.unit_size_factory_default): edited ones updated, missing ones added.
        WITH deleted AS (
            DELETE FROM public.unit_size WHERE custom RETURNING 1
        ), restored AS (
            UPDATE public.unit_size AS t
               SET name = fd.name, enabled = TRUE
              FROM public.unit_size_factory_default AS fd
             WHERE NOT t.custom AND t.code = fd.code
               AND (NOT t.enabled OR t.name IS DISTINCT FROM fd.name)
            RETURNING 1
        ), added AS (
            INSERT INTO public.unit_size(code, name, enabled, custom)
            SELECT fd.code, fd.name, TRUE, FALSE
              FROM public.unit_size_factory_default AS fd
             WHERE NOT EXISTS (SELECT 1 FROM public.unit_size AS t WHERE t.code = fd.code AND NOT t.custom)
            RETURNING 1
        )
        SELECT jsonb_build_object('unit_size', jsonb_build_object(
            'deleted_count', (SELECT count(*) FROM deleted),
            'changed_count', (SELECT count(*) FROM restored),
            'added_count', (SELECT count(*) FROM added)
        )) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope = 'customisation' THEN
        -- data_source: custom rows removed; system rows restored as shipped
        -- (public.data_source_factory_default): edited ones updated, missing ones added.
        WITH deleted AS (
            DELETE FROM public.data_source WHERE custom RETURNING 1
        ), restored AS (
            UPDATE public.data_source AS t
               SET name = fd.name, enabled = TRUE
              FROM public.data_source_factory_default AS fd
             WHERE NOT t.custom AND t.code = fd.code
               AND (NOT t.enabled OR t.name IS DISTINCT FROM fd.name)
            RETURNING 1
        ), added AS (
            INSERT INTO public.data_source(code, name, enabled, custom)
            SELECT fd.code, fd.name, TRUE, FALSE
              FROM public.data_source_factory_default AS fd
             WHERE NOT EXISTS (SELECT 1 FROM public.data_source AS t WHERE t.code = fd.code AND NOT t.custom)
            RETURNING 1
        )
        SELECT jsonb_build_object('data_source', jsonb_build_object(
            'deleted_count', (SELECT count(*) FROM deleted),
            'changed_count', (SELECT count(*) FROM restored),
            'added_count', (SELECT count(*) FROM added)
        )) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope = 'customisation' THEN
        -- foreign_participation: custom rows removed; system rows restored as shipped
        -- (public.foreign_participation_factory_default): edited ones updated, missing ones added.
        WITH deleted AS (
            DELETE FROM public.foreign_participation WHERE custom RETURNING 1
        ), restored AS (
            UPDATE public.foreign_participation AS t
               SET name = fd.name, enabled = TRUE
              FROM public.foreign_participation_factory_default AS fd
             WHERE NOT t.custom AND t.code = fd.code
               AND (NOT t.enabled OR t.name IS DISTINCT FROM fd.name)
            RETURNING 1
        ), added AS (
            INSERT INTO public.foreign_participation(code, name, enabled, custom)
            SELECT fd.code, fd.name, TRUE, FALSE
              FROM public.foreign_participation_factory_default AS fd
             WHERE NOT EXISTS (SELECT 1 FROM public.foreign_participation AS t WHERE t.code = fd.code AND NOT t.custom)
            RETURNING 1
        )
        SELECT jsonb_build_object('foreign_participation', jsonb_build_object(
            'deleted_count', (SELECT count(*) FROM deleted),
            'changed_count', (SELECT count(*) FROM restored),
            'added_count', (SELECT count(*) FROM added)
        )) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope = 'customisation' THEN
        -- power_group_type: custom rows removed; system rows restored as shipped
        -- (public.power_group_type_factory_default): edited ones updated, missing ones added.
        WITH deleted AS (
            DELETE FROM public.power_group_type WHERE custom RETURNING 1
        ), restored AS (
            UPDATE public.power_group_type AS t
               SET name = fd.name, enabled = TRUE
              FROM public.power_group_type_factory_default AS fd
             WHERE NOT t.custom AND t.code = fd.code
               AND (NOT t.enabled OR t.name IS DISTINCT FROM fd.name)
            RETURNING 1
        ), added AS (
            INSERT INTO public.power_group_type(code, name, enabled, custom)
            SELECT fd.code, fd.name, TRUE, FALSE
              FROM public.power_group_type_factory_default AS fd
             WHERE NOT EXISTS (SELECT 1 FROM public.power_group_type AS t WHERE t.code = fd.code AND NOT t.custom)
            RETURNING 1
        )
        SELECT jsonb_build_object('power_group_type', jsonb_build_object(
            'deleted_count', (SELECT count(*) FROM deleted),
            'changed_count', (SELECT count(*) FROM restored),
            'added_count', (SELECT count(*) FROM added)
        )) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope = 'customisation' THEN
        -- legal_reorg_type: custom rows removed; system rows restored as shipped
        -- (public.legal_reorg_type_factory_default): edited ones updated, missing ones added.
        WITH deleted AS (
            DELETE FROM public.legal_reorg_type WHERE custom RETURNING 1
        ), restored AS (
            UPDATE public.legal_reorg_type AS t
               SET name = fd.name, description = fd.description, enabled = TRUE
              FROM public.legal_reorg_type_factory_default AS fd
             WHERE NOT t.custom AND t.code = fd.code
               AND (NOT t.enabled OR t.name IS DISTINCT FROM fd.name OR t.description IS DISTINCT FROM fd.description)
            RETURNING 1
        ), added AS (
            INSERT INTO public.legal_reorg_type(code, name, description, enabled, custom)
            SELECT fd.code, fd.name, fd.description, TRUE, FALSE
              FROM public.legal_reorg_type_factory_default AS fd
             WHERE NOT EXISTS (SELECT 1 FROM public.legal_reorg_type AS t WHERE t.code = fd.code AND NOT t.custom)
            RETURNING 1
        )
        SELECT jsonb_build_object('legal_reorg_type', jsonb_build_object(
            'deleted_count', (SELECT count(*) FROM deleted),
            'changed_count', (SELECT count(*) FROM restored),
            'added_count', (SELECT count(*) FROM added)
        )) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope = 'customisation' THEN
        -- legal_rel_type: custom rows removed; system rows restored as shipped
        -- (public.legal_rel_type_factory_default): edited ones updated, missing ones added.
        WITH deleted AS (
            DELETE FROM public.legal_rel_type WHERE custom RETURNING 1
        ), restored AS (
            UPDATE public.legal_rel_type AS t
               SET name = fd.name, description = fd.description, primary_influencer_only = fd.primary_influencer_only, enabled = TRUE
              FROM public.legal_rel_type_factory_default AS fd
             WHERE NOT t.custom AND t.code = fd.code
               AND (NOT t.enabled OR t.name IS DISTINCT FROM fd.name OR t.description IS DISTINCT FROM fd.description OR t.primary_influencer_only IS DISTINCT FROM fd.primary_influencer_only)
            RETURNING 1
        ), added AS (
            INSERT INTO public.legal_rel_type(code, name, description, primary_influencer_only, enabled, custom)
            SELECT fd.code, fd.name, fd.description, fd.primary_influencer_only, TRUE, FALSE
              FROM public.legal_rel_type_factory_default AS fd
             WHERE NOT EXISTS (SELECT 1 FROM public.legal_rel_type AS t WHERE t.code = fd.code AND NOT t.custom)
            RETURNING 1
        )
        SELECT jsonb_build_object('legal_rel_type', jsonb_build_object(
            'deleted_count', (SELECT count(*) FROM deleted),
            'changed_count', (SELECT count(*) FROM restored),
            'added_count', (SELECT count(*) FROM added)
        )) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope = 'customisation' THEN
        -- status: custom rows removed, system rows restored as shipped.
        WITH deleted AS (
            DELETE FROM public.status WHERE custom RETURNING 1
        ), restored AS (
            UPDATE public.status AS t
               SET name = fd.name, assigned_by_default = fd.assigned_by_default,
                   used_for_counting = fd.used_for_counting, priority = fd.priority, enabled = TRUE
              FROM public.status_factory_default AS fd
             WHERE NOT t.custom AND t.code = fd.code
               AND (NOT t.enabled OR t.name IS DISTINCT FROM fd.name
                    OR t.assigned_by_default IS DISTINCT FROM fd.assigned_by_default
                    OR t.used_for_counting IS DISTINCT FROM fd.used_for_counting
                    OR t.priority IS DISTINCT FROM fd.priority)
            RETURNING 1
        ), added AS (
            INSERT INTO public.status(code, name, assigned_by_default, used_for_counting, priority, enabled, custom)
            SELECT fd.code, fd.name, fd.assigned_by_default, fd.used_for_counting, fd.priority, TRUE, FALSE
              FROM public.status_factory_default AS fd
             WHERE NOT EXISTS (SELECT 1 FROM public.status AS t WHERE t.code = fd.code AND NOT t.custom)
            RETURNING 1
        )
        SELECT jsonb_build_object('status', jsonb_build_object(
            'deleted_count', (SELECT count(*) FROM deleted),
            'changed_count', (SELECT count(*) FROM restored),
            'added_count', (SELECT count(*) FROM added)
        )) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope = 'customisation' THEN
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

    CASE WHEN scope = 'customisation' THEN
        -- stat_definition: rows not shipped removed; shipped rows restored as shipped
        -- (public.stat_definition_factory_default): edited ones updated, missing ones added.
        WITH deleted AS (
            DELETE FROM public.stat_definition AS t
             WHERE NOT EXISTS (SELECT 1 FROM public.stat_definition_factory_default AS fd WHERE fd.code = t.code)
            RETURNING 1
        ), restored AS (
            UPDATE public.stat_definition AS t
               SET type = fd.type, frequency = fd.frequency, name = fd.name, description = fd.description, priority = fd.priority, enabled = fd.enabled
              FROM public.stat_definition_factory_default AS fd
             WHERE t.code = fd.code AND (t.type IS DISTINCT FROM fd.type OR t.frequency IS DISTINCT FROM fd.frequency OR t.name IS DISTINCT FROM fd.name OR t.description IS DISTINCT FROM fd.description OR t.priority IS DISTINCT FROM fd.priority OR t.enabled IS DISTINCT FROM fd.enabled)
            RETURNING 1
        ), added AS (
            INSERT INTO public.stat_definition(code, type, frequency, name, description, priority, enabled)
            SELECT fd.code, fd.type, fd.frequency, fd.name, fd.description, fd.priority, fd.enabled
              FROM public.stat_definition_factory_default AS fd
             WHERE NOT EXISTS (SELECT 1 FROM public.stat_definition AS t WHERE t.code = fd.code)
            RETURNING 1
        )
        SELECT jsonb_build_object('stat_definition', jsonb_build_object(
            'deleted_count', (SELECT count(*) FROM deleted),
            'changed_count', (SELECT count(*) FROM restored),
            'added_count', (SELECT count(*) FROM added)
        )) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope = 'customisation' THEN
        -- external_ident_type: rows not shipped removed; shipped rows restored as shipped
        -- (public.external_ident_type_factory_default): edited ones updated, missing ones added.
        WITH deleted AS (
            DELETE FROM public.external_ident_type AS t
             WHERE NOT EXISTS (SELECT 1 FROM public.external_ident_type_factory_default AS fd WHERE fd.code = t.code)
            RETURNING 1
        ), restored AS (
            UPDATE public.external_ident_type AS t
               SET name = fd.name, description = fd.description, priority = fd.priority, enabled = fd.enabled
              FROM public.external_ident_type_factory_default AS fd
             WHERE t.code = fd.code AND (t.name IS DISTINCT FROM fd.name OR t.description IS DISTINCT FROM fd.description OR t.priority IS DISTINCT FROM fd.priority OR t.enabled IS DISTINCT FROM fd.enabled)
            RETURNING 1
        ), added AS (
            INSERT INTO public.external_ident_type(code, name, description, priority, enabled)
            SELECT fd.code, fd.name, fd.description, fd.priority, fd.enabled
              FROM public.external_ident_type_factory_default AS fd
             WHERE NOT EXISTS (SELECT 1 FROM public.external_ident_type AS t WHERE t.code = fd.code)
            RETURNING 1
        )
        SELECT jsonb_build_object('external_ident_type', jsonb_build_object(
            'deleted_count', (SELECT count(*) FROM deleted),
            'changed_count', (SELECT count(*) FROM restored),
            'added_count', (SELECT count(*) FROM added)
        )) INTO changed;
        result := result || changed;
    ELSE END CASE;

    -- public.activity_category_standard rows are never deleted: they are the
    -- system's standards, restored above to their factory defaults.

    CASE WHEN scope = 'customisation' THEN
        -- quality_check_switched_on: the starting set again, as shipped (public.quality_check_starting_set).
        WITH deleted AS (
            DELETE FROM public.quality_check_switched_on WHERE true -- every row: the starting set is inserted below
            RETURNING 1
        )
        SELECT jsonb_build_object('deleted_count', count(*)) FROM deleted INTO changed;
        WITH inserted AS (
            INSERT INTO public.quality_check_switched_on (rule, stat_definition_id)
            SELECT s.rule, NULL FROM public.quality_check_starting_set() AS s(rule)
            RETURNING 1
        )
        SELECT jsonb_build_object('quality_check_switched_on',
                   changed || jsonb_build_object('inserted_count', count(*)))
        FROM inserted INTO changed;
        result := result || changed;
    ELSE END CASE;

    RETURN result;
END;
$function$;

CREATE OR REPLACE PROCEDURE public.statistical_unit_refresh(IN p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange, IN p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange, IN p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange, IN p_power_group_id_ranges int4multirange DEFAULT NULL::int4multirange)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_batch_size INT := 262144;
    v_min_id int; v_max_id int; v_start_id int; v_end_id int;
    v_batch_num INT; v_total_units INT;
    v_batch_start_time timestamptz; v_batch_duration_ms numeric; v_batch_speed numeric; v_current_batch_size int;
    v_is_partial_refresh BOOLEAN;
    v_col_list TEXT;
BEGIN
    v_is_partial_refresh := (p_establishment_id_ranges IS NOT NULL
                            OR p_legal_unit_id_ranges IS NOT NULL
                            OR p_enterprise_id_ranges IS NOT NULL
                            OR p_power_group_id_ranges IS NOT NULL);

    -- Column list used for all INSERT statements (excludes GENERATED valid_range)
    v_col_list := 'unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
        primary_activity_category_id, primary_activity_category_path, primary_activity_category_code,
        secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code,
        activity_category_paths, sector_id, sector_path, sector_code, sector_name,
        data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name,
        physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace,
        physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2,
        physical_latitude, physical_longitude, physical_altitude, domestic,
        postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace,
        postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2,
        postal_latitude, postal_longitude, postal_altitude,
        web_address, email_address, phone_number, landline, mobile_number, fax_number,
        unit_size_id, unit_size_code, status_id, status_code, used_for_counting,
        last_edit_comment, last_edit_by_user_id, last_edit_at, has_legal_unit,
        related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
        related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
        related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
        stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths';

    IF NOT v_is_partial_refresh THEN
        ANALYZE public.timeline_establishment, public.timeline_legal_unit, public.timeline_enterprise, public.timeline_power_group;
        CREATE TEMP TABLE statistical_unit_new (LIKE public.statistical_unit) ON COMMIT DROP;
        ALTER TABLE statistical_unit_new DROP COLUMN IF EXISTS valid_range;

        -- Establishments
        v_batch_num := 0;
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = 'establishment';
        RAISE DEBUG 'Refreshing statistical units for % establishments...', v_total_units;
        IF v_min_id IS NOT NULL THEN FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_num := v_batch_num + 1; v_start_id := i; v_end_id := i + v_batch_size - 1;
            EXECUTE format('INSERT INTO statistical_unit_new (%s) SELECT %s FROM public.statistical_unit_def WHERE unit_type = %L AND unit_id BETWEEN %s AND %s', v_col_list, v_col_list, 'establishment', v_start_id, v_end_id);
        END LOOP; END IF;

        -- Legal Units
        v_batch_num := 0;
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = 'legal_unit';
        RAISE DEBUG 'Refreshing statistical units for % legal units...', v_total_units;
        IF v_min_id IS NOT NULL THEN FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_num := v_batch_num + 1; v_start_id := i; v_end_id := i + v_batch_size - 1;
            EXECUTE format('INSERT INTO statistical_unit_new (%s) SELECT %s FROM public.statistical_unit_def WHERE unit_type = %L AND unit_id BETWEEN %s AND %s', v_col_list, v_col_list, 'legal_unit', v_start_id, v_end_id);
        END LOOP; END IF;

        -- Enterprises
        v_batch_num := 0;
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = 'enterprise';
        RAISE DEBUG 'Refreshing statistical units for % enterprises...', v_total_units;
        IF v_min_id IS NOT NULL THEN FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_num := v_batch_num + 1; v_start_id := i; v_end_id := i + v_batch_size - 1;
            EXECUTE format('INSERT INTO statistical_unit_new (%s) SELECT %s FROM public.statistical_unit_def WHERE unit_type = %L AND unit_id BETWEEN %s AND %s', v_col_list, v_col_list, 'enterprise', v_start_id, v_end_id);
        END LOOP; END IF;

        -- Power Groups
        v_batch_num := 0;
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = 'power_group';
        RAISE DEBUG 'Refreshing statistical units for % power groups...', v_total_units;
        IF v_min_id IS NOT NULL THEN FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_num := v_batch_num + 1; v_start_id := i; v_end_id := i + v_batch_size - 1;
            EXECUTE format('INSERT INTO statistical_unit_new (%s) SELECT %s FROM public.statistical_unit_def WHERE unit_type = %L AND unit_id BETWEEN %s AND %s', v_col_list, v_col_list, 'power_group', v_start_id, v_end_id);
        END LOOP; END IF;

        -- quality_finding points at the rows replaced here and is refilled by the next
        -- worker.derive_quality. It references statistical_unit by a NOT ENFORCED foreign
        -- key, which TRUNCATE refuses without CASCADE even with both tables listed.
        TRUNCATE public.statistical_unit, public.quality_finding CASCADE;
        EXECUTE format('INSERT INTO public.statistical_unit (%s) SELECT %s FROM statistical_unit_new', v_col_list, v_col_list);
        ANALYZE public.statistical_unit;
    ELSE
        -- Partial refresh: Write to staging table
        IF p_establishment_id_ranges IS NOT NULL THEN
            DELETE FROM public.statistical_unit_staging WHERE unit_type = 'establishment' AND unit_id = ANY(public.int4multirange_to_array(p_establishment_id_ranges));
            EXECUTE format('INSERT INTO public.statistical_unit_staging (%s) SELECT %s FROM import.get_statistical_unit_data_partial(%L, %L::int4multirange)', v_col_list, v_col_list, 'establishment', p_establishment_id_ranges::text);
        END IF;
        IF p_legal_unit_id_ranges IS NOT NULL THEN
            DELETE FROM public.statistical_unit_staging WHERE unit_type = 'legal_unit' AND unit_id = ANY(public.int4multirange_to_array(p_legal_unit_id_ranges));
            EXECUTE format('INSERT INTO public.statistical_unit_staging (%s) SELECT %s FROM import.get_statistical_unit_data_partial(%L, %L::int4multirange)', v_col_list, v_col_list, 'legal_unit', p_legal_unit_id_ranges::text);
        END IF;
        IF p_enterprise_id_ranges IS NOT NULL THEN
            DELETE FROM public.statistical_unit_staging WHERE unit_type = 'enterprise' AND unit_id = ANY(public.int4multirange_to_array(p_enterprise_id_ranges));
            EXECUTE format('INSERT INTO public.statistical_unit_staging (%s) SELECT %s FROM import.get_statistical_unit_data_partial(%L, %L::int4multirange)', v_col_list, v_col_list, 'enterprise', p_enterprise_id_ranges::text);
        END IF;
        IF p_power_group_id_ranges IS NOT NULL THEN
            DELETE FROM public.statistical_unit_staging WHERE unit_type = 'power_group' AND unit_id = ANY(public.int4multirange_to_array(p_power_group_id_ranges));
            EXECUTE format('INSERT INTO public.statistical_unit_staging (%s) SELECT %s FROM import.get_statistical_unit_data_partial(%L, %L::int4multirange)', v_col_list, v_col_list, 'power_group', p_power_group_id_ranges::text);
        END IF;
    END IF;
END;
$procedure$;

DROP FUNCTION public.quality_check_count(date);
DROP FUNCTION public.statistical_unit_quality(integer, date);
DROP FUNCTION public.in_use(public.quality_check);

-- ######## the catalogue back under its part 1 name, the switches back in their table ########
CREATE TEMP TABLE quality_switched_on_down ON COMMIT DROP AS
SELECT rule, stat_definition_id FROM public.quality_check WHERE switched_on;
ALTER TABLE public.quality_check DROP COLUMN switched_on;
ALTER POLICY quality_check_admin_user_manage ON public.quality_check RENAME TO quality_check_catalogue_admin_user_manage;
ALTER POLICY quality_check_authenticated_read ON public.quality_check RENAME TO quality_check_catalogue_authenticated_read;
ALTER POLICY quality_check_regular_user_read ON public.quality_check RENAME TO quality_check_catalogue_regular_user_read;
ALTER TABLE public.quality_check RENAME CONSTRAINT quality_check_pkey TO quality_check_catalogue_pkey;
ALTER TABLE public.quality_check RENAME CONSTRAINT quality_check_rule_variable_key TO quality_check_catalogue_rule_variable_key;
ALTER TABLE public.quality_check RENAME CONSTRAINT quality_check_id_variable_key TO quality_check_catalogue_id_variable_key;
ALTER TABLE public.quality_check RENAME CONSTRAINT quality_check_variable_matches_rule TO quality_check_catalogue_variable_matches_rule;
ALTER TABLE public.quality_check RENAME CONSTRAINT quality_check_kind_matches_rule TO quality_check_catalogue_kind_matches_rule;
ALTER TABLE public.quality_check RENAME CONSTRAINT quality_check_stat_definition_id_fkey TO quality_check_catalogue_stat_definition_id_fkey;
ALTER TABLE public.quality_check RENAME CONSTRAINT quality_check_id_not_null TO quality_check_catalogue_id_not_null;
ALTER TABLE public.quality_check RENAME CONSTRAINT quality_check_rule_not_null TO quality_check_catalogue_rule_not_null;
ALTER TABLE public.quality_check RENAME CONSTRAINT quality_check_kind_not_null TO quality_check_catalogue_kind_not_null;
ALTER TABLE public.quality_check RENAME CONSTRAINT quality_check_priority_not_null TO quality_check_catalogue_priority_not_null;
ALTER SEQUENCE public.quality_check_id_seq RENAME TO quality_check_catalogue_id_seq;
ALTER TABLE public.quality_check RENAME TO quality_check_catalogue;
COMMENT ON TABLE public.quality_check_catalogue IS
  'Every data-quality check of this installation with its integer id (h9mhxe): each rule that is not per variable once, with a fixed id (1 missing_region, 2 missing_activity_category, 3 missing_physical_location, 4 establishment_activity_differs, 7 secondary_activity_equals_primary), and each per-variable rule once per summed variable (stat_definition of type int or float), with an id from 101 up given when the variable is created and kept by the stat_definition lifecycle callback (public.quality_check_catalogue_generate / _cleanup). The id is what findings store (an int[] on statistical_unit for row checks, check_id in the relation tables); it is never reused, so a stored id always names the same check. Part 2 of h9mhxe replaces the public.quality_check view with this table under that name.';
COMMENT ON CONSTRAINT quality_check_catalogue_rule_variable_key ON public.quality_check_catalogue IS
  'A check is a rule and its variable (NULL counting as a value): it is in the catalogue once.';
COMMENT ON CONSTRAINT quality_check_catalogue_id_variable_key ON public.quality_check_catalogue IS
  'Target of public.quality_legal_unit_establishment_stat''s (check_id, stat_definition_id) foreign key, so a comparison''s variable is its check''s variable.';
COMMENT ON CONSTRAINT quality_check_catalogue_variable_matches_rule ON public.quality_check_catalogue IS
  'A per-variable check names its variable and every other check names none (public.quality_rule_per_stat).';
COMMENT ON CONSTRAINT quality_check_catalogue_kind_matches_rule ON public.quality_check_catalogue IS
  'A check''s kind is its rule''s kind (public.quality_rule_kind).';

CREATE OR REPLACE PROCEDURE public.quality_check_catalogue_generate()
 LANGUAGE plpgsql
AS $procedure$
BEGIN
    -- One check per per-variable rule and summed variable; an existing check keeps its id and
    -- follows its variable's priority. Ids come in rule then variable order, so a replay gives
    -- the same ids. Only missing checks are inserted: an INSERT ... ON CONFLICT would draw an id
    -- for every existing check on every call.
    UPDATE public.quality_check_catalogue AS qc
    SET priority = array_position(enum_range(NULL::public.quality_rule), qc.rule) * 1000 + sd.priority
    FROM public.stat_definition AS sd
    WHERE qc.stat_definition_id = sd.id
      AND qc.priority <> array_position(enum_range(NULL::public.quality_rule), qc.rule) * 1000 + sd.priority;

    INSERT INTO public.quality_check_catalogue (rule, stat_definition_id, kind, priority)
    SELECT r.rule, sd.id, public.quality_rule_kind(r.rule),
           array_position(enum_range(NULL::public.quality_rule), r.rule) * 1000 + sd.priority
    FROM unnest(enum_range(NULL::public.quality_rule)) AS r(rule)
    JOIN public.stat_definition AS sd ON sd.type IN ('int', 'float')
    WHERE public.quality_rule_per_stat(r.rule)
      AND NOT EXISTS (
          SELECT FROM public.quality_check_catalogue AS qc
          WHERE qc.rule = r.rule AND qc.stat_definition_id = sd.id)
    ORDER BY r.rule, sd.priority, sd.id;
END;
$procedure$;

CREATE OR REPLACE PROCEDURE public.quality_check_catalogue_cleanup()
 LANGUAGE plpgsql
AS $procedure$
BEGIN
    -- A deleted variable's checks went with it (ON DELETE CASCADE); a variable that is no longer
    -- summed loses its checks here.
    DELETE FROM public.quality_check_catalogue AS qc
    USING public.stat_definition AS sd
    WHERE qc.stat_definition_id = sd.id
      AND sd.type NOT IN ('int', 'float');
END;
$procedure$;

-- ######## relation tables back to part 1: empty, no statistical_unit key ########
CREATE OR REPLACE PROCEDURE worker.derive_quality(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
    v_task_id bigint;
    v_hash_partition_size integer := GREATEST(1, 16384 / public.get_partition_count_target());
    -- A full run: one range per analytics worker, so each does one large pass (fewer tasks than the
    -- small partitions, which cost a task's start and commit each).
    v_full_partition_size integer := 16384 / GREATEST(1, (SELECT q.default_concurrency FROM worker.queue_registry AS q WHERE q.queue = 'analytics'));
    v_full boolean;
    v_hash_partition int4range;
    v_child_count integer := 0;
BEGIN
    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY id DESC LIMIT 1;

    -- Every partition on a full recalculation (valid_from -infinity and valid_until infinity, see
    -- worker.enqueue_derive_statistical_unit_all; a full statistical_unit refresh empties
    -- quality_finding). Otherwise the partitions holding a changed unit: the cycle's changed units'
    -- hash slots, recorded by worker.derive_statistical_unit and cleared by
    -- worker.statistical_history_facet_delta_reduce after this step.
    v_full := v_valid_from = '-infinity'::date AND v_valid_until = 'infinity'::date;

    FOR v_hash_partition IN
        SELECT int4range(p.start, LEAST(p.start + v_full_partition_size, 16384))
        FROM generate_series(0, 16383, v_full_partition_size) AS p(start)
        WHERE v_full
        UNION
        SELECT int4range((d.dirty_hash_slot / v_hash_partition_size) * v_hash_partition_size,
                         LEAST((d.dirty_hash_slot / v_hash_partition_size) * v_hash_partition_size + v_hash_partition_size, 16384))
        FROM public.statistical_unit_facet_dirty_hash_slots AS d
        WHERE NOT v_full
        ORDER BY 1
    LOOP
        PERFORM worker.spawn(
            p_command => 'derive_quality_partition',
            p_payload => jsonb_build_object('command', 'derive_quality_partition', 'hash_partition', v_hash_partition::text),
            p_parent_id => v_task_id
        );
        v_child_count := v_child_count + 1;
    END LOOP;

    p_info := jsonb_build_object('child_count', v_child_count, 'full', v_full);
END;
$procedure$;

CREATE OR REPLACE PROCEDURE worker.derive_quality_partition(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
BEGIN
    -- The findings per check in this partition, one number per check, so the parent's info sums
    -- them over its children (worker.complete_parent_if_ready).
    p_info := public.quality_finding_derive((payload->>'hash_partition')::int4range);
END;
$procedure$;

DROP FUNCTION public.quality_relation_derive();
DROP FUNCTION public.quality_relation_derive(int4range);
DROP VIEW public.quality_legal_unit_establishment_stat_def;
DROP VIEW public.quality_establishment_activity_differs_def;
DELETE FROM public.quality_establishment_activity_differs WHERE true; -- every row: part 1 holds the table empty
DELETE FROM public.quality_legal_unit_establishment_stat WHERE true; -- every row: part 1 holds the table empty
ALTER TABLE public.quality_legal_unit_establishment_stat DROP CONSTRAINT quality_legal_unit_establishment_stat_statistical_unit_fkey;
ALTER TABLE public.quality_establishment_activity_differs
    DROP CONSTRAINT quality_establishment_activity_differs_statistical_unit_fkey,
    ALTER COLUMN legal_unit_activity_category_id SET NOT NULL,
    ALTER COLUMN establishment_activity_category_id SET NOT NULL;
COMMENT ON TABLE public.quality_establishment_activity_differs IS
  'Findings of check 4, establishment_activity_differs (h9mhxe): one row per legal unit''s statistical_unit row whose primary establishment has another primary activity category than the legal unit. Filled by the relation step of worker.derive_quality (part 2 of h9mhxe); empty until then.';
COMMENT ON TABLE public.quality_legal_unit_establishment_stat IS
  'Findings of the per-variable checks establishments_above_legal_unit and legal_unit_above_establishments (h9mhxe): one row per check (a rule and summed variable) and legal unit''s statistical_unit row it lists, with the comparison that decided it. One table serves both rules for every variable because they share one comparison. Filled by the relation step of worker.derive_quality (part 2 of h9mhxe); empty until then.';
COMMENT ON COLUMN public.quality_establishment_activity_differs.legal_unit_activity_category_id IS 'The legal unit''s primary activity category.';
COMMENT ON COLUMN public.quality_establishment_activity_differs.establishment_activity_category_id IS 'The primary establishment''s primary activity category, which differs from the legal unit''s.';

-- ######## quality_finding, its rules, the quality_check view and the switch table, as they were ########
--
-- PostgreSQL database dump
--


-- Dumped from database version 18.7 (Ubuntu 18.7-1.pgdg22.04+5)
-- Dumped by pg_dump version 18.7 (Ubuntu 18.7-1.pgdg22.04+5)




--
-- Name: quality_check_switched_on; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.quality_check_switched_on (
    rule public.quality_rule NOT NULL,
    stat_definition_id integer,
    CONSTRAINT quality_check_switched_on_variable_matches_rule CHECK ((public.quality_rule_per_stat(rule) = (stat_definition_id IS NOT NULL)))
);


--
-- Name: TABLE quality_check_switched_on; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.quality_check_switched_on IS 'The checks an installation has switched on (1tx1ed): shown in the dashboard''s Data quality section and the search''s Quality filter. Only switched-on checks are stored, so every check, a new variable''s checks too, starts off; a fresh installation and reset''s customisation scope hold the starting set (public.quality_check_starting_set). A disabled variable keeps its row for when it is enabled again; deleting the variable deletes it. Written by admins on Admin > Data quality checks.';


--
-- Name: COLUMN quality_check_switched_on.stat_definition_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.quality_check_switched_on.stat_definition_id IS 'The summed variable of a per-variable rule (public.quality_rule_per_stat); NULL for every other rule.';


--
-- Name: CONSTRAINT quality_check_switched_on_variable_matches_rule ON quality_check_switched_on; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON CONSTRAINT quality_check_switched_on_variable_matches_rule ON public.quality_check_switched_on IS 'A per-variable rule names its variable and every other rule names none (public.quality_rule_per_stat), so each row is a check of public.quality_check.';


--
-- Name: quality_check; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.quality_check WITH (security_invoker='on') AS
 WITH check_of AS (
         SELECT r.rule,
            NULL::integer AS stat_definition_id,
            0 AS stat_priority
           FROM unnest(enum_range(NULL::public.quality_rule)) r(rule)
          WHERE (NOT public.quality_rule_per_stat(r.rule))
        UNION ALL
         SELECT r.rule,
            sd.id,
            sd.priority
           FROM (unnest(enum_range(NULL::public.quality_rule)) r(rule)
             JOIN public.stat_definition sd ON ((sd.enabled AND (sd.type = ANY (ARRAY['int'::public.stat_type, 'float'::public.stat_type])) AND (sd.lu_es_rollup = 'max'::public.lu_es_rollup))))
          WHERE public.quality_rule_per_stat(r.rule)
        )
 SELECT rule,
    stat_definition_id,
    (EXISTS ( SELECT 1
           FROM public.quality_check_switched_on qs
          WHERE ((qs.rule = c.rule) AND (COALESCE(qs.stat_definition_id, 0) = COALESCE(c.stat_definition_id, 0))))) AS on_dashboard,
    row_number() OVER (ORDER BY rule, stat_priority, stat_definition_id) AS priority
   FROM check_of c;


--
-- Name: VIEW quality_check; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.quality_check IS 'Every data-quality check of this installation (05pe0x): each rule that is not per variable once, and each per-variable rule once per enabled summed statistical variable (stat_definition of type int or float), so adding, disabling or enabling a variable adds or removes its checks with no other step. on_dashboard is true when the check is in public.quality_check_switched_on (1tx1ed): a check starts off. priority orders the checks: by rule (the enum''s order), then by the variable''s priority. The dashboard and the search''s Quality filter show the checks with on_dashboard; Admin > Data quality checks lists them all.';


--
-- Name: quality_finding; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.quality_finding (
    rule public.quality_rule NOT NULL,
    stat_definition_id integer,
    unit_type public.statistical_unit_type NOT NULL,
    unit_id integer NOT NULL,
    valid_from date NOT NULL,
    valid_until date NOT NULL,
    valid_range daterange GENERATED ALWAYS AS (daterange(valid_from, valid_until)) STORED NOT NULL,
    existence_from date NOT NULL,
    existence_until date NOT NULL,
    detail jsonb,
    hash_slot integer GENERATED ALWAYS AS (public.hash_slot(unit_type, unit_id)) STORED,
    CONSTRAINT quality_finding_variable_matches_rule CHECK ((public.quality_rule_per_stat(rule) = (stat_definition_id IS NOT NULL)))
);


--
-- Name: TABLE quality_finding; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.quality_finding IS 'The units each data-quality check lists (05pe0x): one row per check (rule, and variable for a per-variable rule) and statistical_unit row it lists. Filled from public.quality_finding_def by public.quality_finding_derive() in worker.derive_quality after statistical_unit is published; it holds every check, switched off or not, so switching one on shows its number at once. The dashboard counts every check at an instant in one query on (rule, stat_definition_id, existence_from, existence_until); the search lists a check''s units through public.statistical_unit_quality().';


--
-- Name: COLUMN quality_finding.stat_definition_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.quality_finding.stat_definition_id IS 'The summed variable a per-variable rule compares (public.quality_rule_per_stat); NULL for every other rule.';


--
-- Name: COLUMN quality_finding.valid_range; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.quality_finding.valid_range IS 'The statistical_unit row''s period; with unit_type and unit_id the key of that row.';


--
-- Name: COLUMN quality_finding.existence_from; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.quality_finding.existence_from IS 'public.existence_from of the statistical_unit row, copied so that a check is counted at an instant from this table alone (lib/unit-existence.ts: existence_from <= d < existence_until).';


--
-- Name: COLUMN quality_finding.existence_until; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.quality_finding.existence_until IS 'public.existence_until of the statistical_unit row; see existence_from.';


--
-- Name: COLUMN quality_finding.detail; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.quality_finding.detail IS 'What the rule compared, for a reader of the finding. establishments_above_legal_unit and legal_unit_above_establishments: {"legal_unit": own value, "establishments_sum": sum, "establishments": count}. establishment_activity_differs: {"legal_unit_activity_category_id", "primary_establishment_id", "primary_establishment_activity_category_id"}. NULL for the rules that say all in their name.';


--
-- Name: COLUMN quality_finding.hash_slot; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.quality_finding.hash_slot IS 'The unit''s public.hash_slot, the partition public.quality_finding_derive() rederives the finding in (0pn35h).';


--
-- Name: CONSTRAINT quality_finding_variable_matches_rule ON quality_finding; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON CONSTRAINT quality_finding_variable_matches_rule ON public.quality_finding IS 'A per-variable rule''s finding names its variable and every other rule''s names none (public.quality_rule_per_stat).';


--
-- Name: quality_finding_def; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.quality_finding_def WITH (security_invoker='on') AS
 SELECT r.rule,
    NULL::integer AS stat_definition_id,
    su.unit_type,
    su.unit_id,
    su.valid_from,
    su.valid_until,
    r.detail,
    su.hash_slot
   FROM (public.statistical_unit su
     CROSS JOIN LATERAL ( VALUES ('missing_region'::public.quality_rule,(su.domestic AND (su.physical_country_id IS NOT NULL) AND (su.physical_region_path IS NULL)),NULL::jsonb), ('missing_activity_category'::public.quality_rule,(su.primary_activity_category_path IS NULL),NULL::jsonb), ('missing_physical_location'::public.quality_rule,(su.physical_country_id IS NULL),NULL::jsonb), ('secondary_activity_equals_primary'::public.quality_rule,(su.secondary_activity_category_id = su.primary_activity_category_id),jsonb_build_object('activity_category_id', su.primary_activity_category_id))) r(rule, failed, detail))
  WHERE ((su.unit_type = ANY (ARRAY['legal_unit'::public.statistical_unit_type, 'establishment'::public.statistical_unit_type])) AND r.failed)
UNION ALL
 SELECT 'establishment_activity_differs'::public.quality_rule AS rule,
    NULL::integer AS stat_definition_id,
    su.unit_type,
    su.unit_id,
    su.valid_from,
    su.valid_until,
    jsonb_build_object('legal_unit_activity_category_id', su.primary_activity_category_id, 'primary_establishment_id', te.unit_id, 'primary_establishment_activity_category_id', te.primary_activity_category_id) AS detail,
    su.hash_slot
   FROM (public.statistical_unit su
     JOIN public.timeline_establishment te ON (((te.legal_unit_id = su.unit_id) AND te.primary_for_legal_unit AND (te.valid_from <= su.valid_from) AND (su.valid_from < te.valid_until))))
  WHERE ((su.unit_type = 'legal_unit'::public.statistical_unit_type) AND (su.primary_activity_category_id IS DISTINCT FROM te.primary_activity_category_id))
UNION ALL
 SELECT 'establishments_above_legal_unit'::public.quality_rule AS rule,
    sd.id AS stat_definition_id,
    c.unit_type,
    c.unit_id,
    c.valid_from,
    c.valid_until,
    jsonb_build_object('legal_unit', c.legal_unit_value, 'establishments_sum', c.establishments_sum, 'establishments', c.establishment_count) AS detail,
    c.hash_slot
   FROM (public.legal_unit_establishment_stat_comparison c
     JOIN public.stat_definition sd ON (((sd.code)::text = (c.stat_code)::text)))
  WHERE (c.legal_unit_value < c.establishments_sum)
UNION ALL
 SELECT 'legal_unit_above_establishments'::public.quality_rule AS rule,
    sd.id AS stat_definition_id,
    c.unit_type,
    c.unit_id,
    c.valid_from,
    c.valid_until,
    jsonb_build_object('legal_unit', c.legal_unit_value, 'establishments_sum', c.establishments_sum, 'establishments', c.establishment_count) AS detail,
    c.hash_slot
   FROM (public.legal_unit_establishment_stat_comparison c
     JOIN public.stat_definition sd ON (((sd.code)::text = (c.stat_code)::text)))
  WHERE ((c.establishments_sum < c.legal_unit_value) AND (c.establishments_with_value = c.establishment_count));


--
-- Name: VIEW quality_finding_def; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.quality_finding_def IS 'The rule of every data-quality check (public.quality_rule), read from the published statistical_unit and the legal unit / establishment comparison; public.quality_finding_derive() makes public.quality_finding equal to it, a hash partition at a time. The rules that read one statistical_unit row share one pass over it (a VALUES row per rule with its test); the rules comparing a legal unit with its establishments are their own branches. Missing region counts only units located in the installation''s own country (domestic): a unit abroad has no region of this country to lack, and a unit without a physical location is missing_physical_location (pkne34). Secondary activity equals primary reads each statistical_unit row, which statistical_unit splits wherever an activity changes, so the row is the period where the two overlap (qjy2eg).';


--
-- Name: COLUMN quality_finding_def.hash_slot; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.quality_finding_def.hash_slot IS 'The unit''s public.hash_slot: public.quality_finding_derive() filters on it to rederive one partition (0pn35h).';


--
-- Name: quality_check_switched_on quality_check_switched_on_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quality_check_switched_on
    ADD CONSTRAINT quality_check_switched_on_key UNIQUE NULLS NOT DISTINCT (rule, stat_definition_id);


--
-- Name: CONSTRAINT quality_check_switched_on_key ON quality_check_switched_on; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON CONSTRAINT quality_check_switched_on_key ON public.quality_check_switched_on IS 'A check is switched on once: the rule and its variable, NULL counting as a value (NULLS NOT DISTINCT), so a rule without a variable has one row at most.';


--
-- Name: quality_finding quality_finding_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quality_finding
    ADD CONSTRAINT quality_finding_key UNIQUE NULLS NOT DISTINCT (rule, stat_definition_id, unit_type, unit_id, valid_range);


--
-- Name: CONSTRAINT quality_finding_key ON quality_finding; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON CONSTRAINT quality_finding_key ON public.quality_finding IS 'A check lists a statistical_unit row once: the rule, its variable (NULL counting as a value), and the row''s unit and period; the key quality_finding_derive() merges on.';


--
-- Name: quality_finding_count_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX quality_finding_count_idx ON public.quality_finding USING btree (rule, COALESCE(stat_definition_id, 0), existence_from, existence_until);


--
-- Name: INDEX quality_finding_count_idx; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.quality_finding_count_idx IS 'Serves the dashboard''s count of every check at an instant and public.statistical_unit_quality(): a check (rule and variable, 0 for none) and the instant within the existence dates.';


--
-- Name: quality_finding_hash_slot_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX quality_finding_hash_slot_idx ON public.quality_finding USING btree (hash_slot);


--
-- Name: quality_check_switched_on quality_check_switched_on_stat_definition_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quality_check_switched_on
    ADD CONSTRAINT quality_check_switched_on_stat_definition_id_fkey FOREIGN KEY (stat_definition_id) REFERENCES public.stat_definition(id) ON DELETE CASCADE;


--
-- Name: quality_finding quality_finding_stat_definition_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quality_finding
    ADD CONSTRAINT quality_finding_stat_definition_id_fkey FOREIGN KEY (stat_definition_id) REFERENCES public.stat_definition(id) ON DELETE CASCADE;


--
-- Name: quality_finding quality_finding_statistical_unit_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quality_finding
    ADD CONSTRAINT quality_finding_statistical_unit_fkey FOREIGN KEY (unit_type, unit_id, PERIOD valid_range) REFERENCES public.statistical_unit(unit_type, unit_id, PERIOD valid_range) NOT ENFORCED;


--
-- Name: CONSTRAINT quality_finding_statistical_unit_fkey ON quality_finding; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON CONSTRAINT quality_finding_statistical_unit_fkey ON public.quality_finding IS 'NOT ENFORCED: describes the link to the statistical_unit row for readers; derive rewrites statistical_unit freely and the next worker.derive_quality makes this table right again. A TRUNCATE of statistical_unit names this table and says CASCADE.';


--
-- Name: quality_check_switched_on; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.quality_check_switched_on ENABLE ROW LEVEL SECURITY;

--
-- Name: quality_check_switched_on quality_check_switched_on_admin_user_manage; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY quality_check_switched_on_admin_user_manage ON public.quality_check_switched_on TO admin_user USING (true) WITH CHECK (true);


--
-- Name: quality_check_switched_on quality_check_switched_on_authenticated_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY quality_check_switched_on_authenticated_read ON public.quality_check_switched_on FOR SELECT TO authenticated USING (true);


--
-- Name: quality_check_switched_on quality_check_switched_on_regular_user_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY quality_check_switched_on_regular_user_read ON public.quality_check_switched_on FOR SELECT TO regular_user USING (true);


--
-- Name: quality_finding; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.quality_finding ENABLE ROW LEVEL SECURITY;

--
-- Name: quality_finding quality_finding_admin_user_manage; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY quality_finding_admin_user_manage ON public.quality_finding TO admin_user USING (true) WITH CHECK (true);


--
-- Name: quality_finding quality_finding_authenticated_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY quality_finding_authenticated_read ON public.quality_finding FOR SELECT TO authenticated USING (true);


--
-- Name: quality_finding quality_finding_regular_user_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY quality_finding_regular_user_read ON public.quality_finding FOR SELECT TO regular_user USING (true);


--
-- Name: TABLE quality_check_switched_on; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.quality_check_switched_on TO authenticated;
GRANT SELECT ON TABLE public.quality_check_switched_on TO regular_user;
GRANT ALL ON TABLE public.quality_check_switched_on TO admin_user;


--
-- Name: TABLE quality_check; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.quality_check TO authenticated;
GRANT SELECT ON TABLE public.quality_check TO regular_user;
GRANT SELECT ON TABLE public.quality_check TO admin_user;


--
-- Name: TABLE quality_finding; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.quality_finding TO authenticated;
GRANT SELECT ON TABLE public.quality_finding TO regular_user;
GRANT ALL ON TABLE public.quality_finding TO admin_user;


--
-- Name: TABLE quality_finding_def; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.quality_finding_def TO authenticated;
GRANT SELECT ON TABLE public.quality_finding_def TO regular_user;
GRANT SELECT ON TABLE public.quality_finding_def TO admin_user;


--
-- PostgreSQL database dump complete
--



INSERT INTO public.quality_check_switched_on (rule, stat_definition_id)
SELECT rule, stat_definition_id FROM quality_switched_on_down;

CREATE OR REPLACE FUNCTION public.quality_finding_derive(p_hash_slots int4range)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    -- Explicit half-open bounds, so the btree indexes on hash_slot are used (as in
    -- worker.derive_statistical_unit_facet_partition).
    v_from integer := lower(p_hash_slots);
    v_until integer := upper(p_hash_slots);
    v_findings jsonb;
BEGIN
    DELETE FROM public.quality_finding
     WHERE hash_slot >= v_from AND hash_slot < v_until;

    WITH inserted AS (
        INSERT INTO public.quality_finding
            (rule, stat_definition_id, unit_type, unit_id, valid_from, valid_until, existence_from, existence_until, detail)
        SELECT d.rule, d.stat_definition_id, d.unit_type, d.unit_id, d.valid_from, d.valid_until,
               public.unit_existence_from(su.valid_from, su.birth_date),
               public.unit_existence_until(su.valid_until, su.death_date),
               d.detail
        FROM public.quality_finding_def AS d
        JOIN public.statistical_unit AS su
          ON su.unit_type = d.unit_type AND su.unit_id = d.unit_id
         AND su.valid_range = daterange(d.valid_from, d.valid_until)
         AND su.hash_slot >= v_from AND su.hash_slot < v_until
        WHERE d.hash_slot >= v_from AND d.hash_slot < v_until
        RETURNING rule, stat_definition_id
    )
    SELECT jsonb_object_agg(k.check_key, k.findings) INTO v_findings
    FROM (
        SELECT CASE WHEN sd.code IS NULL THEN i.rule::text ELSE i.rule::text || ':' || sd.code END AS check_key,
               count(*) AS findings
        FROM inserted AS i
        LEFT JOIN public.stat_definition AS sd ON sd.id = i.stat_definition_id
        GROUP BY 1
    ) AS k;
    RETURN COALESCE(v_findings, '{}'::jsonb);
END;
$function$;

CREATE OR REPLACE FUNCTION public.quality_finding_derive()
 RETURNS jsonb
 LANGUAGE sql
AS $function$
    SELECT public.quality_finding_derive(int4range(0, 16384));
$function$;

CREATE OR REPLACE FUNCTION public.statistical_unit_quality(quality_rule quality_rule, valid_on date, quality_stat_definition_id integer DEFAULT NULL::integer)
 RETURNS SETOF statistical_unit
 LANGUAGE sql
 STABLE
AS $function$
    SELECT su.*
    FROM public.statistical_unit AS su
    WHERE public.existence_from(su) <= statistical_unit_quality.valid_on
      AND statistical_unit_quality.valid_on < public.existence_until(su)
      AND EXISTS (
          SELECT 1 FROM public.quality_finding AS f
          WHERE f.rule = statistical_unit_quality.quality_rule
            AND COALESCE(f.stat_definition_id, 0) = COALESCE(statistical_unit_quality.quality_stat_definition_id, 0)
            AND f.existence_from <= statistical_unit_quality.valid_on
            AND statistical_unit_quality.valid_on < f.existence_until
            AND f.unit_type = su.unit_type
            AND f.unit_id = su.unit_id
            AND f.valid_range = su.valid_range)
$function$;

GRANT EXECUTE ON FUNCTION public.statistical_unit_quality(public.quality_rule, date, integer) TO authenticated, regular_user, admin_user;
COMMENT ON FUNCTION public.statistical_unit_quality(quality_rule,date,integer) IS 'The statistical_unit rows that exist at valid_on and that a check (rule, and variable for a per-variable rule) lists, read from the findings first: the check, the instant (quality_finding_count_idx) and then each unit by its key. The search uses it for a check that lists few units at the time frame (Norway 2026-11-26: 2 units 9 ms, 17 units 36 ms for a page; about 0.16 ms per listed unit, so 161,571 units take 29 s), and walks statistical_unit in the page''s order with quality_finding as an inner embed for a check that lists many (161,571 units 0.1 s, 2 units 117 s): owner decision 2026-11-26, threshold 1,000 units by the check''s count at the time frame. Called as rpc/statistical_unit_quality with the page''s other filters, order and paging applied to its rows; its count equals the dashboard''s count of the check at valid_on.';
COMMENT ON FUNCTION public.quality_finding_derive(int4range) IS 'Makes public.quality_finding equal to public.quality_finding_def for the units whose hash_slot is in p_hash_slots, with each finding''s existence dates from its statistical_unit row. Returns the findings per check, keyed by the check''s ?quality= value (rule, or rule:variable code). Called per partition by worker.derive_quality_partition (0pn35h); public.quality_finding_derive() does every slot.';
COMMENT ON FUNCTION public.quality_finding_derive() IS 'public.quality_finding_derive(int4range) over every hash slot (public.hash_slot is 0 to 16383): all findings in one transaction, for tests and repairs; the worker derives a partition per task.';
COMMENT ON PROCEDURE worker.derive_quality_partition(jsonb,jsonb) IS 'A child of worker.derive_quality: rederives the quality findings of one hash partition (public.quality_finding_derive), concurrently with its siblings (0pn35h). SECURITY DEFINER: it writes the RLS-protected public.quality_finding.';
COMMENT ON PROCEDURE worker.derive_quality(jsonb,jsonb) IS 'The reports phase''s quality step, after statistical_unit is published: spawns concurrent derive_quality_partition children, on a full recalculation one hash range per analytics worker (worker.queue_registry.default_concurrency) and otherwise the small partitions holding a changed unit (0pn35h). SECURITY DEFINER like the other derive steps, because its children write RLS-protected tables for whichever role enqueued the recalculation.';

-- ######## statistical_unit without quality_check_ids ########
DROP INDEX public.idx_statistical_unit_quality_check_count;
DROP INDEX public.idx_statistical_unit_quality_check_ids;
ALTER TABLE public.statistical_unit DROP COLUMN quality_check_ids;
CREATE OR REPLACE FUNCTION import.get_statistical_unit_data_partial(p_unit_type statistical_unit_type, p_id_ranges int4multirange)
 RETURNS SETOF statistical_unit
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    v_ids INT[] := public.int4multirange_to_array(p_id_ranges);
BEGIN
    IF p_unit_type = 'establishment' THEN
        RETURN QUERY
        SELECT t.unit_type, t.unit_id, t.valid_from, t.valid_to, t.valid_until,
            COALESCE(eia1.external_idents, '{}'::jsonb) AS external_idents,
            t.name, t.birth_date, t.death_date, t.search,
            t.primary_activity_category_id, t.primary_activity_category_path, t.primary_activity_category_code,
            t.secondary_activity_category_id, t.secondary_activity_category_path, t.secondary_activity_category_code,
            t.activity_category_paths, t.sector_id, t.sector_path, t.sector_code, t.sector_name,
            t.data_source_ids, t.data_source_codes, t.legal_form_id, t.legal_form_code, t.legal_form_name,
            t.physical_address_part1, t.physical_address_part2, t.physical_address_part3, t.physical_postcode, t.physical_postplace,
            t.physical_region_id, t.physical_region_path, t.physical_region_code, t.physical_country_id, t.physical_country_iso_2,
            t.physical_latitude, t.physical_longitude, t.physical_altitude, t.domestic,
            t.postal_address_part1, t.postal_address_part2, t.postal_address_part3, t.postal_postcode, t.postal_postplace,
            t.postal_region_id, t.postal_region_path, t.postal_region_code, t.postal_country_id, t.postal_country_iso_2,
            t.postal_latitude, t.postal_longitude, t.postal_altitude,
            t.web_address, t.email_address, t.phone_number, t.landline, t.mobile_number, t.fax_number,
            t.unit_size_id, t.unit_size_code, t.status_id, t.status_code, t.used_for_counting,
            t.last_edit_comment, t.last_edit_by_user_id, t.last_edit_at, t.has_legal_unit,
            t.related_establishment_ids, t.excluded_establishment_ids, t.included_establishment_ids,
            t.related_legal_unit_ids, t.excluded_legal_unit_ids, t.included_legal_unit_ids,
            t.related_enterprise_ids, t.excluded_enterprise_ids, t.included_enterprise_ids,
            t.stats, t.stats_summary,
            array_length(t.included_establishment_ids, 1) AS included_establishment_count,
            array_length(t.included_legal_unit_ids, 1) AS included_legal_unit_count,
            array_length(t.included_enterprise_ids, 1) AS included_enterprise_count,
            COALESCE(tpa.tag_paths, ARRAY[]::public.ltree[]) AS tag_paths,
            daterange(t.valid_from, t.valid_until) AS valid_range,
            public.hash_slot(t.unit_type, t.unit_id) AS hash_slot
        FROM public.timeline_establishment t
        LEFT JOIN LATERAL (SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents FROM public.external_ident ei JOIN public.external_ident_type eit ON ei.type_id = eit.id WHERE ei.establishment_id = t.unit_id) eia1 ON true
        LEFT JOIN LATERAL (SELECT array_agg(tag.path ORDER BY tag.path) AS tag_paths FROM public.tag_for_unit tfu JOIN public.tag ON tfu.tag_id = tag.id WHERE tfu.establishment_id = t.unit_id) tpa ON true
        WHERE t.unit_id = ANY(v_ids);

    ELSIF p_unit_type = 'legal_unit' THEN
        RETURN QUERY
        SELECT t.unit_type, t.unit_id, t.valid_from, t.valid_to, t.valid_until,
            COALESCE(eia1.external_idents, '{}'::jsonb) AS external_idents,
            t.name, t.birth_date, t.death_date, t.search,
            t.primary_activity_category_id, t.primary_activity_category_path, t.primary_activity_category_code,
            t.secondary_activity_category_id, t.secondary_activity_category_path, t.secondary_activity_category_code,
            t.activity_category_paths, t.sector_id, t.sector_path, t.sector_code, t.sector_name,
            t.data_source_ids, t.data_source_codes, t.legal_form_id, t.legal_form_code, t.legal_form_name,
            t.physical_address_part1, t.physical_address_part2, t.physical_address_part3, t.physical_postcode, t.physical_postplace,
            t.physical_region_id, t.physical_region_path, t.physical_region_code, t.physical_country_id, t.physical_country_iso_2,
            t.physical_latitude, t.physical_longitude, t.physical_altitude, t.domestic,
            t.postal_address_part1, t.postal_address_part2, t.postal_address_part3, t.postal_postcode, t.postal_postplace,
            t.postal_region_id, t.postal_region_path, t.postal_region_code, t.postal_country_id, t.postal_country_iso_2,
            t.postal_latitude, t.postal_longitude, t.postal_altitude,
            t.web_address, t.email_address, t.phone_number, t.landline, t.mobile_number, t.fax_number,
            t.unit_size_id, t.unit_size_code, t.status_id, t.status_code, t.used_for_counting,
            t.last_edit_comment, t.last_edit_by_user_id, t.last_edit_at, t.has_legal_unit,
            t.related_establishment_ids, t.excluded_establishment_ids, t.included_establishment_ids,
            t.related_legal_unit_ids, t.excluded_legal_unit_ids, t.included_legal_unit_ids,
            t.related_enterprise_ids, t.excluded_enterprise_ids, t.included_enterprise_ids,
            t.stats, t.stats_summary,
            array_length(t.included_establishment_ids, 1) AS included_establishment_count,
            array_length(t.included_legal_unit_ids, 1) AS included_legal_unit_count,
            array_length(t.included_enterprise_ids, 1) AS included_enterprise_count,
            COALESCE(tpa.tag_paths, ARRAY[]::public.ltree[]) AS tag_paths,
            daterange(t.valid_from, t.valid_until) AS valid_range,
            public.hash_slot(t.unit_type, t.unit_id) AS hash_slot
        FROM public.timeline_legal_unit t
        LEFT JOIN LATERAL (SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents FROM public.external_ident ei JOIN public.external_ident_type eit ON ei.type_id = eit.id WHERE ei.legal_unit_id = t.unit_id) eia1 ON true
        LEFT JOIN LATERAL (SELECT array_agg(tag.path ORDER BY tag.path) AS tag_paths FROM public.tag_for_unit tfu JOIN public.tag ON tfu.tag_id = tag.id WHERE tfu.legal_unit_id = t.unit_id) tpa ON true
        WHERE t.unit_id = ANY(v_ids);

    ELSIF p_unit_type = 'enterprise' THEN
        RETURN QUERY
        SELECT t.unit_type, t.unit_id, t.valid_from, t.valid_to, t.valid_until,
            COALESCE(eia1.external_idents, eia2.external_idents, eia3.external_idents, '{}'::jsonb) AS external_idents,
            t.name::varchar, t.birth_date, t.death_date, t.search,
            t.primary_activity_category_id, t.primary_activity_category_path, t.primary_activity_category_code,
            t.secondary_activity_category_id, t.secondary_activity_category_path, t.secondary_activity_category_code,
            t.activity_category_paths, t.sector_id, t.sector_path, t.sector_code, t.sector_name,
            t.data_source_ids, t.data_source_codes, t.legal_form_id, t.legal_form_code, t.legal_form_name,
            t.physical_address_part1, t.physical_address_part2, t.physical_address_part3, t.physical_postcode, t.physical_postplace,
            t.physical_region_id, t.physical_region_path, t.physical_region_code, t.physical_country_id, t.physical_country_iso_2,
            t.physical_latitude, t.physical_longitude, t.physical_altitude, t.domestic,
            t.postal_address_part1, t.postal_address_part2, t.postal_address_part3, t.postal_postcode, t.postal_postplace,
            t.postal_region_id, t.postal_region_path, t.postal_region_code, t.postal_country_id, t.postal_country_iso_2,
            t.postal_latitude, t.postal_longitude, t.postal_altitude,
            t.web_address, t.email_address, t.phone_number, t.landline, t.mobile_number, t.fax_number,
            t.unit_size_id, t.unit_size_code, t.status_id, t.status_code, t.used_for_counting,
            t.last_edit_comment, t.last_edit_by_user_id, t.last_edit_at, t.has_legal_unit,
            t.related_establishment_ids, t.excluded_establishment_ids, t.included_establishment_ids,
            t.related_legal_unit_ids, t.excluded_legal_unit_ids, t.included_legal_unit_ids,
            t.related_enterprise_ids, t.excluded_enterprise_ids, t.included_enterprise_ids,
            NULL::JSONB AS stats, t.stats_summary,
            array_length(t.included_establishment_ids, 1) AS included_establishment_count,
            array_length(t.included_legal_unit_ids, 1) AS included_legal_unit_count,
            array_length(t.included_enterprise_ids, 1) AS included_enterprise_count,
            COALESCE(tpa.tag_paths, ARRAY[]::public.ltree[]) AS tag_paths,
            daterange(t.valid_from, t.valid_until) AS valid_range,
            public.hash_slot(t.unit_type, t.unit_id) AS hash_slot
        FROM public.timeline_enterprise t
        LEFT JOIN LATERAL (SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents FROM public.external_ident ei JOIN public.external_ident_type eit ON ei.type_id = eit.id WHERE ei.enterprise_id = t.unit_id) eia1 ON true
        LEFT JOIN LATERAL (SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents FROM public.external_ident ei JOIN public.external_ident_type eit ON ei.type_id = eit.id WHERE ei.establishment_id = t.primary_establishment_id) eia2 ON true
        LEFT JOIN LATERAL (SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents FROM public.external_ident ei JOIN public.external_ident_type eit ON ei.type_id = eit.id WHERE ei.legal_unit_id = t.primary_legal_unit_id) eia3 ON true
        LEFT JOIN LATERAL (SELECT array_agg(tag.path ORDER BY tag.path) AS tag_paths FROM public.tag_for_unit tfu JOIN public.tag ON tfu.tag_id = tag.id WHERE tfu.enterprise_id = t.unit_id) tpa ON true
        WHERE t.unit_id = ANY(v_ids);

    ELSIF p_unit_type = 'power_group' THEN
        RETURN QUERY
        SELECT t.unit_type, t.unit_id, t.valid_from, t.valid_to, t.valid_until,
            COALESCE(eia1.external_idents, '{}'::jsonb) AS external_idents,
            t.name::varchar, t.birth_date, t.death_date, t.search,
            t.primary_activity_category_id, t.primary_activity_category_path, t.primary_activity_category_code,
            t.secondary_activity_category_id, t.secondary_activity_category_path, t.secondary_activity_category_code,
            t.activity_category_paths, t.sector_id, t.sector_path, t.sector_code, t.sector_name,
            t.data_source_ids, t.data_source_codes, t.legal_form_id, t.legal_form_code, t.legal_form_name,
            t.physical_address_part1, t.physical_address_part2, t.physical_address_part3, t.physical_postcode, t.physical_postplace,
            t.physical_region_id, t.physical_region_path, t.physical_region_code, t.physical_country_id, t.physical_country_iso_2,
            t.physical_latitude, t.physical_longitude, t.physical_altitude, t.domestic,
            t.postal_address_part1, t.postal_address_part2, t.postal_address_part3, t.postal_postcode, t.postal_postplace,
            t.postal_region_id, t.postal_region_path, t.postal_region_code, t.postal_country_id, t.postal_country_iso_2,
            t.postal_latitude, t.postal_longitude, t.postal_altitude,
            t.web_address, t.email_address, t.phone_number, t.landline, t.mobile_number, t.fax_number,
            t.unit_size_id, t.unit_size_code, t.status_id, t.status_code, t.used_for_counting,
            t.last_edit_comment, t.last_edit_by_user_id, t.last_edit_at, t.has_legal_unit,
            t.related_establishment_ids, t.excluded_establishment_ids, t.included_establishment_ids,
            t.related_legal_unit_ids, t.excluded_legal_unit_ids, t.included_legal_unit_ids,
            t.related_enterprise_ids, t.excluded_enterprise_ids, t.included_enterprise_ids,
            NULL::JSONB AS stats, t.stats_summary,
            array_length(t.included_establishment_ids, 1) AS included_establishment_count,
            array_length(t.included_legal_unit_ids, 1) AS included_legal_unit_count,
            array_length(t.included_enterprise_ids, 1) AS included_enterprise_count,
            COALESCE(tpa.tag_paths, ARRAY[]::public.ltree[]) AS tag_paths,
            daterange(t.valid_from, t.valid_until) AS valid_range,
            public.hash_slot(t.unit_type, t.unit_id) AS hash_slot
        FROM public.timeline_power_group t
        LEFT JOIN LATERAL (SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents FROM public.external_ident ei JOIN public.external_ident_type eit ON ei.type_id = eit.id WHERE ei.power_group_id = t.power_group_id) eia1 ON true
        LEFT JOIN LATERAL (SELECT array_agg(tag.path ORDER BY tag.path) AS tag_paths FROM public.tag_for_unit tfu JOIN public.tag ON tfu.tag_id = tag.id WHERE tfu.power_group_id = t.power_group_id) tpa ON true
        WHERE t.unit_id = ANY(v_ids);
    END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION admin.create_statistical_unit_ui_indices()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Every index here serves a query on statistical_unit; its COMMENT names the query.
    -- The search page's filters and sorts are listed in app/src/app/search/filters/url-search-params.ts
    -- and app/src/atoms/search.ts; test/sql/359 checks that each one reads an index.

    -- Lookups by the derive pipeline, reports and unit pages.
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_unit_type ON public.statistical_unit (unit_type);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_establishment_id ON public.statistical_unit (unit_id);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_primary_activity_category_id ON public.statistical_unit (primary_activity_category_id);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_secondary_activity_category_id ON public.statistical_unit (secondary_activity_category_id);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_physical_region_id ON public.statistical_unit (physical_region_id);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_physical_country_id ON public.statistical_unit (physical_country_id);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_sector_id ON public.statistical_unit (sector_id);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_legal_form_id ON public.statistical_unit (legal_form_id);

    -- Search filters.
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_domestic ON public.statistical_unit (domestic);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_status_code ON public.statistical_unit (status_code);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_unit_size_code ON public.statistical_unit (unit_size_code);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_last_edit_by_user_id ON public.statistical_unit (last_edit_by_user_id);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_search ON public.statistical_unit USING GIN (search);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_data_source_ids ON public.statistical_unit USING GIN (data_source_ids public.gin__int_ops);
    CREATE INDEX IF NOT EXISTS idx_gist_statistical_unit_external_idents ON public.statistical_unit USING GIN (external_idents jsonb_path_ops);

    -- Path filters (descendant of a chosen code: GiST).
    CREATE INDEX IF NOT EXISTS idx_gist_statistical_unit_physical_region_path ON public.statistical_unit USING GIST (physical_region_path);
    CREATE INDEX IF NOT EXISTS idx_gist_statistical_unit_sector_path ON public.statistical_unit USING GIST (sector_path);
    CREATE INDEX IF NOT EXISTS idx_gist_statistical_unit_primary_activity_category_path ON public.statistical_unit USING GIST (primary_activity_category_path);
    CREATE INDEX IF NOT EXISTS idx_gist_statistical_unit_tag_paths ON public.statistical_unit USING GIST (tag_paths);

    -- Search sorts: one index per direction, ending in the search's tie-break (unit_type, unit_id).
    -- The asc index also serves the column's equality filter (legal_form_code in (...)).
    CREATE INDEX IF NOT EXISTS su_sort_name_asc ON public.statistical_unit (name, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_name_desc ON public.statistical_unit (name DESC NULLS LAST, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_physical_region_path_asc ON public.statistical_unit (physical_region_path, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_physical_region_path_desc ON public.statistical_unit (physical_region_path DESC NULLS LAST, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_sector_path_asc ON public.statistical_unit (sector_path, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_sector_path_desc ON public.statistical_unit (sector_path DESC NULLS LAST, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_legal_form_code_asc ON public.statistical_unit (legal_form_code, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_legal_form_code_desc ON public.statistical_unit (legal_form_code DESC NULLS LAST, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_primary_activity_category_path_asc ON public.statistical_unit (primary_activity_category_path, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_primary_activity_category_path_desc ON public.statistical_unit (primary_activity_category_path DESC NULLS LAST, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_secondary_activity_category_path_asc ON public.statistical_unit (secondary_activity_category_path, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_secondary_activity_category_path_desc ON public.statistical_unit (secondary_activity_category_path DESC NULLS LAST, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_birth_date_asc ON public.statistical_unit (birth_date, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_birth_date_desc ON public.statistical_unit (birth_date DESC NULLS LAST, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_death_date_asc ON public.statistical_unit (death_date, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_death_date_desc ON public.statistical_unit (death_date DESC NULLS LAST, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_last_edit_at_asc ON public.statistical_unit (last_edit_at, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_last_edit_at_desc ON public.statistical_unit (last_edit_at DESC NULLS LAST, unit_type, unit_id);

    -- Per identifier type and per statistic (su_ei_*, su_ss_*): admin.generate_statistical_unit_jsonb_indices().
    CALL admin.generate_statistical_unit_jsonb_indices();

    PERFORM admin.comment_statistical_unit_indices();
    RAISE DEBUG 'Created all statistical_unit UI indices';
END;
$function$;

CREATE OR REPLACE FUNCTION admin.comment_statistical_unit_indices()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    r RECORD;
    v_comment text;
BEGIN
    FOR r IN
        SELECT c.relname AS indexname
          FROM pg_index AS i JOIN pg_class AS c ON c.oid = i.indexrelid
         WHERE i.indrelid = 'public.statistical_unit'::regclass
           -- These two carry their own comments, written where they were made.
           AND c.relname NOT IN ('idx_statistical_unit_hash_slot', 'statistical_unit_unit_idx')
    LOOP
        v_comment := CASE
            WHEN r.indexname = 'statistical_unit_temporal_pk' THEN
                'Temporal primary key (unit_type, unit_id, valid_range): one row per unit and period.'
            WHEN r.indexname IN ('idx_statistical_unit_unit_type', 'idx_statistical_unit_establishment_id') THEN
                'Unit pages and reports look units up by type and id.'
            WHEN r.indexname = 'idx_statistical_unit_last_edit_by_user_id' THEN
                'Search filter: last edited by (last_edit_by_user_id in ...).'
            WHEN r.indexname ~ '^idx_statistical_unit_.*_id$' THEN
                'Derive pipeline and reports join statistical_unit to its classification by id.'
            WHEN r.indexname = 'idx_statistical_unit_domestic' THEN 'Search filter: domestic.'
            WHEN r.indexname = 'idx_statistical_unit_status_code' THEN 'Search filter: status (status_code in ...).'
            WHEN r.indexname = 'idx_statistical_unit_unit_size_code' THEN 'Search filter: unit size (unit_size_code in ...).'
            WHEN r.indexname = 'idx_statistical_unit_search' THEN 'Search filter: free text (search, full-text query).'
            WHEN r.indexname = 'idx_statistical_unit_data_source_ids' THEN 'Search filter: data source (data_source_ids overlaps ...).'
            WHEN r.indexname = 'idx_gist_statistical_unit_external_idents' THEN 'Identifier lookups by containment (external_idents @> ...).'
            WHEN r.indexname ~ '^idx_gist_statistical_unit_' THEN
                format('Search filter: %s under a chosen code (ltree descendant, cd.).',
                       regexp_replace(r.indexname, '^idx_gist_statistical_unit_', ''))
            WHEN r.indexname ~ '^su_sort_.*_asc$' THEN
                format('Search sort: %s ascending, then unit_type, unit_id; read backwards for a page from the end of a descending sort. Also serves equality filters on the column.',
                       regexp_replace(r.indexname, '^su_sort_(.*)_asc$', '\1'))
            WHEN r.indexname ~ '^su_sort_.*_desc$' THEN
                format('Search sort: %s descending with nulls last, then unit_type, unit_id; read backwards for a page from the end of an ascending sort.',
                       regexp_replace(r.indexname, '^su_sort_(.*)_desc$', '\1'))
            WHEN r.indexname ~ '^su_ss_.*_sum_asc_idx$' THEN
                format('Search filter and sort on statistic %s (stats_summary->code->''sum''): ascending, then unit_type, unit_id. Built by admin.generate_statistical_unit_jsonb_indices.',
                       regexp_replace(r.indexname, '^su_ss_(.*)_sum_asc_idx$', '\1'))
            WHEN r.indexname ~ '^su_ss_.*_sum_desc_idx$' THEN
                format('Search sort on statistic %s (stats_summary->code->''sum''): descending with nulls last, then unit_type, unit_id. Built by admin.generate_statistical_unit_jsonb_indices.',
                       regexp_replace(r.indexname, '^su_ss_(.*)_sum_desc_idx$', '\1'))
            WHEN r.indexname ~ '^su_ei_.*_ltree_gist_idx$' THEN
                format('Search filter: hierarchical identifier %s matched by pattern. Built by admin.generate_statistical_unit_jsonb_indices.',
                       regexp_replace(r.indexname, '^su_ei_(.*)_ltree_gist_idx$', '\1'))
            WHEN r.indexname ~ '^su_ei_.*_idx$' THEN
                format('Search filter: identifier %s (external_idents->>code). Built by admin.generate_statistical_unit_jsonb_indices.',
                       regexp_replace(r.indexname, '^su_ei_(.*)_idx$', '\1'))
        END;
        IF v_comment IS NULL THEN
            RAISE EXCEPTION 'statistical_unit index % has no stated purpose: add it to admin.comment_statistical_unit_indices() with the query it serves, or drop it', r.indexname;
        END IF;
        EXECUTE format('COMMENT ON INDEX public.%I IS %L', r.indexname, v_comment);
    END LOOP;
END;
$function$;

END;
