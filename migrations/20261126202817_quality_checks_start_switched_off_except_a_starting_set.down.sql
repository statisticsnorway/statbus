-- Down Migration 20261126202817: back to recording the checks switched off (absence means on).
-- Every check, for every summed variable enabled or not, that is not switched on is switched off,
-- so the installation keeps the checks it shows.
BEGIN;

CREATE TABLE public.quality_check_switched_off (
    rule public.quality_rule NOT NULL,
    stat_definition_id integer REFERENCES public.stat_definition (id) ON DELETE CASCADE,
    CONSTRAINT quality_check_switched_off_key UNIQUE NULLS NOT DISTINCT (rule, stat_definition_id),
    CONSTRAINT quality_check_switched_off_variable_matches_rule
        CHECK (public.quality_rule_per_stat(rule) = (stat_definition_id IS NOT NULL))
);

COMMENT ON TABLE public.quality_check_switched_off IS
  'The checks an installation has switched off (05pe0x): hidden from the dashboard''s Data quality section and the search''s Quality filter. Only switched-off checks are stored, so every check, a new variable''s checks too, starts on. A disabled variable keeps its row for when it is enabled again; deleting the variable deletes it. Written by admins on Admin > Data quality checks; reset''s customisation scope empties it.';
COMMENT ON COLUMN public.quality_check_switched_off.stat_definition_id IS
  'The summed variable of a per-variable rule (public.quality_rule_per_stat); NULL for every other rule.';
COMMENT ON CONSTRAINT quality_check_switched_off_key ON public.quality_check_switched_off IS
  'A check is switched off once: the rule and its variable, NULL counting as a value (NULLS NOT DISTINCT), so a rule without a variable has one row at most.';
COMMENT ON CONSTRAINT quality_check_switched_off_variable_matches_rule ON public.quality_check_switched_off IS
  'A per-variable rule names its variable and every other rule names none (public.quality_rule_per_stat), so each row is a check of public.quality_check.';

-- Everyone signed in reads the switches (the dashboard and the Quality filter); admins write them.
SELECT admin.add_rls_regular_user_can_read('public.quality_check_switched_off'::regclass);

INSERT INTO public.quality_check_switched_off (rule, stat_definition_id)
SELECT c.rule, c.stat_definition_id
FROM (
    SELECT r.rule, NULL::integer AS stat_definition_id
    FROM unnest(enum_range(NULL::public.quality_rule)) AS r(rule)
    WHERE NOT public.quality_rule_per_stat(r.rule)
    UNION ALL
    SELECT r.rule, sd.id
    FROM unnest(enum_range(NULL::public.quality_rule)) AS r(rule)
    JOIN public.stat_definition AS sd ON sd.type IN ('int', 'float')
    WHERE public.quality_rule_per_stat(r.rule)
) AS c
WHERE NOT EXISTS (
    SELECT 1 FROM public.quality_check_switched_on AS qs
    WHERE qs.rule = c.rule
      AND COALESCE(qs.stat_definition_id, 0) = COALESCE(c.stat_definition_id, 0));

DROP VIEW public.quality_check;
CREATE VIEW public.quality_check
WITH (security_invoker = on) AS
WITH check_of AS (
    SELECT r.rule, NULL::integer AS stat_definition_id, 0 AS stat_priority
    FROM unnest(enum_range(NULL::public.quality_rule)) AS r(rule)
    WHERE NOT public.quality_rule_per_stat(r.rule)
    UNION ALL
    SELECT r.rule, sd.id, sd.priority
    FROM unnest(enum_range(NULL::public.quality_rule)) AS r(rule)
    JOIN public.stat_definition AS sd
      ON sd.enabled AND sd.type IN ('int', 'float')
    WHERE public.quality_rule_per_stat(r.rule)
)
SELECT c.rule,
       c.stat_definition_id,
       NOT EXISTS (
           SELECT 1 FROM public.quality_check_switched_off AS qs
           WHERE qs.rule = c.rule
             AND COALESCE(qs.stat_definition_id, 0) = COALESCE(c.stat_definition_id, 0)
       ) AS on_dashboard,
       row_number() OVER (ORDER BY c.rule, c.stat_priority, c.stat_definition_id) AS priority
FROM check_of AS c;

COMMENT ON VIEW public.quality_check IS
  'Every data-quality check of this installation (05pe0x): each rule that is not per variable once, and each per-variable rule once per enabled summed statistical variable (stat_definition of type int or float), so adding, disabling or enabling a variable adds or removes its checks with no other step. on_dashboard is false when the check is in public.quality_check_switched_off. priority orders the checks: by rule (the enum''s order), then by the variable''s priority. The dashboard and the search''s Quality filter show the checks with on_dashboard; Admin > Data quality checks lists them all.';
GRANT SELECT ON public.quality_check TO authenticated, regular_user, admin_user;

DROP TABLE public.quality_check_switched_on;

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
        -- quality_check_switched_off: every check switched on again, as shipped (it ships with no
        -- rows, so every row goes).
        WITH deleted AS (
            DELETE FROM public.quality_check_switched_off WHERE true
            RETURNING 1
        )
        SELECT jsonb_build_object('quality_check_switched_off', jsonb_build_object(
            'deleted_count', (SELECT count(*) FROM deleted)
        )) INTO changed;
        result := result || changed;
    ELSE END CASE;

    RETURN result;
END;
$function$
;

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
    PERFORM admin.add_rls_regular_user_can_read('public.quality_check_switched_off'::regclass);
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

DROP FUNCTION public.quality_check_starting_set();

END;
