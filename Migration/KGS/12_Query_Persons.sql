DELETE FROM [Persons]
GO
DBCC CHECKIDENT ('dbo.Persons',RESEED, 1)
GO

ALTER TABLE [dbo].[Persons]
ADD [K_PRED] FLOAT NULL
GO

--ALTER TABLE [dbo].[Persons] DROP [K_PRED]

INSERT INTO [dbo].[Persons]
	([Address]
	,[BirthDate]
	,[CountryId]
	,[GivenName]
	,[IdDate]
	,[MiddleName]
	,[PersonalId]
	,[PhoneNumber]
	,[PhoneNumber1]
	,[Sex]
	,[Surname]
	,[K_PRED])
SELECT 
	CASE
		WHEN [P_ADR] <> '' AND [P_ADR] <> '0' THEN [P_ADR]
		WHEN [P_ADR1] <> '' AND [P_ADR1] <> '0' THEN [P_ADR1]
	END AS Address,
	[P_RRD] AS BirthDate,
	CASE
		WHEN c.[Code] IS NULL THEN (SELECT [Id] FROM [dbo].[Countries] WHERE [Code]='KGZ')
		ELSE c.[Id]
	END as CountryId,
	CASE
		WHEN [P_FIO] <> '' AND [P_FIO] <> '0' THEN [P_FIO]
		WHEN [FIO] <> '' AND [FIO] <> '0' THEN [FIO]
	END AS GivenName,
	GETDATE() AS IdDate,
	'' as MiddleName,
	[P_NOM] AS PersonalId,	
	[T_ON] AS PhoneNumber,	
	'' AS PhoneNumber1,
	CAST([POL] AS SMALLINT) AS Sex,	
	'' AS Surname,
	CAST([K_PRED] AS FLOAT)
FROM [statcom].[dbo].[KATME] e
	LEFT JOIN [dbo].[Countries] c
		ON c.[IsoCode] = CAST(e.[P_GRD] AS NVARCHAR)
GO

-- Add Person Types
DELETE FROM [dbo].[PersonTypes]
GO
DBCC CHECKIDENT ('dbo.PersonTypes',RESEED, 1)
GO

INSERT INTO [dbo].[PersonTypes]
  ([IsDeleted]
  ,[Name])
SELECT 0, 'Owner'
UNION ALL
SELECT 0,'Manager'
UNION ALL 
SELECT 0,'Contact person'
 
GO

INSERT INTO [dbo].[PersonStatisticalUnits]
	([Unit_Id]
	,[Person_Id]
	,[GroupUnit_Id]
	,[PersonTypeId]
	,[StatUnit_Id])
SELECT
	s.[RegId],
	p.[Id],
	null as groupUnit_id,
	1 as PersonTypeId, --Make sure the matches the [PersonType] table value
	null as StatUnit_Id	--don't know why this is here right now
FROM [dbo].[StatisticalUnits] AS s
	INNER JOIN [dbo].[Persons] AS p
		ON s.[K_PRED] = p.[K_PRED]