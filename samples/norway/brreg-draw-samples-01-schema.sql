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
SELECT "organisasjonsnummer" AS tax_ident
     , "navn" AS name
     , "stiftelsesdato" AS birth_date
     -- There is no death date, the entry simply vanishes!
     --, "nedleggelsesdato" AS death_date
     , "forretningsadresse.adresse" AS physical_address_part1
     , "forretningsadresse.postnummer" AS physical_postal_code
     , "forretningsadresse.poststed"   AS physical_postal_place
     , "forretningsadresse.kommunenummer" AS physical_region_code
     , "forretningsadresse.landkode" AS physical_country_iso_2
     , "postadresse.adresse" AS postal_address_part1
     , "postadresse.poststed" AS postal_postal_code
     , "postadresse.postnummer" AS postal_postal_place
     , "postadresse.kommunenummer" AS postal_region_code
     , "postadresse.landkode" AS postal_country_iso_2
     , "naeringskode1.kode" AS primary_activity_category_code
     , "naeringskode2.kode" AS secondary_activity_category_code
     , "institusjonellSektorkode.kode" AS sector_code
     , "organisasjonsform.kode" AS legal_form_code
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
SELECT "organisasjonsnummer" AS tax_ident
     , "overordnetEnhet" AS legal_unit_tax_ident
     , "navn" AS name
     , "oppstartsdato" AS birth_date
     , "nedleggelsesdato" AS death_date
     , "beliggenhetsadresse.adresse" AS physical_address_part1
     , "beliggenhetsadresse.postnummer" AS physical_postal_code
     , "beliggenhetsadresse.poststed"   AS physical_postal_place
     , "beliggenhetsadresse.kommunenummer" AS physical_region_code
     , "beliggenhetsadresse.landkode" AS physical_country_iso_2
     , "postadresse.adresse" AS postal_address_part1
     , "postadresse.poststed" AS postal_postal_code
     , "postadresse.postnummer" AS postal_postal_place
     , "postadresse.kommunenummer" AS postal_region_code
     , "postadresse.landkode" AS postal_country_iso_2
     , "naeringskode1.kode" AS primary_activity_category_code
     , "naeringskode2.kode" AS secondary_activity_category_code
     , "antallAnsatte" AS employees
FROM tmp.underenhet;
