--DROP SCHEMA gh CASCADE;

-- gh => generated history
CREATE SCHEMA IF NOT EXISTS gh;

CREATE OR REPLACE VIEW gh.enhet_for_view_import AS
SELECT "organisasjonsnummer" AS tax_ident
     , "navn" AS name
     , "stiftelsesdato" AS birth_date
     -- There is no death date, the entry simply vanishes!
     --, "nedleggelsesdato" AS death_date
     , "forretningsadresse.adresse" AS physical_address_part1
     , "forretningsadresse.postnummer" AS physical_postal_code
     , "forretningsadresse.poststed"   AS physical_postal_place
     , "forretningsadresse.kommunenummer" AS physical_region_code
     , "forretningsadresse.landkode" AS physical_country_code_2
     , "postadresse.adresse" AS postal_address_part1
     , "postadresse.poststed" AS postal_postal_code
     , "postadresse.postnummer" AS postal_postal_place
     , "postadresse.kommunenummer" AS postal_region_code
     , "postadresse.landkode" AS postal_country_code_2
     , "naeringskode1.kode" AS primary_activity_category_code
     , "naeringskode2.kode" AS secondary_activity_category_code
     , "institusjonellSektorkode.kode" AS sector_code
     , "organisasjonsform.kode" AS legal_form_code
FROM brreg.enhet;


CREATE OR REPLACE VIEW gh.underenhet_for_view_import AS
SELECT "organisasjonsnummer" AS tax_ident
     , "overordnetEnhet" AS legal_unit_tax_ident
     , "navn" AS name
     , "oppstartsdato" AS birth_date
     , "nedleggelsesdato" AS death_date
     , "beliggenhetsadresse.adresse" AS physical_address_part1
     , "beliggenhetsadresse.postnummer" AS physical_postal_code
     , "beliggenhetsadresse.poststed"   AS physical_postal_place
     , "beliggenhetsadresse.kommunenummer" AS physical_region_code
     , "beliggenhetsadresse.landkode" AS physical_country_code_2
     , "postadresse.adresse" AS postal_address_part1
     , "postadresse.poststed" AS postal_postal_code
     , "postadresse.postnummer" AS postal_postal_place
     , "postadresse.kommunenummer" AS postal_region_code
     , "postadresse.landkode" AS postal_country_code_2
     , "naeringskode1.kode" AS primary_activity_category_code
     , "naeringskode2.kode" AS secondary_activity_category_code
     , "antallAnsatte" AS employees
FROM brreg.underenhet;


CREATE UNLOGGED TABLE IF NOT EXISTS gh.legal_unit_info(
     ident  TEXT  UNIQUE NOT NULL ,
     periodic_random FLOAT                 ,
     used   BOOL
);
CREATE INDEX IF NOT EXISTS idx_legal_unit_info_ident  ON gh.legal_unit_info(ident);
CREATE INDEX IF NOT EXISTS idx_legal_unit_info_periodic_random ON gh.legal_unit_info(periodic_random);
CREATE INDEX IF NOT EXISTS idx_legal_unit_info_used   ON gh.legal_unit_info(used);

CREATE UNLOGGED TABLE IF NOT EXISTS gh.establishment_info(
     ident            TEXT  UNIQUE NOT NULL ,
     legal_unit_ident TEXT  NOT NULL        ,
     periodic_random           FLOAT                 ,
     used             BOOL
);
CREATE INDEX IF NOT EXISTS idx_establishment_info_ident            ON gh.establishment_info(ident);
CREATE INDEX IF NOT EXISTS idx_establishment_info_legal_unit_ident ON gh.establishment_info(legal_unit_ident);
CREATE INDEX IF NOT EXISTS idx_establishment_info_periodic_random           ON gh.establishment_info(periodic_random);
CREATE INDEX IF NOT EXISTS idx_establishment_info_used             ON gh.establishment_info(used);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'sample_action') THEN
        CREATE TYPE gh.sample_action AS ENUM ('die','grow','change_legal_unit','shrink_establishments','change_establishments','grow_establishments','preserve');
    END IF;
