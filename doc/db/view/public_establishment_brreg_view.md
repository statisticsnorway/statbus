```sql
                   View "public.establishment_brreg_view"
               Column               | Type | Collation | Nullable | Default 
------------------------------------+------+-----------+----------+---------
 organisasjonsnummer                | text |           |          | 
 navn                               | text |           |          | 
 organisasjonsform.kode             | text |           |          | 
 organisasjonsform.beskrivelse      | text |           |          | 
 naeringskode1.kode                 | text |           |          | 
 naeringskode1.beskrivelse          | text |           |          | 
 naeringskode2.kode                 | text |           |          | 
 naeringskode2.beskrivelse          | text |           |          | 
 naeringskode3.kode                 | text |           |          | 
 naeringskode3.beskrivelse          | text |           |          | 
 hjelpeenhetskode.kode              | text |           |          | 
 hjelpeenhetskode.beskrivelse       | text |           |          | 
 harRegistrertAntallAnsatte         | text |           |          | 
 antallAnsatte                      | text |           |          | 
 hjemmeside                         | text |           |          | 
 postadresse.adresse                | text |           |          | 
 postadresse.poststed               | text |           |          | 
 postadresse.postnummer             | text |           |          | 
 postadresse.kommune                | text |           |          | 
 postadresse.kommunenummer          | text |           |          | 
 postadresse.land                   | text |           |          | 
 postadresse.landkode               | text |           |          | 
 beliggenhetsadresse.adresse        | text |           |          | 
 beliggenhetsadresse.poststed       | text |           |          | 
 beliggenhetsadresse.postnummer     | text |           |          | 
 beliggenhetsadresse.kommune        | text |           |          | 
 beliggenhetsadresse.kommunenummer  | text |           |          | 
 beliggenhetsadresse.land           | text |           |          | 
 beliggenhetsadresse.landkode       | text |           |          | 
 registreringsdatoIEnhetsregisteret | text |           |          | 
 frivilligMvaRegistrertBeskrivelser | text |           |          | 
 registrertIMvaregisteret           | text |           |          | 
 oppstartsdato                      | text |           |          | 
 datoEierskifte                     | text |           |          | 
 overordnetEnhet                    | text |           |          | 
 nedleggelsesdato                   | text |           |          | 
Triggers:
    upsert_establishment_brreg_view INSTEAD OF INSERT ON establishment_brreg_view FOR EACH ROW EXECUTE FUNCTION admin.upsert_establishment_brreg_view()

```
