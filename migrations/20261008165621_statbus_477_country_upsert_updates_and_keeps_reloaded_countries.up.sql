-- Migration 20261008165621: statbus_477 country upsert updates and keeps reloaded countries
--
-- STATBUS-477 family E. country_view is loaded by migrations only (the
-- shipped dbseed/country/country_codes.csv). Two defects:
-- 1. admin.upsert_country conflicted on (iso_2, iso_3, iso_num, name) with
--    WHERE country.id = EXCLUDED.id. The id predicate never fires (identity
--    id), and because name is part of the target a corrected name never even
--    conflicts: it fails on country_iso_2_key. The country key is iso_2
--    (country_iso_2_key); a reload corrects iso_3, iso_num and name.
-- 2. admin.delete_stale_country deleted every country with
--    updated_at < statement_timestamp(). With the no-op upsert that is every
--    country: reloading the shipped file left 0 countries, and with
--    settings.country_id set it aborted on RESTRICT. Stale is now the
--    complement of the codes the statement addressed (as STATBUS-473), and a
--    statement that addressed none deletes nothing.
-- The INSTEAD OF trigger returns the row, so INSERT/COPY report what was
-- stored rather than 0.
BEGIN;

CREATE OR REPLACE FUNCTION admin.upsert_country()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Record that this statement addresses the code, so the statement-level
    -- admin.delete_stale_country removes exactly the complement.
    -- (Triggers on views cannot have transition tables.)
    IF to_regclass('pg_temp.country_addressed') IS NULL THEN
        CREATE TEMP TABLE country_addressed
            ( iso_2 text PRIMARY KEY
            ) ON COMMIT DROP;
    END IF;
    INSERT INTO pg_temp.country_addressed(iso_2)
    VALUES (NEW.iso_2)
    ON CONFLICT DO NOTHING;

    INSERT INTO public.country (iso_2, iso_3, iso_num, name, enabled, custom, updated_at)
    VALUES (NEW.iso_2, NEW.iso_3, NEW.iso_num, NEW.name, true, false, statement_timestamp())
    ON CONFLICT (iso_2)
    DO UPDATE SET
        iso_3 = EXCLUDED.iso_3,
        iso_num = EXCLUDED.iso_num,
        name = EXCLUDED.name,
        custom = false,
        updated_at = statement_timestamp();
    -- Report the written row, so the statement's row count is what was stored.
    RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION admin.delete_stale_country()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- A load through country_view is the complete country list: the countries
    -- the statement did NOT address are stale. admin.upsert_country recorded
    -- every addressed code; a statement that addressed none deletes nothing.
    -- A stale country still referenced (settings, location, person) fails
    -- honestly on its RESTRICT foreign key rather than being kept silently.
    IF to_regclass('pg_temp.country_addressed') IS NULL THEN
        RETURN NULL;
    END IF;

    DELETE FROM public.country AS c
    WHERE NOT EXISTS (
        SELECT 1 FROM pg_temp.country_addressed AS addressed
         WHERE addressed.iso_2 = c.iso_2);

    DROP TABLE pg_temp.country_addressed;
    RETURN NULL;
END;
$function$
;

END;
