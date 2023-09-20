-- Run with
-- sqlcmd -h-1 -s"," -W -S YourServer -d YourDatabase -U YourUsername -P YourPassword -i ExtractData.sql -o OutputFile.sql
-- sqlcmd -h-1 -s"," -W -S localhost -d SBR_NOR -U sa -P 12qw!@QW -i ExtractMsSqlData.sql -o InsertPostgresData.sql

-- Tables with Seed data, require for Statbus to be operational.
--   LegalForms(Code, IsDeleted, Name, ParentId)
--   SectorCodes(Code, IsDeleted, Name, ParentId)
--   Countries(Code, IsDeleted, IsoCode, Name)
--   ReorgTypes(Code, IsDeleted, Name)
--   ForeignParticipations(Code, IsDeleted, Name)
--   DataSourceClassifications(Code, IsDeleted, Name)
--   Statuses(Code, Name, IsDeleted)
--   UnitsSize(IsDeleted, Name, NameLanguage1, NameLanguage2, Code)
--   RegistrationReasons(Code, IsDeleted, Name)
--   PersonTypes(IsDeleted, Name)
--   DictionaryVersions(VersionId, VersionName)
--   ActivityCategories(Code, IsDeleted, Name, ParentId, Section, VersionId, DicParentId, ActivityCategoryLevel)
--   Regions(AdminstrativeCenter, Code, IsDeleted, Name, ParentId, FullPath, RegionLevel)
--   EnterpriseGroupTypes(IsDeleted, Name)
--   EnterpriseGroupRoles(Name, IsDeleted, Code)


SET NOCOUNT ON;

SELECT 'INSERT INTO "LegalForms" ("Code", "IsDeleted", "Name", "ParentId") VALUES (' +
    ISNULL(''''+ CAST([Code] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([IsDeleted] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Name] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([ParentId] AS NVARCHAR) + '''', 'NULL') + '); ' + CHAR(13)
FROM [LegalForms]
ORDER BY [Id];


SELECT 'INSERT INTO "SectorCodes" ("Code", "IsDeleted", "Name", "ParentId") VALUES (' +
    ISNULL(''''+ CAST([Code] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([IsDeleted] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Name] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([ParentId] AS NVARCHAR) + '''', 'NULL') + '); ' + CHAR(13)
FROM [SectorCodes]
ORDER BY [Id];

SELECT 'INSERT INTO "Countries" ("Code", "IsDeleted", "IsoCode", "Name") VALUES (' +
    ISNULL(''''+ CAST([Code] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([IsDeleted] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([IsoCode] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Name] AS NVARCHAR) + '''', 'NULL') + '); ' + CHAR(13)
FROM [Countries];

SELECT 'INSERT INTO "ReorgTypes" ("Code", "IsDeleted", "Name") VALUES (' +
    ISNULL(''''+ CAST([Code] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([IsDeleted] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Name] AS NVARCHAR) + '''', 'NULL') + '); ' + CHAR(13)
FROM [ReorgTypes];


SELECT 'INSERT INTO "ForeignParticipations" ("Code", "IsDeleted", "Name") VALUES (' +
    ISNULL(''''+ CAST([Code] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([IsDeleted] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Name] AS NVARCHAR) + '''', 'NULL') + '); ' + CHAR(13)
FROM [ForeignParticipations];


SELECT 'INSERT INTO "DataSourceClassifications" ("Code", "IsDeleted", "Name") VALUES (' +
    ISNULL(''''+ CAST([Code] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([IsDeleted] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Name] AS NVARCHAR) + '''', 'NULL') + '); ' + CHAR(13)
FROM [DataSourceClassifications];

SELECT 'INSERT INTO "Statuses" ("Code", "Name", "IsDeleted") VALUES (' +
    ISNULL(''''+ CAST([Code] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Name] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([IsDeleted] AS NVARCHAR) + '''', 'NULL') + '); ' + CHAR(13)
FROM [Statuses];


SELECT 'INSERT INTO "UnitsSize" ("IsDeleted", "Name", "NameLanguage1", "NameLanguage2", "Code") VALUES (' +
    ISNULL(''''+ CAST([IsDeleted] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Name] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([NameLanguage1] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([NameLanguage2] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Code] AS NVARCHAR) + '''', 'NULL') + '); ' + CHAR(13)
FROM [UnitsSize];

SELECT 'INSERT INTO "RegistrationReasons" ("Code", "IsDeleted", "Name") VALUES (' +
    ISNULL(''''+ CAST([Code] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([IsDeleted] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Name] AS NVARCHAR) + '''', 'NULL') + '); ' + CHAR(13)
FROM [RegistrationReasons];

SELECT 'INSERT INTO "PersonTypes" ("IsDeleted", "Name") VALUES (' +
    ISNULL(''''+ CAST([IsDeleted] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Name] AS NVARCHAR) + '''', 'NULL') + '); ' + CHAR(13)
FROM [PersonTypes];

SELECT 'INSERT INTO "DictionaryVersions" ("VersionId", "VersionName") VALUES (' +
    ISNULL(''''+ CAST([VersionId] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([VersionName] AS NVARCHAR) + '''', 'NULL') + '); ' + CHAR(13)
FROM [DictionaryVersions];


SELECT 'INSERT INTO "ActivityCategories" ("Code", "IsDeleted", "Name", "ParentId", "Section", "VersionId", "DicParentId", "ActivityCategoryLevel") VALUES (' +
    ISNULL(''''+ CAST([Code] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([IsDeleted] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Name] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([ParentId] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Section] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([VersionId] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([DicParentId] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([ActivityCategoryLevel] AS NVARCHAR) + '''', 'NULL') + '); ' + CHAR(13)
FROM [ActivityCategories]
ORDER BY [Id];

SELECT 'INSERT INTO "Regions" ("AdminstrativeCenter", "Code", "IsDeleted", "Name", "ParentId", "FullPath", "RegionLevel") VALUES (' +
    ISNULL(''''+ CAST([AdminstrativeCenter] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Code] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([IsDeleted] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Name] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([ParentId] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([FullPath] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([RegionLevel] AS NVARCHAR) + '''', 'NULL') + '); ' + CHAR(13)
FROM [Regions];

SELECT 'INSERT INTO "EnterpriseGroupTypes" ("IsDeleted", "Name") VALUES (' +
    ISNULL(''''+ CAST([IsDeleted] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Name] AS NVARCHAR) + '''', 'NULL') + '); ' + CHAR(13)
FROM [EnterpriseGroupTypes];

SELECT 'INSERT INTO "EnterpriseGroupRoles" ("Name", "IsDeleted", "Code") VALUES (' +
    ISNULL(''''+ CAST([Name] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([IsDeleted] AS NVARCHAR) + '''', 'NULL') + ', ' +
    ISNULL(''''+ CAST([Code] AS NVARCHAR) + '''', 'NULL') + '); ' + CHAR(13)
FROM [EnterpriseGroupRoles];

