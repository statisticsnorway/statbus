-- Run with
-- sqlcmd --headers -1 -s"" --trim-spaces --variable-type-width 0 --server localhost --database-name SBR_NOR --user-name sa --password 12qw!@QW --input-file ExtractMsSqlData.sql --output-file InsertPostgresData.sql

-- Tables with Seed data, require for Statbus to be operational.
--   LegalForms(Code, IsDeleted, Name)
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
--   Countries(Code, IsDeleted, IsoCode, Name)

SET NOCOUNT ON;

SELECT 'BEGIN;';

SELECT 'INSERT INTO "LegalForms" ("Id", "Code", "Name") VALUES (' +
    ISNULL(''''+ CAST([Id] AS NVARCHAR(MAX)) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Code] AS NVARCHAR(MAX)) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Name] AS NVARCHAR(MAX)) + '''', 'NULL') + ');'
FROM [LegalForms]
ORDER BY [Id];

SELECT 'SELECT setval(pg_get_serial_sequence(''"LegalForms"'', ''Id''), COALESCE((SELECT MAX("Id")+1 FROM "LegalForms"), 1), false);';

SELECT 'INSERT INTO "SectorCodes" ("Id", "Code", "Name", "ParentId") VALUES (' +
    ISNULL(''''+ CAST([Id] AS NVARCHAR(MAX)) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Code] AS NVARCHAR(MAX)) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Name] AS NVARCHAR(MAX)) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([ParentId] AS NVARCHAR(MAX)) + '''', 'NULL') + ');'
FROM [SectorCodes]
ORDER BY [Id];
SELECT 'SELECT setval(pg_get_serial_sequence(''"SectorCodes"'', ''Id''), COALESCE((SELECT MAX("Id")+1 FROM "SectorCodes"), 1), false);';

SELECT 'INSERT INTO "Countries" ("Id", "Code", "IsoCode", "Name") VALUES (' +
    ISNULL(''''+ CAST([Id] AS NVARCHAR(MAX)) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Code] AS NVARCHAR(MAX)) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([IsoCode] AS NVARCHAR(MAX)) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Name] AS NVARCHAR(MAX)) + '''', 'NULL') + ');'
FROM [Countries];
SELECT 'SELECT setval(pg_get_serial_sequence(''"Countries"'', ''Id''), COALESCE((SELECT MAX("Id")+1 FROM "Countries"), 1), false);';

SELECT 'INSERT INTO "ReorgTypes" ("Id", "Code", "Name") VALUES (' +
    ISNULL(''''+ CAST([Id] AS NVARCHAR(MAX)) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Code] AS NVARCHAR(MAX)) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Name] AS NVARCHAR(MAX)) + '''', 'NULL') + ');'
FROM [ReorgTypes];
SELECT 'SELECT setval(pg_get_serial_sequence(''"ReorgTypes"'', ''Id''), COALESCE((SELECT MAX("Id")+1 FROM "ReorgTypes"), 1), false);';

SELECT 'INSERT INTO "ForeignParticipations" ("Id", "Code", "Name") VALUES (' +
    ISNULL(''''+ CAST([Id] AS NVARCHAR(MAX)) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Code] AS NVARCHAR(MAX)) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Name] AS NVARCHAR(MAX)) + '''', 'NULL') + ');'
FROM [ForeignParticipations];
SELECT 'SELECT setval(pg_get_serial_sequence(''"ForeignParticipations"'', ''Id''), COALESCE((SELECT MAX("Id")+1 FROM "ForeignParticipations"), 1), false);';

SELECT 'INSERT INTO "DataSourceClassifications" ("Id", "Code", "Name") VALUES (' +
    ISNULL(''''+ CAST([Id] AS NVARCHAR(MAX)) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Code] AS NVARCHAR(MAX)) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Name] AS NVARCHAR(MAX)) + '''', 'NULL') + ');'
FROM [DataSourceClassifications];
SELECT 'SELECT setval(pg_get_serial_sequence(''"DataSourceClassifications"'', ''Id''), COALESCE((SELECT MAX("Id")+1 FROM "DataSourceClassifications"), 1), false);';

SELECT 'INSERT INTO "UnitStatuses" ("Id", "Code", "Name") VALUES (' +
    ISNULL(''''+ CAST([Id] AS NVARCHAR(MAX)) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Code] AS NVARCHAR(MAX)) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Name] AS NVARCHAR(MAX)) + '''', 'NULL') + ');'
FROM [Statuses];
SELECT 'SELECT setval(pg_get_serial_sequence(''"UnitStatuses"'', ''Id''), COALESCE((SELECT MAX("Id")+1 FROM "UnitStatuses"), 1), false);';

SELECT 'INSERT INTO "UnitSizes" ("Id", "Name", "NameLanguage1", "NameLanguage2", "Code") VALUES (' +
    ISNULL(''''+ CAST([Id] AS NVARCHAR(MAX)) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Name] AS NVARCHAR(MAX)) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([NameLanguage1] AS NVARCHAR(MAX)) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([NameLanguage2] AS NVARCHAR(MAX)) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Code] AS NVARCHAR(MAX)) + '''', 'NULL') + ');'
FROM [UnitsSize];
SELECT 'SELECT setval(pg_get_serial_sequence(''"UnitSizes"'', ''Id''), COALESCE((SELECT MAX("Id")+1 FROM "UnitSizes"), 1), false);';

SELECT 'INSERT INTO "RegistrationReasons" ("Id", "Code", "Name") VALUES (' +
    ISNULL(''''+ CAST([Id] AS NVARCHAR(MAX)) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Code] AS NVARCHAR(MAX)) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Name] AS NVARCHAR(MAX)) + '''', 'NULL') + ');'
