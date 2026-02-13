```sql
CREATE OR REPLACE FUNCTION public.reset(confirmed boolean, scope reset_scope)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    result JSONB := '{}'::JSONB;
    changed JSONB;
BEGIN
    IF NOT confirmed THEN
        RAISE EXCEPTION 'Action not confirmed.';
    END IF;

    CASE WHEN scope IN ('units', 'data', 'getting-started', 'all') THEN
        -- Initial pattern application for 'activity'
        WITH deleted AS (
            DELETE FROM public.activity WHERE id > 0 RETURNING *
        )
        SELECT jsonb_build_object(
            'activity', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted)
                )
            ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('units', 'data', 'getting-started', 'all') THEN
        -- Apply pattern for 'location'
        WITH deleted_location AS (
            DELETE FROM public.location WHERE id > 0 RETURNING *
        )
        SELECT jsonb_build_object(
            'location', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_location)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('units', 'data', 'getting-started', 'all') THEN
        -- Apply pattern for 'contact'
        WITH deleted_contact AS (
            DELETE FROM public.contact WHERE id > 0 RETURNING *
        )
        SELECT jsonb_build_object(
            'contact', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_contact)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('units', 'data', 'getting-started', 'all') THEN
        -- Apply pattern for 'person_for_unit'
        WITH deleted_person_for_unit AS (
            DELETE FROM public.person_for_unit WHERE id > 0 RETURNING *
        )
        SELECT jsonb_build_object(
            'person_for_unit', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_person_for_unit)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('units', 'data', 'getting-started', 'all') THEN
        -- Add delete for public.person
        WITH deleted_person AS (
            DELETE FROM public.person WHERE id > 0 RETURNING *
        )
        SELECT jsonb_build_object(
            'person', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_person)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('data', 'getting-started', 'all') THEN
        -- Apply pattern for 'import_job'
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

    CASE WHEN scope IN ('getting-started', 'all') THEN
        -- Apply pattern for 'import_definition'
        -- Must delete BEFORE data_source due to RESTRICT foreign key constraint.
        -- Deleting import_jobs first (above) removes the CASCADE dependency.
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
    
    CASE WHEN scope IN ('units', 'data', 'getting-started', 'all') THEN
        -- Apply pattern for 'tag_for_unit'
        WITH deleted_tag_for_unit AS (
            DELETE FROM public.tag_for_unit WHERE id > 0 RETURNING *
        )
        SELECT jsonb_build_object(
            'tag_for_unit', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_tag_for_unit)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('all') THEN
        -- Add delete for public.tag where type = 'custom'
        WITH deleted_tag AS (
            DELETE FROM public.tag WHERE type = 'custom' RETURNING *
        )
        SELECT jsonb_build_object(
            'tag', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_tag)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('units', 'data', 'getting-started', 'all') THEN
        -- Apply pattern for 'stat_for_unit'
        WITH deleted_stat_for_unit AS (
            DELETE FROM public.stat_for_unit WHERE id > 0 RETURNING *
        )
        SELECT jsonb_build_object(
            'stat_for_unit', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_stat_for_unit)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('all') THEN
        -- Delete all stat_definition entries first, then restore baseline
        WITH deleted_stat_definition AS (
            DELETE FROM public.stat_definition RETURNING *
        )
        SELECT jsonb_build_object(
            'stat_definition', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_stat_definition WHERE code NOT IN ('employees','turnover'))
            )
        ) INTO changed;
        result := result || changed;
        
        -- Restore baseline stat_definition entries
        INSERT INTO public.stat_definition(code, type, frequency, name, description, priority, enabled)
        VALUES
            ('employees', 'int', 'yearly', 'Employees', 'The number of people receiving an official salary with government reporting.', 1, true),
            ('turnover', 'float', 'yearly', 'Turnover', 'The amount (Local Currency)', 2, true);
    ELSE END CASE;

    CASE WHEN scope IN ('units', 'data', 'getting-started', 'all') THEN
        -- Add delete for public.external_ident_type not added by the system
        WITH deleted_external_ident AS (
            DELETE FROM public.external_ident WHERE id > 0 RETURNING *
        )
        SELECT jsonb_build_object(
            'external_ident', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_external_ident)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('all') THEN
        -- Delete all external_ident_type entries first, then restore baseline
        WITH deleted_external_ident_type AS (
            DELETE FROM public.external_ident_type RETURNING *
        )
        SELECT jsonb_build_object(
            'external_ident_type', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_external_ident_type WHERE code NOT IN ('stat_ident','tax_ident'))
            )
        ) INTO changed;
        result := result || changed;
        
        -- Restore baseline external_ident_type entries
        INSERT INTO public.external_ident_type(code, name, priority, description, enabled)
        VALUES
            ('tax_ident', 'Tax Identifier', 1, 'Stable and country unique identifier used for tax reporting.', true),
            ('stat_ident', 'Statistical Identifier', 2, 'Stable identifier generated by Statbus', true);
    ELSE END CASE;

    CASE WHEN scope IN ('units', 'data', 'getting-started', 'all') THEN
        WITH deleted_establishment AS (
            DELETE FROM public.establishment WHERE id > 0 RETURNING *
        )
        SELECT jsonb_build_object(
            'establishment', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_establishment)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('units', 'data', 'getting-started', 'all') THEN
        WITH deleted_legal_unit AS (
            DELETE FROM public.legal_unit WHERE id > 0 RETURNING *
        )
        SELECT jsonb_build_object(
            'legal_unit', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_legal_unit)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('units', 'data', 'getting-started', 'all') THEN
        WITH deleted_enterprise AS (
            DELETE FROM public.enterprise WHERE id > 0 RETURNING *
        )
        SELECT jsonb_build_object(
            'enterprise', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_enterprise)
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
        -- Special handling for tables with 'custom' attribute
        -- Change any children with `parent_id` pointing to an `id` of a row to be deleted,
        -- to point to a NOT custom row instead.
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
        -- Apply pattern for 'sector'
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
        -- Apply pattern for 'legal_form'
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
        -- Apply pattern for 'unit_size'
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
        -- Apply pattern for 'data_source'
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
        -- Apply pattern for 'status'
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
    
    RETURN result;
END;
$function$
```
