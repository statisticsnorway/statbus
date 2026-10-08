-- Down Migration 20261008165621: statbus_477 country upsert updates and keeps reloaded countries
-- Restores both functions exactly as dumped (\sf) before the up migration.
BEGIN;

CREATE OR REPLACE FUNCTION admin.upsert_country()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    INSERT INTO public.country (iso_2, iso_3, iso_num, name, enabled, custom, updated_at)
    VALUES (NEW.iso_2, NEW.iso_3, NEW.iso_num, NEW.name, true, false, statement_timestamp())
    ON CONFLICT (iso_2, iso_3, iso_num, name)
    DO UPDATE SET
        name = EXCLUDED.name,
        custom = false,
        updated_at = statement_timestamp()
    WHERE country.id = EXCLUDED.id;
    RETURN NULL;
END;
$function$
;

CREATE OR REPLACE FUNCTION admin.delete_stale_country()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    DELETE FROM public.country
    WHERE updated_at < statement_timestamp();
    RETURN NULL;
END;
$function$
;

END;