FROM [RegistrationReasons];
SELECT 'SELECT setval(pg_get_serial_sequence(''"RegistrationReasons"'', ''Id''), COALESCE((SELECT MAX("Id")+1 FROM "RegistrationReasons"), 1), false);';

SELECT 'INSERT INTO "PersonTypes" ("Id", "Name") VALUES (' +
    ISNULL(''''+ CAST([Id] AS NVARCHAR(MAX)) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Name] AS NVARCHAR(MAX)) + '''', 'NULL') + ');'
FROM [PersonTypes];
SELECT 'SELECT setval(pg_get_serial_sequence(''"PersonTypes"'', ''Id''), COALESCE((SELECT MAX("Id")+1 FROM "PersonTypes"), 1), false);';

SELECT 'INSERT INTO "DictionaryVersions" ("Id", "VersionId", "VersionName") VALUES (' +
    ISNULL(''''+ CAST([Id] AS NVARCHAR(MAX)) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([VersionId] AS NVARCHAR(MAX)) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([VersionName] AS NVARCHAR(MAX)) + '''', 'NULL') + ');'
FROM [DictionaryVersions];

SELECT 'SELECT setval(pg_get_serial_sequence(''"DictionaryVersions"'', ''Id''), COALESCE((SELECT MAX("Id")+1 FROM "DictionaryVersions"), 1), false);';

WITH RecursiveCTE AS (
    -- Base case: records with no parent
    SELECT [Id], [ParentId], 0 AS Depth
    FROM [ActivityCategories]
    WHERE [ParentId] IS NULL OR [ParentId] = 0

    UNION ALL

    -- Recursive case: join with children
    SELECT ac.[Id], ac.[ParentId], r.Depth + 1
    FROM [ActivityCategories] ac
    JOIN RecursiveCTE r ON ac.[ParentId] = r.[Id]
)
SELECT 'INSERT INTO "ActivityCategories" ("Id", "Code", "Name", "ParentId", "Section", "VersionId", "DicParentId", "ActivityCategoryLevel") VALUES (' +
    ISNULL(''''+ CAST(ac.[Id] AS NVARCHAR(MAX)) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST(ac.[Code] AS NVARCHAR(MAX)) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST(ac.[Name] AS NVARCHAR(MAX)) + '''', 'NULL') + ', ' +
    CASE
      WHEN ac.[ParentId] = 0 THEN 'NULL'
      ELSE ISNULL(''''+ CAST(ac.[ParentId] AS NVARCHAR(MAX)) + '''', 'NULL')
    END + ', ' +
    ISNULL(''''+ CAST(ac.[Section] AS NVARCHAR(MAX)) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST(ac.[VersionId] AS NVARCHAR(MAX)) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST(ac.[DicParentId] AS NVARCHAR(MAX)) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST(ac.[ActivityCategoryLevel] AS NVARCHAR(MAX)) + '''', 'NULL') + ');'
FROM [ActivityCategories] ac
JOIN RecursiveCTE r ON ac.[Id] = r.[Id]
ORDER BY r.Depth ASC, ac.[ParentId] ASC;
SELECT 'SELECT setval(pg_get_serial_sequence(''"ActivityCategories"'', ''Id''), COALESCE((SELECT MAX("Id")+1 FROM "ActivityCategories"), 1), false);';

SELECT 'INSERT INTO "Regions" ("Id", "AdminstrativeCenter", "Code", "Name", "ParentId", "FullPath", "RegionLevel") VALUES (' +
    ISNULL(''''+ CAST([Id] AS NVARCHAR(MAX)) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([AdminstrativeCenter] AS NVARCHAR(MAX)) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Code] AS NVARCHAR(MAX)) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Name] AS NVARCHAR(MAX)) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([ParentId] AS NVARCHAR(MAX)) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([FullPath] AS NVARCHAR(MAX)) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([RegionLevel] AS NVARCHAR(MAX)) + '''', 'NULL') + ');'
FROM [Regions];
SELECT 'SELECT setval(pg_get_serial_sequence(''"Regions"'', ''Id''), COALESCE((SELECT MAX("Id")+1 FROM "Regions"), 1), false);';

-- -- These are provided by dotnet during startup.
-- SELECT 'INSERT INTO "EnterpriseGroupTypes" ("Id", "Code", "Name") VALUES (' +
--     ISNULL(''''+ CAST([Id] AS NVARCHAR(MAX)) + '''', 'NULL') + ', ' +
--     ISNULL(''''+ CAST([Code] AS NVARCHAR(MAX)) + '''', 'NULL') + ', ' +
--     ISNULL(''''+ CAST([Name] AS NVARCHAR(MAX)) + '''', 'NULL') + ');'
-- FROM [EnterpriseGroupTypes];
-- SELECT 'SELECT setval(pg_get_serial_sequence(''"EnterpriseGroupTypes"'', ''Id''), COALESCE((SELECT MAX("Id")+1 FROM "EnterpriseGroupTypes"), 1), false);';
--
-- SELECT 'INSERT INTO "EnterpriseGroupRoles" ("Id", "Code", "Name") VALUES (' +
--     ISNULL(''''+ CAST([Id] AS NVARCHAR(MAX)) + '''', 'NULL') + ', ' +
--     ISNULL(''''+ CAST([Code] AS NVARCHAR(MAX)) + '''', 'NULL') + ', ' +
--     ISNULL(''''+ CAST([Name] AS NVARCHAR(MAX)) + '''', 'NULL') + ');'
-- FROM [EnterpriseGroupRoles];
-- SELECT 'SELECT setval(pg_get_serial_sequence(''"EnterpriseGroupRoles"'', ''Id''), COALESCE((SELECT MAX("Id")+1 FROM "EnterpriseGroupRoles"), 1), false);';

SELECT 'END;';