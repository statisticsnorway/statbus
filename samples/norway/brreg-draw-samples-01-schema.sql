CREATE SCHEMA tmp;

CREATE UNLOGGED TABLE tmp.enhet(
"organisasjonsnummer" TEXT NOT NULL PRIMARY KEY,
"navn" TEXT,
"organisasjonsform.kode" TEXT,
"organisasjonsform.beskrivelse" TEXT,
"naeringskode1.kode" TEXT,
"naeringskode1.beskrivelse" TEXT,
"naeringskode2.kode" TEXT,
"naeringskode2.beskrivelse" TEXT,
"naeringskode3.kode" TEXT,
"naeringskode3.beskrivelse" TEXT,
"hjelpeenhetskode.kode" TEXT,
"hjelpeenhetskode.beskrivelse" TEXT,
"harRegistrertAntallAnsatte" TEXT,
"antallAnsatte" TEXT,
"hjemmeside" TEXT,
"postadresse.adresse" TEXT,
"postadresse.poststed" TEXT,
"postadresse.postnummer" TEXT,
"postadresse.kommune" TEXT,
"postadresse.kommunenummer" TEXT,
"postadresse.land" TEXT,
"postadresse.landkode" TEXT,
"forretningsadresse.adresse" TEXT,
"forretningsadresse.poststed" TEXT,
"forretningsadresse.postnummer" TEXT,
"forretningsadresse.kommune" TEXT,
"forretningsadresse.kommunenummer" TEXT,
"forretningsadresse.land" TEXT,
"forretningsadresse.landkode" TEXT,
"institusjonellSektorkode.kode" TEXT,
"institusjonellSektorkode.beskrivelse" TEXT,
"sisteInnsendteAarsregnskap" TEXT,
"registreringsdatoenhetsregisteret" TEXT,
"stiftelsesdato" TEXT,
"registrertIMvaRegisteret" TEXT,
"frivilligMvaRegistrertBeskrivelser" TEXT,
"registrertIFrivillighetsregisteret" TEXT,
"registrertIForetaksregisteret" TEXT,
"registrertIStiftelsesregisteret" TEXT,
"konkurs" TEXT,
"konkursdato" TEXT,
"underAvvikling" TEXT,
"underAvviklingDato" TEXT,
"underTvangsavviklingEllerTvangsopplosning" TEXT,
"tvangsopplostPgaManglendeDagligLederDato" TEXT,
"tvangsopplostPgaManglendeRevisorDato" TEXT,
"tvangsopplostPgaManglendeRegnskapDato" TEXT,
"tvangsopplostPgaMangelfulltStyreDato" TEXT,
"tvangsavvikletPgaManglendeSlettingDato" TEXT,
"overordnetEnhet" TEXT,
"maalform" TEXT,
"vedtektsdato" TEXT,
"vedtektsfestetFormaal" TEXT,
"aktivitet" TEXT);

CREATE VIEW tmp.enhet_for_web_import AS
SELECT "organisasjonsnummer" AS tax_reg_ident
     , "navn" AS name
     , "forretningsadresse.kommunenummer" AS physical_region_code
     , "naeringskode1.kode" AS primary_activity_category_code
FROM tmp.enhet;


CREATE UNLOGGED TABLE tmp.underenhet(
"organisasjonsnummer" TEXT PRIMARY KEY,
"navn" TEXT,
"organisasjonsform.kode" TEXT,
"organisasjonsform.beskrivelse" TEXT,
"naeringskode1.kode" TEXT,
"naeringskode1.beskrivelse" TEXT,
"naeringskode2.kode" TEXT,
"naeringskode2.beskrivelse" TEXT,
"naeringskode3.kode" TEXT,
"naeringskode3.beskrivelse" TEXT,
"hjelpeenhetskode.kode" TEXT,
"hjelpeenhetskode.beskrivelse" TEXT,
"harRegistrertAntallAnsatte" TEXT,
"antallAnsatte" TEXT,
"hjemmeside" TEXT,
"postadresse.adresse" TEXT,
"postadresse.poststed" TEXT,
"postadresse.postnummer" TEXT,
"postadresse.kommune" TEXT,
"postadresse.kommunenummer" TEXT,
"postadresse.land" TEXT,
"postadresse.landkode" TEXT,
"beliggenhetsadresse.adresse" TEXT,
"beliggenhetsadresse.poststed" TEXT,
"beliggenhetsadresse.postnummer" TEXT,
"beliggenhetsadresse.kommune" TEXT,
"beliggenhetsadresse.kommunenummer" TEXT,
"beliggenhetsadresse.land" TEXT,
"beliggenhetsadresse.landkode" TEXT,
"registreringsdatoIEnhetsregisteret" TEXT,
"frivilligMvaRegistrertBeskrivelser" TEXT,
"registrertIMvaregisteret" TEXT,
"oppstartsdato" TEXT,
"datoEierskifte" TEXT,
"overordnetEnhet" TEXT,-- NOT NULL REFERENCES enhet("organisasjonsnummer"),
"nedleggelsesdato" TEXT);


CREATE VIEW tmp.underenhet_for_web_import AS
SELECT "organisasjonsnummer" AS tax_reg_ident
     , "overordnetEnhet" AS legal_unit_tax_reg_ident
     , "navn" AS name
     , "beliggenhetsadresse.kommunenummer" AS physical_region_code
     , "naeringskode1.kode" AS primary_activity_category_code
FROM tmp.underenhet;