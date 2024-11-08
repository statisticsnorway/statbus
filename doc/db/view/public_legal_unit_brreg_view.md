```sql
                        View "public.legal_unit_brreg_view"
                  Column                   | Type | Collation | Nullable | Default 
-------------------------------------------+------+-----------+----------+---------
 organisasjonsnummer                       | text |           |          | 
 navn                                      | text |           |          | 
 organisasjonsform.kode                    | text |           |          | 
 organisasjonsform.beskrivelse             | text |           |          | 
 naeringskode1.kode                        | text |           |          | 
 naeringskode1.beskrivelse                 | text |           |          | 
 naeringskode2.kode                        | text |           |          | 
 naeringskode2.beskrivelse                 | text |           |          | 
 naeringskode3.kode                        | text |           |          | 
 naeringskode3.beskrivelse                 | text |           |          | 
 hjelpeenhetskode.kode                     | text |           |          | 
 hjelpeenhetskode.beskrivelse              | text |           |          | 
 harRegistrertAntallAnsatte                | text |           |          | 
 antallAnsatte                             | text |           |          | 
 hjemmeside                                | text |           |          | 
 postadresse.adresse                       | text |           |          | 
 postadresse.poststed                      | text |           |          | 
 postadresse.postnummer                    | text |           |          | 
 postadresse.kommune                       | text |           |          | 
 postadresse.kommunenummer                 | text |           |          | 
 postadresse.land                          | text |           |          | 
 postadresse.landkode                      | text |           |          | 
 forretningsadresse.adresse                | text |           |          | 
 forretningsadresse.poststed               | text |           |          | 
 forretningsadresse.postnummer             | text |           |          | 
 forretningsadresse.kommune                | text |           |          | 
 forretningsadresse.kommunenummer          | text |           |          | 
 forretningsadresse.land                   | text |           |          | 
 forretningsadresse.landkode               | text |           |          | 
 institusjonellSektorkode.kode             | text |           |          | 
 institusjonellSektorkode.beskrivelse      | text |           |          | 
 sisteInnsendteAarsregnskap                | text |           |          | 
 registreringsdatoenhetsregisteret         | text |           |          | 
 stiftelsesdato                            | text |           |          | 
 registrertIMvaRegisteret                  | text |           |          | 
 frivilligMvaRegistrertBeskrivelser        | text |           |          | 
 registrertIFrivillighetsregisteret        | text |           |          | 
 registrertIForetaksregisteret             | text |           |          | 
 registrertIStiftelsesregisteret           | text |           |          | 
 konkurs                                   | text |           |          | 
 konkursdato                               | text |           |          | 
 underAvvikling                            | text |           |          | 
 underAvviklingDato                        | text |           |          | 
 underTvangsavviklingEllerTvangsopplosning | text |           |          | 
 tvangsopplostPgaManglendeDagligLederDato  | text |           |          | 
 tvangsopplostPgaManglendeRevisorDato      | text |           |          | 
 tvangsopplostPgaManglendeRegnskapDato     | text |           |          | 
 tvangsopplostPgaMangelfulltStyreDato      | text |           |          | 
 tvangsavvikletPgaManglendeSlettingDato    | text |           |          | 
 overordnetEnhet                           | text |           |          | 
 maalform                                  | text |           |          | 
 vedtektsdato                              | text |           |          | 
 vedtektsfestetFormaal                     | text |           |          | 
 aktivitet                                 | text |           |          | 
Triggers:
    legal_unit_brreg_view_upsert INSTEAD OF INSERT ON legal_unit_brreg_view FOR EACH ROW EXECUTE FUNCTION admin.legal_unit_brreg_view_upsert()

```
