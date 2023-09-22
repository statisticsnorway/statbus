-- Run with
-- sqlcmd -h-1 -s"," -W -S YourServer -d YourDatabase -U YourUsername -P YourPassword -i ExtractData.sql -o OutputFile.sql
-- sqlcmd --headers -1 -s"" --trim-spaces --server localhost --database-name SBR_NOR --user-name sa --password 12qw!@QW --input-file ExtractMsSqlData.sql --output-file InsertPostgresData.sql

-- Tables with Seed data, require for Statbus to be operational.
--   LegalForms(Code, IsDeleted, Name, ParentId)
--   SectorCodes(Code, IsDeleted, Name, ParentId)
--   ReorgTypes(Code, IsDeleted, Name)
--   ForeignParticipations(Code, IsDeleted, Name)
--   DataSourceClassifications(Code, IsDeleted, Name)
--   UnitStatuses(Code, Name, IsDeleted)
--   UnitSizes(IsDeleted, Name, NameLanguage1, NameLanguage2, Code)
--   RegistrationReasons(Code, IsDeleted, Name)
--   PersonTypes(IsDeleted, Name)
--   DictionaryVersions(VersionId, VersionName)
--   ActivityCategories(Code, IsDeleted, Name, ParentId, Section, VersionId, DicParentId, ActivityCategoryLevel)
--   Regions(AdminstrativeCenter, Code, IsDeleted, Name, ParentId, FullPath, RegionLevel)
--   EnterpriseGroupTypes(IsDeleted, Name)
--   EnterpriseGroupRoles(Name, IsDeleted, Code)

-- Automatically created by dotnet startup code
--   Countries(Code, IsDeleted, IsoCode, Name)

SET NOCOUNT ON;

SELECT 'BEGIN;';

SELECT 'INSERT INTO "LegalForms" ("Id", "Code", "Name") VALUES (' +
    ISNULL(''''+ CAST([Id] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Code] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Name] AS NVARCHAR) + '''', 'NULL') + ');'
FROM [LegalForms]
ORDER BY [Id];

SELECT 'SELECT setval(pg_get_serial_sequence(''"LegalForms"'', ''Id''), COALESCE((SELECT MAX("Id")+1 FROM "LegalForms"), 1), false);'

SELECT 'INSERT INTO "SectorCodes" ("Id", "Code", "Name", "ParentId") VALUES (' +
    ISNULL(''''+ CAST([Id] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Code] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Name] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([ParentId] AS NVARCHAR) + '''', 'NULL') + ');'
FROM [SectorCodes]
ORDER BY [Id];
SELECT 'SELECT setval(pg_get_serial_sequence(''"SectorCodes"'', ''Id''), COALESCE((SELECT MAX("Id")+1 FROM "SectorCodes"), 1), false);'

