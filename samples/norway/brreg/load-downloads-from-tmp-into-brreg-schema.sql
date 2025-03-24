DROP SCHEMA IF EXISTS brreg CASCADE;

BEGIN;
CREATE SCHEMA brreg;

CREATE TABLE IF NOT EXISTS brreg.enhet
     ( "organisasjonsnummer" TEXT NOT NULL PRIMARY KEY
     , "navn" TEXT
     , "organisasjonsform.kode" TEXT
     , "organisasjonsform.beskrivelse" TEXT
     , "naeringskode1.kode" TEXT
     , "naeringskode1.beskrivelse" TEXT
     , "naeringskode2.kode" TEXT
     , "naeringskode2.beskrivelse" TEXT
     , "naeringskode3.kode" TEXT
     , "naeringskode3.beskrivelse" TEXT
     , "hjelpeenhetskode.kode" TEXT
     , "hjelpeenhetskode.beskrivelse" TEXT
     , "harRegistrertAntallAnsatte" TEXT
     , "antallAnsatte" TEXT
     , "registreringsdatoAntallAnsatteEnhetsregisteret" TEXT
     , "registreringsdatoantallansatteNAVAaregisteret" TEXT
     , "hjemmeside" TEXT
     , "epostadresse" TEXT
     , "telefon" TEXT
     , "mobil" TEXT
     , "postadresse.adresse" TEXT
     , "postadresse.poststed" TEXT
     , "postadresse.postnummer" TEXT
     , "postadresse.kommune" TEXT
     , "postadresse.kommunenummer" TEXT
     , "postadresse.land" TEXT
     , "postadresse.landkode" TEXT
     , "forretningsadresse.adresse" TEXT
     , "forretningsadresse.poststed" TEXT
     , "forretningsadresse.postnummer" TEXT
     , "forretningsadresse.kommune" TEXT
     , "forretningsadresse.kommunenummer" TEXT
     , "forretningsadresse.land" TEXT
     , "forretningsadresse.landkode" TEXT
     , "institusjonellSektorkode.kode" TEXT
     , "institusjonellSektorkode.beskrivelse" TEXT
     , "sisteInnsendteAarsregnskap" TEXT
     , "registreringsdatoenhetsregisteret" TEXT
     , "stiftelsesdato" TEXT
     , "registrertIMvaRegisteret" TEXT
     , "registreringsdatoMerverdiavgiftsregisteret" TEXT
     , "registreringsdatoMerverdiavgiftsregisteretEnhetsregisteret" TEXT
     , "frivilligMvaRegistrertBeskrivelser" TEXT
     , "registreringsdatoFrivilligMerverdiavgiftsregisteret" TEXT
     , "registrertIFrivillighetsregisteret" TEXT
     , "registreringsdatoFrivillighetsregisteret" TEXT
     , "registrertIForetaksregisteret" TEXT
     , "registreringsdatoForetaksregisteret" TEXT
     , "registrertIStiftelsesregisteret" TEXT
     , "registrertIPartiregisteret" TEXT
     , "registreringsdatoPartiregisteret" TEXT
     , "konkurs" TEXT
     , "konkursdato" TEXT
     , "underAvvikling" TEXT
     , "underAvviklingDato" TEXT
     , "underTvangsavviklingEllerTvangsopplosning" TEXT
     , "tvangsopplostPgaManglendeDagligLederDato" TEXT
     , "tvangsopplostPgaManglendeRevisorDato" TEXT
     , "tvangsopplostPgaManglendeRegnskapDato" TEXT
     , "tvangsopplostPgaMangelfulltStyreDato" TEXT
     , "tvangsavvikletPgaManglendeSlettingDato" TEXT
     , "overordnetEnhet" TEXT
     , "maalform" TEXT
     , "vedtektsdato" TEXT
     , "vedtektsfestetFormaal" TEXT
     , "aktivitet" TEXT
     );


CREATE TABLE IF NOT EXISTS brreg.underenhet
     ( "organisasjonsnummer" TEXT PRIMARY KEY
     , "navn" TEXT
     , "organisasjonsform.kode" TEXT
     , "organisasjonsform.beskrivelse" TEXT
     , "naeringskode1.kode" TEXT
     , "naeringskode1.beskrivelse" TEXT
     , "naeringskode2.kode" TEXT
     , "naeringskode2.beskrivelse" TEXT
     , "naeringskode3.kode" TEXT
     , "naeringskode3.beskrivelse" TEXT
     , "hjelpeenhetskode.kode" TEXT
     , "hjelpeenhetskode.beskrivelse" TEXT
     , "harRegistrertAntallAnsatte" TEXT
     , "antallAnsatte" TEXT
     , "registreringsdatoAntallAnsatteEnhetsregisteret" TEXT
     , "registreringsdatoantallansatteNAVAaregisteret" TEXT
     , "hjemmeside" TEXT
     , "epostadresse" TEXT
     , "telefon" TEXT
     , "mobil" TEXT
     , "postadresse.adresse" TEXT
     , "postadresse.poststed" TEXT
     , "postadresse.postnummer" TEXT
     , "postadresse.kommune" TEXT
     , "postadresse.kommunenummer" TEXT
     , "postadresse.land" TEXT
     , "postadresse.landkode" TEXT
     , "beliggenhetsadresse.adresse" TEXT
     , "beliggenhetsadresse.poststed" TEXT
     , "beliggenhetsadresse.postnummer" TEXT
     , "beliggenhetsadresse.kommune" TEXT
     , "beliggenhetsadresse.kommunenummer" TEXT
     , "beliggenhetsadresse.land" TEXT
     , "beliggenhetsadresse.landkode" TEXT
     , "registreringsdatoIEnhetsregisteret" TEXT
     , "frivilligMvaRegistrertBeskrivelser" TEXT
     , "registreringsdatoFrivilligMerverdiavgiftsregisteret" TEXT
     , "registrertIMvaregisteret" TEXT
     , "registreringsdatoMerverdiavgiftsregisteret" TEXT
     , "registreringsdatoMerverdiavgiftsregisteretEnhetsregisteret" TEXT
     , "oppstartsdato" TEXT
     , "datoEierskifte" TEXT
     , "overordnetEnhet" TEXT
     , "nedleggelsesdato" TEXT
     );

\echo Copy tmp/enheter.csv into brreg.enhet
\copy brreg.enhet FROM 'tmp/enheter.csv' WITH (HEADER MATCH, FORMAT csv, DELIMITER ',', QUOTE '"');
\echo Copy tmp/underenheter.csv into brreg.underenhet
\copy brreg.underenhet FROM 'tmp/underenheter.csv' WITH (HEADER MATCH, FORMAT csv, DELIMITER ',', QUOTE '"');

CREATE INDEX idx_underenhet_overordnetEnhet ON brreg.underenhet("overordnetEnhet");

END;
