BEGIN;

CREATE FUNCTION admin.upsert_activity_category()
RETURNS TRIGGER AS $$
DECLARE
    standardCode text;
    standardId int;
BEGIN
    -- Access the standard code passed as an argument
    standardCode := TG_ARGV[0];
    SELECT id INTO standardId FROM public.activity_category_standard WHERE code = standardCode;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Unknown activity_category_standard.code %', standardCode;
    END IF;

    WITH parent AS (
        SELECT activity_category.id
          FROM public.activity_category
         WHERE standard_id = standardId
           AND path OPERATOR(public.=) public.subltree(NEW.path, 0, public.nlevel(NEW.path) - 1)
    )
    INSERT INTO public.activity_category
        ( standard_id
        , path
        , parent_id
        , name
        , description
        , updated_at
        , enabled
        , custom
        )
    SELECT standardId
         , NEW.path
         , (SELECT id FROM parent)
         , NEW.name
         , NEW.description
         , statement_timestamp()
         , true
         , false
    ON CONFLICT (standard_id, path, enabled)
    DO UPDATE SET parent_id = (SELECT id FROM parent)
                , name = NEW.name
                , description = NEW.description
                , updated_at = statement_timestamp()
                , custom = false
        WHERE activity_category.id = EXCLUDED.id
                ;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;


CREATE FUNCTION admin.delete_stale_activity_category()
RETURNS TRIGGER AS $$
BEGIN
    -- All the `standard_id` with a recent update must be complete.
    WITH changed_activity_category AS (
      SELECT DISTINCT standard_id
      FROM public.activity_category
      WHERE updated_at = statement_timestamp()
    )
    -- Delete activities that have a stale updated_at
    DELETE FROM public.activity_category
    WHERE standard_id IN (SELECT standard_id FROM changed_activity_category)
    AND updated_at < statement_timestamp();
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

END;
