```sql
CREATE OR REPLACE FUNCTION public.lookup_parent_and_derive_code()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    code_pattern_var public.activity_category_code_behaviour;
    derived_code varchar;
    parent_path public.ltree;
BEGIN
    -- Look up the code pattern
    SELECT code_pattern INTO code_pattern_var
    FROM public.activity_category_standard
    WHERE id = NEW.standard_id;

    -- Derive the code based on the code pattern using CASE expression
    CASE code_pattern_var
        WHEN 'digits' THEN
            derived_code := regexp_replace(NEW.path::text, '[^0-9]', '', 'g');
        WHEN 'dot_after_two_digits' THEN
            derived_code := regexp_replace(regexp_replace(NEW.path::text, '[^0-9]', '', 'g'), '^([0-9]{2})(.+)$', '\1.\2');
        ELSE
            RAISE EXCEPTION 'Unknown code pattern: %', code_pattern_var;
    END CASE;

    -- Set the derived code
    NEW.code := derived_code;

    -- Ensure parent_id is consistent with the path
    -- Only update parent_id if path has parent segments
    IF public.nlevel(NEW.path) > 1 THEN
        SELECT id INTO NEW.parent_id
        FROM public.activity_category
        WHERE standard_id = NEW.standard_id
          AND path OPERATOR(public.=) public.subltree(NEW.path, 0, public.nlevel(NEW.path) - 1)
        -- (standard_id, path, enabled) is unique, so this is the enabled
        -- parent, or the disabled one mid-swap (public.reset re-parents
        -- children before it re-enables the system row).
        ORDER BY enabled DESC
        LIMIT 1
        ;
    ELSE
        NEW.parent_id := NULL; -- No parent, set parent_id to NULL
    END IF;

    RETURN NEW;
END;
$function$
```
