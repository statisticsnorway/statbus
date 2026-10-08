-- Down Migration 20261008164443: statbus_477 legal_form upserts update existing rows
--
-- Restores the three upsert functions exactly as dumped (\sf) before the up
-- migration and drops the (code, custom) key. The dedupe of the up migration is
-- a data correction and is deliberately not reverted.
BEGIN;

ALTER TABLE public.legal_form DROP CONSTRAINT legal_form_code_custom_key;

CREATE OR REPLACE FUNCTION admin.upsert_legal_form_custom()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    row RECORD;
BEGIN
    INSERT INTO public.legal_form (code, name, enabled, custom, updated_at)
    VALUES (NEW.code, NEW.name, TRUE, 't', statement_timestamp())
    ON CONFLICT (enabled, code) DO UPDATE SET
        name = NEW.name, enabled = TRUE,
        custom = 't',
        updated_at = statement_timestamp()
    WHERE legal_form.id = EXCLUDED.id
    RETURNING * INTO row;

    RAISE DEBUG 'UPSERTED %', to_json(row);

    RETURN NULL;
END;
$function$
;

CREATE OR REPLACE FUNCTION admin.upsert_legal_form_system()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    row RECORD;
BEGIN
    INSERT INTO public.legal_form (code, name, enabled, custom, updated_at)
    VALUES (NEW.code, NEW.name, TRUE, 'f', statement_timestamp())
    ON CONFLICT (enabled, code) DO UPDATE SET
        name = NEW.name, enabled = TRUE,
        custom = 'f',
        updated_at = statement_timestamp()
    WHERE legal_form.id = EXCLUDED.id
    RETURNING * INTO row;

    RAISE DEBUG 'UPSERTED %', to_json(row);

    RETURN NULL;
END;
$function$
;

CREATE OR REPLACE FUNCTION admin.legal_form_custom_only_upsert()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    row RECORD;
BEGIN
    -- Perform an upsert operation on public.legal_form
    INSERT INTO public.legal_form
        ( code
        , name
        , updated_at
        , enabled
        , custom
        )
    VALUES
        ( NEW.code
        , NEW.name
        , statement_timestamp()
        , TRUE -- Active
        , TRUE -- Custom
        )
    ON CONFLICT (code, enabled, custom)
    DO UPDATE
        SET name = NEW.name
          , updated_at = statement_timestamp()
          , enabled = TRUE
          , custom = TRUE
       WHERE legal_form.id = EXCLUDED.id
       RETURNING * INTO row;
    RAISE DEBUG 'UPSERTED %', to_json(row);

    RETURN NULL;
END;
$function$
;

END;
