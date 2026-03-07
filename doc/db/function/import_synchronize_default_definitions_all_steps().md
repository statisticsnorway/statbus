```sql
CREATE OR REPLACE PROCEDURE import.synchronize_default_definitions_all_steps()
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_def RECORD;
BEGIN
    RAISE DEBUG '--> Running import.synchronize_default_definitions_all_steps...';
    FOR v_def IN
        SELECT id FROM public.import_definition WHERE enabled = TRUE AND custom = FALSE
    LOOP
        RAISE DEBUG '  [-] Synchronizing definition ID: %', v_def.id;
        -- Sync for external_idents step
        IF EXISTS (SELECT 1 FROM public.import_definition_step ids JOIN public.import_step s ON ids.step_id = s.id WHERE ids.definition_id = v_def.id AND s.code = 'external_idents') THEN
            CALL import.synchronize_definition_step_mappings(v_def.id, 'external_idents');
        END IF;

        -- Sync for link_establishment_to_legal_unit step
        IF EXISTS (SELECT 1 FROM public.import_definition_step ids JOIN public.import_step s ON ids.step_id = s.id WHERE ids.definition_id = v_def.id AND s.code = 'link_establishment_to_legal_unit') THEN
            CALL import.synchronize_definition_step_mappings(v_def.id, 'link_establishment_to_legal_unit');
        END IF;

        -- Sync for statistical_variables step
        IF EXISTS (SELECT 1 FROM public.import_definition_step ids JOIN public.import_step s ON ids.step_id = s.id WHERE ids.definition_id = v_def.id AND s.code = 'statistical_variables') THEN
            CALL import.synchronize_definition_step_mappings(v_def.id, 'statistical_variables');
        END IF;
    END LOOP;
    RAISE DEBUG 'Finished import.synchronize_default_definitions_all_steps.';
END;
$procedure$
```
