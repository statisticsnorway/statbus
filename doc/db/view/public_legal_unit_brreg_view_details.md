```sql
                                    View "public.legal_unit_brreg_view"
                  Column                   | Type | Collation | Nullable | Default | Storage  | Description 
-------------------------------------------+------+-----------+----------+---------+----------+-------------
 organisasjonsnummer                       | text |           |          |         | extended | 
 navn                                      | text |           |          |         | extended | 
 organisasjonsform.kode                    | text |           |          |         | extended | 
 organisasjonsform.beskrivelse             | text |           |          |         | extended | 
 naeringskode1.kode                        | text |           |          |         | extended | 
 naeringskode1.beskrivelse                 | text |           |          |         | extended | 
 naeringskode2.kode                        | text |           |          |         | extended | 
 naeringskode2.beskrivelse                 | text |           |          |         | extended | 
 naeringskode3.kode                        | text |           |          |         | extended | 
 naeringskode3.beskrivelse                 | text |           |          |         | extended | 
 hjelpeenhetskode.kode                     | text |           |          |         | extended | 
 hjelpeenhetskode.beskrivelse              | text |           |          |         | extended | 
 harRegistrertAntallAnsatte                | text |           |          |         | extended | 
 antallAnsatte                             | text |           |          |         | extended | 
 hjemmeside                                | text |           |          |         | extended | 
 postadresse.adresse                       | text |           |          |         | extended | 
 postadresse.poststed                      | text |           |          |         | extended | 
 postadresse.postnummer                    | text |           |          |         | extended | 
 postadresse.kommune                       | text |           |          |         | extended | 
 postadresse.kommunenummer                 | text |           |          |         | extended | 
 postadresse.land                          | text |           |          |         | extended | 
 postadresse.landkode                      | text |           |          |         | extended | 
 forretningsadresse.adresse                | text |           |          |         | extended | 
 forretningsadresse.poststed               | text |           |          |         | extended | 
 forretningsadresse.postnummer             | text |           |          |         | extended | 
 forretningsadresse.kommune                | text |           |          |         | extended | 
 forretningsadresse.kommunenummer          | text |           |          |         | extended | 
 forretningsadresse.land                   | text |           |          |         | extended | 
 forretningsadresse.landkode               | text |           |          |         | extended | 
 institusjonellSektorkode.kode             | text |           |          |         | extended | 
 institusjonellSektorkode.beskrivelse      | text |           |          |         | extended | 
 sisteInnsendteAarsregnskap                | text |           |          |         | extended | 
 registreringsdatoenhetsregisteret         | text |           |          |         | extended | 
 stiftelsesdato                            | text |           |          |         | extended | 
 registrertIMvaRegisteret                  | text |           |          |         | extended | 
 frivilligMvaRegistrertBeskrivelser        | text |           |          |         | extended | 
 registrertIFrivillighetsregisteret        | text |           |          |         | extended | 
 registrertIForetaksregisteret             | text |           |          |         | extended | 
 registrertIStiftelsesregisteret           | text |           |          |         | extended | 
 konkurs                                   | text |           |          |         | extended | 
 konkursdato                               | text |           |          |         | extended | 
 underAvvikling                            | text |           |          |         | extended | 
 underAvviklingDato                        | text |           |          |         | extended | 
 underTvangsavviklingEllerTvangsopplosning | text |           |          |         | extended | 
 tvangsopplostPgaManglendeDagligLederDato  | text |           |          |         | extended | 
 tvangsopplostPgaManglendeRevisorDato      | text |           |          |         | extended | 
 tvangsopplostPgaManglendeRegnskapDato     | text |           |          |         | extended | 
 tvangsopplostPgaMangelfulltStyreDato      | text |           |          |         | extended | 
 tvangsavvikletPgaManglendeSlettingDato    | text |           |          |         | extended | 
 overordnetEnhet                           | text |           |          |         | extended | 
 maalform                                  | text |           |          |         | extended | 
 vedtektsdato                              | text |           |          |         | extended | 
 vedtektsfestetFormaal                     | text |           |          |         | extended | 
 aktivitet                                 | text |           |          |         | extended | 
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
    ''::text AS "forretningsadresse.adresse",
    ''::text AS "forretningsadresse.poststed",
    ''::text AS "forretningsadresse.postnummer",
    ''::text AS "forretningsadresse.kommune",
    ''::text AS "forretningsadresse.kommunenummer",
    ''::text AS "forretningsadresse.land",
    ''::text AS "forretningsadresse.landkode",
    ''::text AS "institusjonellSektorkode.kode",
    ''::text AS "institusjonellSektorkode.beskrivelse",
    ''::text AS "sisteInnsendteAarsregnskap",
    ''::text AS registreringsdatoenhetsregisteret,
    ''::text AS stiftelsesdato,
    ''::text AS "registrertIMvaRegisteret",
    ''::text AS "frivilligMvaRegistrertBeskrivelser",
    ''::text AS "registrertIFrivillighetsregisteret",
    ''::text AS "registrertIForetaksregisteret",
    ''::text AS "registrertIStiftelsesregisteret",
    ''::text AS konkurs,
    ''::text AS konkursdato,
    ''::text AS "underAvvikling",
    ''::text AS "underAvviklingDato",
    ''::text AS "underTvangsavviklingEllerTvangsopplosning",
    ''::text AS "tvangsopplostPgaManglendeDagligLederDato",
    ''::text AS "tvangsopplostPgaManglendeRevisorDato",
    ''::text AS "tvangsopplostPgaManglendeRegnskapDato",
    ''::text AS "tvangsopplostPgaMangelfulltStyreDato",
    ''::text AS "tvangsavvikletPgaManglendeSlettingDato",
    ''::text AS "overordnetEnhet",
    ''::text AS maalform,
    ''::text AS vedtektsdato,
    ''::text AS "vedtektsfestetFormaal",
    ''::text AS aktivitet;
Triggers:
    legal_unit_brreg_view_upsert INSTEAD OF INSERT ON legal_unit_brreg_view FOR EACH ROW EXECUTE FUNCTION admin.legal_unit_brreg_view_upsert()
Options: security_invoker=on

```
