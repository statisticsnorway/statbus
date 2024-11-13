```sql
                               View "public.establishment_brreg_view"
               Column               | Type | Collation | Nullable | Default | Storage  | Description 
------------------------------------+------+-----------+----------+---------+----------+-------------
 organisasjonsnummer                | text |           |          |         | extended | 
 navn                               | text |           |          |         | extended | 
 organisasjonsform.kode             | text |           |          |         | extended | 
 organisasjonsform.beskrivelse      | text |           |          |         | extended | 
 naeringskode1.kode                 | text |           |          |         | extended | 
 naeringskode1.beskrivelse          | text |           |          |         | extended | 
 naeringskode2.kode                 | text |           |          |         | extended | 
 naeringskode2.beskrivelse          | text |           |          |         | extended | 
 naeringskode3.kode                 | text |           |          |         | extended | 
 naeringskode3.beskrivelse          | text |           |          |         | extended | 
 hjelpeenhetskode.kode              | text |           |          |         | extended | 
 hjelpeenhetskode.beskrivelse       | text |           |          |         | extended | 
 harRegistrertAntallAnsatte         | text |           |          |         | extended | 
 antallAnsatte                      | text |           |          |         | extended | 
 hjemmeside                         | text |           |          |         | extended | 
 postadresse.adresse                | text |           |          |         | extended | 
 postadresse.poststed               | text |           |          |         | extended | 
 postadresse.postnummer             | text |           |          |         | extended | 
 postadresse.kommune                | text |           |          |         | extended | 
 postadresse.kommunenummer          | text |           |          |         | extended | 
 postadresse.land                   | text |           |          |         | extended | 
 postadresse.landkode               | text |           |          |         | extended | 
 beliggenhetsadresse.adresse        | text |           |          |         | extended | 
 beliggenhetsadresse.poststed       | text |           |          |         | extended | 
 beliggenhetsadresse.postnummer     | text |           |          |         | extended | 
 beliggenhetsadresse.kommune        | text |           |          |         | extended | 
 beliggenhetsadresse.kommunenummer  | text |           |          |         | extended | 
 beliggenhetsadresse.land           | text |           |          |         | extended | 
 beliggenhetsadresse.landkode       | text |           |          |         | extended | 
 registreringsdatoIEnhetsregisteret | text |           |          |         | extended | 
 frivilligMvaRegistrertBeskrivelser | text |           |          |         | extended | 
 registrertIMvaregisteret           | text |           |          |         | extended | 
 oppstartsdato                      | text |           |          |         | extended | 
 datoEierskifte                     | text |           |          |         | extended | 
 overordnetEnhet                    | text |           |          |         | extended | 
 nedleggelsesdato                   | text |           |          |         | extended | 
View definition:
 SELECT ''::text AS organisasjonsnummer,
    ''::text AS navn,
    ''::text AS "organisasjonsform.kode",
    ''::text AS "organisasjonsform.beskrivelse",
    ''::text AS "naeringskode1.kode",
    ''::text AS "naeringskode1.beskrivelse",
    ''::text AS "naeringskode2.kode",
    ''::text AS "naeringskode2.beskrivelse",
    ''::text AS "naeringskode3.kode",
    ''::text AS "naeringskode3.beskrivelse",
    ''::text AS "hjelpeenhetskode.kode",
    ''::text AS "hjelpeenhetskode.beskrivelse",
    ''::text AS "harRegistrertAntallAnsatte",
    ''::text AS "antallAnsatte",
    ''::text AS hjemmeside,
    ''::text AS "postadresse.adresse",
    ''::text AS "postadresse.poststed",
    ''::text AS "postadresse.postnummer",
    ''::text AS "postadresse.kommune",
    ''::text AS "postadresse.kommunenummer",
    ''::text AS "postadresse.land",
    ''::text AS "postadresse.landkode",
    ''::text AS "beliggenhetsadresse.adresse",
    ''::text AS "beliggenhetsadresse.poststed",
    ''::text AS "beliggenhetsadresse.postnummer",
    ''::text AS "beliggenhetsadresse.kommune",
    ''::text AS "beliggenhetsadresse.kommunenummer",
    ''::text AS "beliggenhetsadresse.land",
    ''::text AS "beliggenhetsadresse.landkode",
    ''::text AS "registreringsdatoIEnhetsregisteret",
    ''::text AS "frivilligMvaRegistrertBeskrivelser",
    ''::text AS "registrertIMvaregisteret",
    ''::text AS oppstartsdato,
    ''::text AS "datoEierskifte",
    ''::text AS "overordnetEnhet",
    ''::text AS nedleggelsesdato;
Triggers:
    upsert_establishment_brreg_view INSTEAD OF INSERT ON establishment_brreg_view FOR EACH ROW EXECUTE FUNCTION admin.upsert_establishment_brreg_view()
Options: security_invoker=on

```