-- Countries are automatically created by dotnet during startup.
-- SELECT 'INSERT INTO "Countries" ("Id", "Code", "IsoCode", "Name") VALUES (' +
--     ISNULL(''''+ CAST([Id] AS NVARCHAR) + '''', 'NULL') + ', ' +
--     ISNULL(''''+ CAST([Code] AS NVARCHAR) + '''', 'NULL') + ', ' +
--     ISNULL(''''+ CAST([IsoCode] AS NVARCHAR) + '''', 'NULL') + ', ' +
--     ISNULL(''''+ CAST([Name] AS NVARCHAR) + '''', 'NULL') + ');'
-- FROM [Countries];
-- SELECT 'SELECT setval(pg_get_serial_sequence(''"Countries"'', ''Id''), COALESCE((SELECT MAX("Id")+1 FROM "Countries"), 1), false);'

SELECT 'INSERT INTO "ReorgTypes" ("Id", "Code", "Name") VALUES (' +
    ISNULL(''''+ CAST([Id] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Code] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Name] AS NVARCHAR) + '''', 'NULL') + ');'
FROM [ReorgTypes];
SELECT 'SELECT setval(pg_get_serial_sequence(''"ReorgTypes"'', ''Id''), COALESCE((SELECT MAX("Id")+1 FROM "ReorgTypes"), 1), false);'

SELECT 'INSERT INTO "ForeignParticipations" ("Id", "Code", "Name") VALUES (' +
    ISNULL(''''+ CAST([Id] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Code] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Name] AS NVARCHAR) + '''', 'NULL') + ');'
FROM [ForeignParticipations];
SELECT 'SELECT setval(pg_get_serial_sequence(''"ForeignParticipations"'', ''Id''), COALESCE((SELECT MAX("Id")+1 FROM "ForeignParticipations"), 1), false);'

SELECT 'INSERT INTO "DataSourceClassifications" ("Id", "Code", "Name") VALUES (' +
    ISNULL(''''+ CAST([Id] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Code] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Name] AS NVARCHAR) + '''', 'NULL') + ');'
FROM [DataSourceClassifications];
SELECT 'SELECT setval(pg_get_serial_sequence(''"DataSourceClassifications"'', ''Id''), COALESCE((SELECT MAX("Id")+1 FROM "DataSourceClassifications"), 1), false);'

SELECT 'INSERT INTO "UnitStatuses" ("Id", "Code", "Name", "IsDeleted") VALUES (' +
    ISNULL(''''+ CAST([Id] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Code] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Name] AS NVARCHAR) + '''', 'NULL') + ');'
FROM [Statuses];
SELECT 'SELECT setval(pg_get_serial_sequence(''"UnitStatuses"'', ''Id''), COALESCE((SELECT MAX("Id")+1 FROM "UnitStatuses"), 1), false);'

SELECT 'INSERT INTO "UnitSizes" ("Id", "Name", "NameLanguage1", "NameLanguage2", "Code") VALUES (' +
    ISNULL(''''+ CAST([Id] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Name] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([NameLanguage1] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([NameLanguage2] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Code] AS NVARCHAR) + '''', 'NULL') + ');'
FROM [UnitsSize];
SELECT 'SELECT setval(pg_get_serial_sequence(''"UnitSizes"'', ''Id''), COALESCE((SELECT MAX("Id")+1 FROM "UnitSizes"), 1), false);'

SELECT 'INSERT INTO "RegistrationReasons" ("Id", "Code", "Name") VALUES (' +
    ISNULL(''''+ CAST([Id] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Code] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Name] AS NVARCHAR) + '''', 'NULL') + ');'
FROM [RegistrationReasons];
SELECT 'SELECT setval(pg_get_serial_sequence(''"RegistrationReasons"'', ''Id''), COALESCE((SELECT MAX("Id")+1 FROM "RegistrationReasons"), 1), false);'

SELECT 'INSERT INTO "PersonTypes" ("Id", "Name") VALUES (' +
    ISNULL(''''+ CAST([Id] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Name] AS NVARCHAR) + '''', 'NULL') + ');'
FROM [PersonTypes];
SELECT 'SELECT setval(pg_get_serial_sequence(''"PersonTypes"'', ''Id''), COALESCE((SELECT MAX("Id")+1 FROM "PersonTypes"), 1), false);'

SELECT 'INSERT INTO "DictionaryVersions" ("Id", "VersionId", "VersionName") VALUES (' +
    ISNULL(''''+ CAST([Id] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([VersionId] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([VersionName] AS NVARCHAR) + '''', 'NULL') + ');'
FROM [DictionaryVersions];

SELECT 'SELECT setval(pg_get_serial_sequence(''"DictionaryVersions"'', ''Id''), COALESCE((SELECT MAX("Id")+1 FROM "DictionaryVersions"), 1), false);'

SELECT 'INSERT INTO "ActivityCategories" ("Id", "Code", "Name", "ParentId", "Section", "VersionId", "DicParentId", "ActivityCategoryLevel") VALUES (' +
    ISNULL(''''+ CAST([Id] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Code] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Name] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([ParentId] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Section] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([VersionId] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([DicParentId] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([ActivityCategoryLevel] AS NVARCHAR) + '''', 'NULL') + ');'
FROM [ActivityCategories]
ORDER BY [Id];
SELECT 'SELECT setval(pg_get_serial_sequence(''"ActivityCategories"'', ''Id''), COALESCE((SELECT MAX("Id")+1 FROM "ActivityCategories"), 1), false);'

SELECT 'INSERT INTO "Regions" ("Id", "AdminstrativeCenter", "Code", "Name", "ParentId", "FullPath", "RegionLevel") VALUES (' +
    ISNULL(''''+ CAST([Id] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([AdminstrativeCenter] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Code] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Name] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([ParentId] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([FullPath] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([RegionLevel] AS NVARCHAR) + '''', 'NULL') + ');'
FROM [Regions];
SELECT 'SELECT setval(pg_get_serial_sequence(''"Regions"'', ''Id''), COALESCE((SELECT MAX("Id")+1 FROM "Regions"), 1), false);'

SELECT 'INSERT INTO "EnterpriseGroupTypes" ("Id", "Code", "Name") VALUES (' +
    ISNULL(''''+ CAST([Id] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Code] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Name] AS NVARCHAR) + '''', 'NULL') + ');'
FROM [EnterpriseGroupTypes];
SELECT 'SELECT setval(pg_get_serial_sequence(''"EnterpriseGroupTypes"'', ''Id''), COALESCE((SELECT MAX("Id")+1 FROM "EnterpriseGroupTypes"), 1), false);'

SELECT 'INSERT INTO "EnterpriseGroupRoles" ("Id", "Code", "Name") VALUES (' +
    ISNULL(''''+ CAST([Id] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Code] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Name] AS NVARCHAR) + '''', 'NULL') + ');'
FROM [EnterpriseGroupRoles];
SELECT 'SELECT setval(pg_get_serial_sequence(''"EnterpriseGroupRoles"'', ''Id''), COALESCE((SELECT MAX("Id")+1 FROM "EnterpriseGroupRoles"), 1), false);'

SELECT 'END;';