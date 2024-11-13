\echo public.legal_form_custom_only
CREATE VIEW public.legal_form_custom_only(code, name)
WITH (security_invoker=on) AS
SELECT ac.code
     , ac.name
FROM public.legal_form AS ac
WHERE ac.active
  AND ac.custom
ORDER BY code;

\echo admin.legal_form_custom_only_upsert
CREATE FUNCTION admin.legal_form_custom_only_upsert()
RETURNS TRIGGER AS $$
DECLARE
    row RECORD;
BEGIN
    -- Perform an upsert operation on public.legal_form
    INSERT INTO public.legal_form
        ( code
        , name
        , updated_at
        , active
        , custom
        )
    VALUES
        ( NEW.code
        , NEW.name
        , statement_timestamp()
        , TRUE -- Active
        , TRUE -- Custom
        )
    ON CONFLICT (code, active, custom)
    DO UPDATE
        SET name = NEW.name
          , updated_at = statement_timestamp()
          , active = TRUE
          , custom = TRUE
       WHERE legal_form.id = EXCLUDED.id
       RETURNING * INTO row;
    RAISE DEBUG 'UPSERTED %', to_json(row);

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER legal_form_custom_only_upsert
INSTEAD OF INSERT ON public.legal_form_custom_only
FOR EACH ROW
EXECUTE FUNCTION admin.legal_form_custom_only_upsert();


\echo admin.legal_form_custom_only_prepare
CREATE OR REPLACE FUNCTION admin.legal_form_custom_only_prepare()
RETURNS TRIGGER AS $$
BEGIN
    -- Deactivate all non-custom legal_form entries before insertion
    UPDATE public.legal_form
       SET active = false
     WHERE active = true
       AND custom = false;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER legal_form_custom_only_prepare_trigger
BEFORE INSERT ON public.legal_form_custom_only
FOR EACH STATEMENT
EXECUTE FUNCTION admin.legal_form_custom_only_prepare();