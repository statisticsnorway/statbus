```sql
CREATE OR REPLACE FUNCTION admin.prevent_changes_to_non_draft_definition()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    def public.import_definition;
BEGIN
    IF TG_TABLE_NAME = 'import_definition' THEN
        -- For direct changes to import_definition
        IF NOT NEW.draft AND OLD.draft = NEW.draft THEN
            RAISE EXCEPTION 'Can only modify import definition % when in draft mode', OLD.id;
        END IF;
    ELSE
        -- For changes to related tables (mapping, source_column)
        SELECT * INTO def FROM public.import_definition WHERE id =
            CASE TG_TABLE_NAME
                WHEN 'import_mapping' THEN
                    CASE TG_OP
                        WHEN 'DELETE' THEN OLD.definition_id
                        ELSE NEW.definition_id
                    END
                WHEN 'import_source_column' THEN NEW.definition_id
            END;

        IF NOT def.draft THEN
            RAISE EXCEPTION 'Can only modify % for import definition % when in draft mode',
                TG_TABLE_NAME, def.id;
        END IF;
    END IF;
    RETURN CASE TG_OP WHEN 'DELETE' THEN OLD ELSE NEW END;
END;
$function$
```
