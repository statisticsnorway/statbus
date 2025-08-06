```sql
CREATE OR REPLACE FUNCTION admin.trigger_validate_import_definition()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_definition_id INT;
    v_step_id INT;
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF TG_TABLE_NAME = 'import_definition' THEN
            RETURN OLD; -- No need to validate a definition that is being deleted
        ELSIF TG_TABLE_NAME IN ('import_definition_step', 'import_source_column', 'import_mapping') THEN
            v_definition_id := OLD.definition_id;
        ELSIF TG_TABLE_NAME = 'import_data_column' THEN
            v_step_id := OLD.step_id;
        ELSIF TG_TABLE_NAME = 'import_step' THEN
            v_step_id := OLD.id;
        END IF;
    ELSE -- INSERT or UPDATE
        IF TG_TABLE_NAME = 'import_definition' THEN
            IF TG_OP = 'UPDATE' THEN
                -- If any core configuration field changed, validation is needed.
                -- Otherwise, skip to prevent recursion if only valid/validation_error or non-core fields changed.
                IF NEW.slug IS DISTINCT FROM OLD.slug OR
                   NEW.data_source_id IS DISTINCT FROM OLD.data_source_id OR
                   NEW.strategy IS DISTINCT FROM OLD.strategy OR
                   NEW.mode IS DISTINCT FROM OLD.mode OR
                   NEW.valid_time_from IS DISTINCT FROM OLD.valid_time_from OR
                   NEW.default_retention_period IS DISTINCT FROM OLD.default_retention_period
                THEN
                    RAISE DEBUG '[% Trigger on %] Core field changed for import_definition ID %, proceeding with validation.', TG_OP, TG_TABLE_NAME, NEW.id;
                    v_definition_id := NEW.id;
                ELSE
                    RAISE DEBUG '[% Trigger on %] Skipping validation for import_definition ID % as no core configuration fields changed in this UPDATE.', TG_OP, TG_TABLE_NAME, NEW.id;
                    RETURN NEW; -- Skip validation
                END IF;
            ELSE -- TG_OP = 'INSERT'
                v_definition_id := NEW.id; -- Always validate on INSERT
            END IF;
        ELSIF TG_TABLE_NAME IN ('import_definition_step', 'import_source_column', 'import_mapping') THEN
            v_definition_id := NEW.definition_id;
        ELSIF TG_TABLE_NAME = 'import_data_column' THEN
            v_step_id := NEW.step_id;
        ELSIF TG_TABLE_NAME = 'import_step' THEN
            v_step_id := NEW.id;
        END IF;
    END IF;

    IF v_definition_id IS NOT NULL THEN
        PERFORM admin.validate_import_definition(v_definition_id);
    ELSIF v_step_id IS NOT NULL THEN
        -- Re-validate all definitions using this step
        FOR v_definition_id IN
            SELECT DISTINCT definition_id
            FROM public.import_definition_step
            WHERE step_id = v_step_id
        LOOP
            PERFORM admin.validate_import_definition(v_definition_id);
        END LOOP;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$function$
```