END
$$;

-- Make a plan
CREATE UNLOGGED TABLE IF NOT EXISTS gh.sample(
     id               INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY ,
     legal_unit_ident TEXT    NOT NULL                                 ,
     year             INTEGER NOT NULL                                 ,
     periodic_random           FLOAT   NOT NULL                                 ,
     legal_unit       JSONB   NOT NULL                                 ,
     establishments   JSONB   NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_sample_legal_unit_ident    ON gh.sample(legal_unit_ident);
CREATE INDEX IF NOT EXISTS idx_sample_year                ON gh.sample(year);
CREATE INDEX IF NOT EXISTS idx_sample_periodic_random                ON gh.sample(periodic_random);

DO $$
DECLARE
  draw_random BOOL;
BEGIN
  SELECT NOT EXISTS (SELECT * FROM gh.legal_unit_info) INTO draw_random;
  IF draw_random THEN
    RAISE NOTICE 'Draw Random';
    INSERT INTO gh.legal_unit_info(ident,periodic_random,used)
    SELECT "organisasjonsnummer" AS ident
         , random() AS periodic_random
         , false AS used
      FROM brreg.enhet;

    INSERT INTO gh.establishment_info(ident,legal_unit_ident,periodic_random,used)
    SELECT "organisasjonsnummer" AS ident
         , "overordnetEnhet" AS legal_unit_ident
         , random() AS periodic_random
         , false AS used
      FROM brreg.underenhet;
  END IF;
END;
$$;



DO LANGUAGE plpgsql $$
DECLARE
  populate_sample BOOL;
  start_year DATE := '2000-01-01'::DATE;
  stop_year  DATE := '2024-01-01'::DATE;
  seed_size  INTEGER := 100;
  current_year DATE;
  next_year DATE;
  rec RECORD; -- Declare a record to hold your query results
  new_establishment JSONB;
  new_establishments JSONB := '[]'::JSONB;
  used_ident TEXT;
  element JSONB;
BEGIN
  SELECT NOT EXISTS (SELECT * FROM gh.sample) INTO populate_sample;
  IF populate_sample THEN
    RAISE NOTICE 'Populate Sample';
    WITH start_selection AS (
        SELECT lui.ident, lui.periodic_random FROM gh.legal_unit_info AS lui
        -- TODO: Decide if a certion proportion of the legal units must have establishments?
        WHERE EXISTS (
          SELECT *
          FROM gh.establishment_info AS esi
          WHERE esi.legal_unit_ident = lui.ident
        )
        ORDER BY periodic_random
        LIMIT seed_size
    )
    INSERT INTO gh.sample (legal_unit_ident,year,periodic_random,legal_unit,establishments)
    SELECT lui.ident                         AS legal_unit_ident
         , extract(YEAR FROM start_year) AS year
         , random()                      AS periodic_random
         , (
          SELECT to_jsonb(e.*)
          FROM brreg.enhet AS e
          WHERE e."organisasjonsnummer" = lui.ident
          ) AS legal_unit
         , (
          SELECT COALESCE(jsonb_agg(to_jsonb(u.*)),'[]'::JSONB)
          FROM brreg.underenhet AS u
          WHERE u."overordnetEnhet" = lui.ident
          ) AS establishments
      FROM start_selection AS lui
    ;

    UPDATE gh.legal_unit_info
    SET used = true
    WHERE NOT used AND ident IN (
        SELECT legal_unit_ident FROM gh.sample
    );

    UPDATE gh.establishment_info
    SET used = true
    WHERE NOT used AND legal_unit_ident IN (
        SELECT legal_unit_ident FROM gh.sample
    );

    current_year := start_year;

    WHILE current_year < stop_year LOOP
        next_year := current_year + INTERVAL '1 year';

        FOR rec IN
            WITH basis AS (
              SELECT
                  legal_unit_ident,
                  EXTRACT(YEAR FROM next_year) AS year,
                  random() AS periodic_random,
                  CASE
                  WHEN random() < 0.1 THEN 'die'
                  WHEN random() < 0.2 THEN 'grow'
                  WHEN random() < 0.3 THEN 'change_legal_unit'
                  WHEN random() < 0.4 THEN 'shrink_establishments'
                  WHEN random() < 0.5 THEN 'change_establishments'
                  WHEN random() < 0.6 THEN 'grow_establishments'
                  ELSE 'preserve'
                  END AS action,
                  legal_unit,
                  establishments
              FROM
                  gh.sample
              WHERE
                year = EXTRACT(YEAR FROM current_year)
            )
            SELECT * FROM basis
        LOOP
            RAISE NOTICE 'year: % legal_unit_ident:% action: %', next_year, rec.legal_unit_ident, rec.action;
            IF rec.action = 'die' THEN
                -- Logic to not insert, effectively skip this iteration.
            ELSIF rec.action = 'grow' THEN
                -- Insert the existing legal unit first as per the existing logic
                INSERT INTO gh.sample (legal_unit_ident, year, periodic_random, legal_unit, establishments)
                VALUES (rec.legal_unit_ident, EXTRACT(YEAR FROM next_year), random(), rec.legal_unit, rec.establishments);

                -- Determine the number of new entries to add
                DECLARE
                    num_new_entries INT := floor(random() * 5 + 1)::INT; -- for example, between 1 and 5
                    i INT := 0;
                    new_legal_unit JSONB;
                    new_establishments JSONB;
                    used_ident TEXT;
                BEGIN
                    RAISE NOTICE 'Adding % legal_units', num_new_entries;
                    WHILE i < num_new_entries LOOP
                        SELECT to_jsonb(e.*) AS legal_unit
                             , (
                               SELECT COALESCE(jsonb_agg(to_jsonb(u.*)), '[]'::JSONB)
                               FROM brreg.underenhet AS u
                               WHERE u."overordnetEnhet" = lui.ident
                                 AND NOT lui.used
                             ) AS establishments
                             , lui.ident
                             INTO new_legal_unit, new_establishments, used_ident
                        FROM gh.legal_unit_info AS lui
                        JOIN brreg.enhet AS e ON e."organisasjonsnummer" = lui.ident
                        WHERE NOT lui.used
                        ORDER BY lui.periodic_random
                        LIMIT 1;

                        UPDATE gh.legal_unit_info
                        SET used = true
                        WHERE ident = used_ident;

                        UPDATE gh.establishment_info
                        SET used = true
                        WHERE NOT used AND legal_unit_ident = used_ident;

                        INSERT INTO gh.sample (legal_unit_ident, year, periodic_random, legal_unit, establishments)
                        VALUES (used_ident, EXTRACT(YEAR FROM next_year), random(), new_legal_unit, new_establishments);

                        i := i + 1;
                    END LOOP;
                END;
            ELSIF rec.action = 'change_legal_unit' THEN
               -- Select first NOT used from gh.legal_unit_info joined with brreg.enhet on lui.ident = e."organisasjonsnummer" ordered by periodic_random.
               -- Mark the gh.legal_unit_info as used = true
               -- Take a jsonb of the data, except keeping the sample.ident - in effect replacing the data with the data of a random sample.
               SELECT to_jsonb(e.*)
                     - 'organisasjonsnummer'
                    || jsonb_build_object('organisasjonsnummer', rec.legal_unit_ident)
                    , lui.ident
                    INTO rec.legal_unit
                       , used_ident
               FROM gh.legal_unit_info AS lui
               JOIN brreg.enhet AS e ON e."organisasjonsnummer" = lui.ident
               WHERE NOT used
               ORDER by periodic_random
               LIMIT 1;

               UPDATE gh.legal_unit_info
               SET used = true
               WHERE NOT used AND ident = used_ident;

               UPDATE gh.establishment_info
               SET used = true
               WHERE NOT used AND legal_unit_ident = used_ident;

               INSERT INTO gh.sample (legal_unit_ident, year, periodic_random, legal_unit, establishments)
               VALUES (rec.legal_unit_ident, EXTRACT(YEAR FROM next_year), random(), rec.legal_unit, rec.establishments);

            ELSIF rec.action = 'shrink_establishments' THEN
               -- iterate jsonb array of establishments and make a 10% chance of skipping (dropping) each entry.
               FOR element IN SELECT * FROM jsonb_array_elements(COALESCE(rec.establishments,'[]'::JSONB))
               LOOP
                   IF random() <= 0.1 THEN
                       RAISE NOTICE 'year: % Removing establishment %', next_year, element->>'organisasjonsnummer';
                       new_establishments := new_establishments || jsonb_build_array(element);
                   ELSE
                       RAISE NOTICE 'year: % Keeping establishment %', next_year, element->>'organisasjonsnummer';
                   END IF;
               END LOOP;
               rec.establishments := new_establishments;

               INSERT INTO gh.sample (legal_unit_ident, year, periodic_random, legal_unit, establishments)
               VALUES (rec.legal_unit_ident, EXTRACT(YEAR FROM next_year), random(), rec.legal_unit, rec.establishments);

            ELSIF rec.action = 'change_establishments' THEN
                -- For each establishment, make a 50% chance of selecting a NOT used gh.establishment_info joined with brreg.underenhet on esi.ident = u."organisasjonsnummer"
               FOR element IN SELECT * FROM jsonb_array_elements(COALESCE(rec.establishments,'[]'::JSONB))
               LOOP
                   IF random() <= 0.3 THEN
                     RAISE NOTICE 'year: % Change establishment %', next_year, element->>'organisasjonsnummer';
                     SELECT to_jsonb(u.*)
                           - 'organisasjonsnummer'
                           - 'overordnetEnhet'
                          || jsonb_build_object(
                              'organisasjonsnummer', element ->> 'organisasjonsnummer',
                              'overordnetEnhet', element ->> 'overordnetEnhet'
                            ) AS establishment
                          , esi.ident
                          INTO new_establishment
                             , used_ident
                     FROM gh.establishment_info AS esi
                     JOIN brreg.underenhet AS u ON u."organisasjonsnummer" = esi.ident
                     WHERE NOT esi.used
                     ORDER by esi.periodic_random
                     LIMIT 1;

                     UPDATE gh.establishment_info
                     SET used = true
                     WHERE NOT used AND ident = used_ident ;

                     new_establishments := new_establishments || jsonb_build_array(new_establishment);
                   ELSE
                     RAISE NOTICE 'year: % Keep establishment %', next_year, element->>'organisasjonsnummer';
                     new_establishments := new_establishments || jsonb_build_array(element);
                   END IF;
               END LOOP;
               rec.establishments := new_establishments;

               INSERT INTO gh.sample (legal_unit_ident, year, periodic_random, legal_unit, establishments)
               VALUES (rec.legal_unit_ident, EXTRACT(YEAR FROM next_year), random(), rec.legal_unit, rec.establishments);

            ELSIF rec.action = 'grow_establishments' THEN
                  -- Draw the estbalishemnts from  NOT used gh.establishment_info joined with brreg.underenhet on esi.ident = u."organisasjonsnummer"
                DECLARE
                    establishment_count INTEGER;
                    new_establishments_count INTEGER;
                    i INTEGER := 0;
                    establishment_to_add JSONB;
                    used_ident TEXT;
                BEGIN
                    -- Determine the current number of establishments
                    SELECT jsonb_array_length(rec.establishments) INTO establishment_count;

                    -- Decide how many new establishments to add (from 1 to establishment_count)
                    new_establishments_count := floor((random() + 1) * log(establishment_count + 1 + exp(1)))::INTEGER;
                    RAISE NOTICE 'year: % Adding % establishments', next_year, new_establishments_count;

                    -- Add new establishments
                    WHILE i < new_establishments_count LOOP
                        -- Select an unused establishment and its identifier
                        SELECT to_jsonb(u.*)
                            - 'overordnetEnhet'
                            || jsonb_build_object(
                                'overordnetEnhet', rec.legal_unit_ident
                            )
                            , esi.ident
                            INTO establishment_to_add
                               , used_ident
                        FROM gh.establishment_info AS esi
                        JOIN brreg.underenhet AS u ON u."organisasjonsnummer" = esi.ident
                        WHERE NOT esi.used
                        ORDER BY esi.periodic_random
                        LIMIT 1;

                        -- Mark the selected establishment as used
                        UPDATE gh.establishment_info
                        SET used = true
                        WHERE ident = used_ident;

                        -- Append the new establishment to the establishments array
                        rec.establishments := rec.establishments || jsonb_build_array(establishment_to_add);

                        RAISE NOTICE 'year: % Added establishment %', next_year, used_ident;

                        i := i + 1;
                    END LOOP;

                    INSERT INTO gh.sample (legal_unit_ident, year, periodic_random, legal_unit, establishments)
                    VALUES (rec.legal_unit_ident, EXTRACT(YEAR FROM next_year), random(), rec.legal_unit, rec.establishments);

                END;
            ELSIF rec.action = 'preserve' THEN
                -- Preserve, directly insert.
                INSERT INTO gh.sample (legal_unit_ident, year, periodic_random, legal_unit, establishments)
                VALUES (rec.legal_unit_ident, EXTRACT(YEAR FROM next_year), random(), rec.legal_unit, rec.establishments);
            ELSE
                RAISE EXCEPTION 'Unhandled action: %', rec.action;
            END IF;
        END LOOP;

        -- Move to the next year
        current_year := next_year;
    END LOOP;
  END IF;
END;
$$;


-- Example selection for export to file.
SELECT legal_unit.*
FROM gh.sample AS sample
JOIN LATERAL jsonb_populate_recordset(NULL::brreg.enhet, sample.legal_unit) AS legal_unit ON true
WHERE sample.year = 2024;


SELECT establishment.*
FROM gh.sample AS sample
CROSS JOIN LATERAL jsonb_array_elements(sample.establishments) AS establishment_element
JOIN LATERAL jsonb_populate_recordset(NULL::brreg.underenhet, jsonb_build_array(establishment_element)) AS establishment ON true
WHERE sample.year = 2024;

-- \copy (SELECT * FROM brreg.enhet WHERE "organisasjonsnummer" IN (SELECT enhet_orgnr FROM gh.selection ORDER BY random LIMIT 5000)) TO 'samples/norway/enheter-selection-cli-with-mapping-import.csv' WITH (HEADER true, FORMAT csv, DELIMITER ',', QUOTE '"', FORCE_QUOTE *);
-- \copy (SELECT * FROM brreg.underenhet WHERE "overordnetEnhet" IN (SELECT enhet_orgnr FROM gh.selection ORDER BY random LIMIT 5000)) TO 'samples/norway/underenheter-selection-cli-with-mapping-import.csv' WITH (HEADER true, FORMAT csv, DELIMITER ',', QUOTE '"', FORCE_QUOTE *);

-- \copy (SELECT * FROM gh.enhet_for_view_import WHERE tax_ident IN (SELECT enhet_orgnr FROM gh.selection ORDER BY random LIMIT 100)) TO 'samples/norway/enheter-selection-web-import.csv' WITH (HEADER true, FORMAT csv, DELIMITER ',', QUOTE '"', FORCE_QUOTE *);
-- \copy (SELECT * FROM brreg.underenhet_for_view_import WHERE legal_unit_tax_ident IN (SELECT enhet_orgnr FROM gh.selection ORDER BY random LIMIT 100)) TO 'samples/norway/underenheter-selection-web-import.csv' WITH (HEADER true, FORMAT csv, DELIMITER ',', QUOTE '"', FORCE_QUOTE *);
