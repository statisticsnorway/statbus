# Statbus Database Seeding

For Statbus to work, the following tables must be populated.

Tables with Seed data, requires for Statbus to be operational.
*  `LegalForms`
*  `SectorCodes`
*  `ReorgTypes`
*  `ForeignParticipations`
*  `DataSourceClassifications`
*  `UnitStatus`
*  `UnitSize`
*  `RegistrationReasons`
*  `PersonTypes Name)`
*  `DictionaryVersions`
*  `ActivityCategories`
*  `Regions`
*  `EnterpriseGroupTypes Name)`
*  `EnterpriseGroupRoles`

Maintained by dotnet startup code.
*  `Countries`

They are usually populated specifically for the country where Statbus is used.

For local development the file `InsertPostgresData.sql` contains all the required
data to start testing Statbus.
Note that these data were extracted from the previously supported MS Sql database
with the `ExtractMsSqlData.sql` script.

