-- Migration 20261008164443: statbus_477 legal_form upserts update existing rows
--
-- STATBUS-477 family A. The three upsert triggers behind legal_form_custom_only
-- (the getting-started upload page), legal_form_custom and legal_form_system
-- ended in ON CONFLICT ... DO UPDATE ... WHERE legal_form.id = EXCLUDED.id.
-- legal_form.id is GENERATED ALWAYS AS IDENTITY, so the update never fired:
-- a re-upload with a corrected name was a silent no-op (INSERT 0 0).
--
-- Dropping only the predicate is NOT a fix: legal_form_custom and
-- legal_form_system conflict on (enabled, code), which treats an enabled
-- custom override and an enabled system row as one row, so a system reload
-- would overwrite the operator's custom override (observed in a clone).
-- The key that distinguishes them is (code, custom): at most one system row
-- and one custom override per code. It becomes a constraint (after a
-- deterministic dedupe) and every upsert conflicts on it:
--   * custom upserts update the custom row only, and enable it;
--   * the system upsert updates the system row's label only (its enabled
--     flag is the operator's choice), and a new system code starts disabled
--     while an enabled custom override of the same code exists.
-- The INSTEAD OF triggers return the row, so INSERT/COPY report what was
-- stored rather than 0.
BEGIN;

-- Make (code, custom) a real key. Boxes ran the broken upserts for years: a
-- re-upload of a custom code whose override had been disabled inserted a
-- second custom row (the old key (code, enabled, custom) allows one enabled
-- and one disabled), and likewise for system rows under (enabled, code).
-- Dedupe deterministically from the rows alone: the CANONICAL row of a key is
-- the enabled one (the row every view shows), then the lowest id. References
-- (legal_unit.legal_form_id, the only foreign key into legal_form) move to
-- the canonical row first, then the redundant rows are removed.
CREATE TEMP TABLE legal_form_redundant ON COMMIT DROP AS
SELECT ranked.id AS redundant_id
     , ranked.canonical_id
  FROM (
    SELECT lf.id
         , first_value(lf.id) OVER (
             PARTITION BY lf.code, lf.custom
             ORDER BY lf.enabled DESC, lf.id
           ) AS canonical_id
      FROM public.legal_form AS lf
  ) AS ranked
 WHERE ranked.id <> ranked.canonical_id;

UPDATE public.legal_unit AS lu
   SET legal_form_id = r.canonical_id
  FROM pg_temp.legal_form_redundant AS r
 WHERE lu.legal_form_id = r.redundant_id;

DO $report_legal_form_dedupe$
DECLARE
    _deleted_count bigint;
BEGIN
    WITH deleted AS (
        DELETE FROM public.legal_form AS lf
         USING pg_temp.legal_form_redundant AS r
         WHERE lf.id = r.redundant_id
        RETURNING lf.id
    )
    SELECT count(*) INTO _deleted_count FROM deleted;
    RAISE NOTICE 'STATBUS-477: removed % redundant legal_form row(s) duplicating (code, custom)', _deleted_count;
END;
$report_legal_form_dedupe$;

ALTER TABLE public.legal_form
  ADD CONSTRAINT legal_form_code_custom_key UNIQUE (code, custom);

CREATE OR REPLACE FUNCTION admin.upsert_legal_form_custom()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    row RECORD;
BEGIN
    INSERT INTO public.legal_form (code, name, enabled, custom, updated_at)
    VALUES (NEW.code, NEW.name, TRUE, 't', statement_timestamp())
    ON CONFLICT (code, custom) DO UPDATE SET
        name = NEW.name, enabled = TRUE,
        updated_at = statement_timestamp()
    RETURNING * INTO row;

    RAISE DEBUG 'UPSERTED %', to_json(row);

    -- Report the written row, so the statement's row count is what was stored.
    RETURN NEW;
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
    -- The system row is updated on (code, custom), never the custom override.
    -- A reload corrects the label only: an existing system row keeps its
    -- enabled flag (the operator's custom-only upload disables system rows on
    -- purpose), and a new system code starts disabled while an enabled custom
    -- override of the code exists.
    INSERT INTO public.legal_form (code, name, enabled, custom, updated_at)
    VALUES
        ( NEW.code
        , NEW.name
        , NOT EXISTS (
            SELECT 1 FROM public.legal_form AS override
             WHERE override.code = NEW.code
               AND override.custom
               AND override.enabled)
        , 'f'
        , statement_timestamp()
        )
    ON CONFLICT (code, custom) DO UPDATE SET
        name = NEW.name,
        updated_at = statement_timestamp()
    RETURNING * INTO row;

    RAISE DEBUG 'UPSERTED %', to_json(row);

    -- Report the written row, so the statement's row count is what was stored.
    RETURN NEW;
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
    ON CONFLICT (code, custom)
    DO UPDATE
        SET name = NEW.name
          , updated_at = statement_timestamp()
          , enabled = TRUE
       RETURNING * INTO row;
    RAISE DEBUG 'UPSERTED %', to_json(row);

    -- Report the written row, so the statement's row count (INSERT 0 n,
    -- COPY n) is what was stored, never a silent 0.
    RETURN NEW;
END;
$function$
;

END;
