-- View for insert of Norwegian Establishment (Underenhet)
\echo public.establishment_brreg_view
CREATE VIEW public.establishment_brreg_view
WITH (security_invoker=on) AS
SELECT '' AS "organisasjonsnummer"
     , '' AS "navn"
     , '' AS "organisasjonsform.kode"
     , '' AS "organisasjonsform.beskrivelse"
     , '' AS "naeringskode1.kode"
     , '' AS "naeringskode1.beskrivelse"
     , '' AS "naeringskode2.kode"
     , '' AS "naeringskode2.beskrivelse"
     , '' AS "naeringskode3.kode"
     , '' AS "naeringskode3.beskrivelse"
     , '' AS "hjelpeenhetskode.kode"
     , '' AS "hjelpeenhetskode.beskrivelse"
     , '' AS "harRegistrertAntallAnsatte"
     , '' AS "antallAnsatte"
     , '' AS "hjemmeside"
     , '' AS "postadresse.adresse"
     , '' AS "postadresse.poststed"
     , '' AS "postadresse.postnummer"
     , '' AS "postadresse.kommune"
     , '' AS "postadresse.kommunenummer"
     , '' AS "postadresse.land"
     , '' AS "postadresse.landkode"
     , '' AS "beliggenhetsadresse.adresse"
     , '' AS "beliggenhetsadresse.poststed"
     , '' AS "beliggenhetsadresse.postnummer"
     , '' AS "beliggenhetsadresse.kommune"
     , '' AS "beliggenhetsadresse.kommunenummer"
     , '' AS "beliggenhetsadresse.land"
     , '' AS "beliggenhetsadresse.landkode"
     , '' AS "registreringsdatoIEnhetsregisteret"
     , '' AS "frivilligMvaRegistrertBeskrivelser"
     , '' AS "registrertIMvaregisteret"
     , '' AS "oppstartsdato"
     , '' AS "datoEierskifte"
     , '' AS "overordnetEnhet"
     , '' AS "nedleggelsesdato"
     ;


\echo admin.upsert_establishment_brreg_view
CREATE FUNCTION admin.upsert_establishment_brreg_view()
RETURNS TRIGGER AS $$
DECLARE
  result RECORD;
BEGIN
    WITH su AS (
        SELECT *
        FROM statbus_user
        WHERE uuid = auth.uid()
        LIMIT 1
    ), upsert_data AS (
        SELECT
          NEW."organisasjonsnummer" AS tax_ident
        , '2023-01-01'::date AS valid_from
        , 'infinity'::date AS valid_to
        , CASE NEW."oppstartsdato"
          WHEN NULL THEN NULL
          WHEN '' THEN NULL
          ELSE NEW."oppstartsdato"::date
          END AS birth_date
        , NEW."navn" AS name
        , true AS active
        , 'Batch import' AS edit_comment
        , (SELECT id FROM su) AS edit_by_user_id
    ),
    update_outcome AS (
        UPDATE public.establishment
        SET valid_from = upsert_data.valid_from
          , valid_to = upsert_data.valid_to
          , birth_date = upsert_data.birth_date
          , name = upsert_data.name
          , active = upsert_data.active
          , edit_comment = upsert_data.edit_comment
          , edit_by_user_id = upsert_data.edit_by_user_id
        FROM upsert_data
        WHERE establishment.tax_ident = upsert_data.tax_ident
          AND establishment.valid_to = 'infinity'::date
        RETURNING 'update'::text AS action, establishment.id
    ),
    insert_outcome AS (
        INSERT INTO public.establishment
          ( tax_ident
          , valid_from
          , valid_to
          , birth_date
          , name
          , active
          , edit_comment
          , edit_by_user_id
          )
        SELECT
            upsert_data.tax_ident
          , upsert_data.valid_from
          , upsert_data.valid_to
          , upsert_data.birth_date
          , upsert_data.name
          , upsert_data.active
          , upsert_data.edit_comment
          , upsert_data.edit_by_user_id
        FROM upsert_data
        WHERE NOT EXISTS (SELECT id FROM update_outcome LIMIT 1)
        RETURNING 'insert'::text AS action, id
    ), combined AS (
      SELECT * FROM update_outcome UNION ALL SELECT * FROM insert_outcome
    )
    SELECT * INTO result FROM combined;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;


-- Create triggers for the view
CREATE TRIGGER upsert_establishment_brreg_view
INSTEAD OF INSERT ON public.establishment_brreg_view
FOR EACH ROW
EXECUTE FUNCTION admin.upsert_establishment_brreg_view();