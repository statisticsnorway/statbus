ALTER TABLE [dbo].[Persons]
ADD [K_PRED] FLOAT NULL
GO

--ALTER TABLE [dbo].[Persons] DROP [K_PRED]

INSERT INTO [dbo].[Persons] ( [Address], [BirthDate], [CountryId], [GivenName], [IdDate], [PersonalId], [PhoneNumber], [PhoneNumber1], [Role], [Sex], [Surname], [K_PRED] )
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
	[P_NOM] AS PersonalId,	
	[T_ON] AS PhoneNumber,	
	'' AS PhoneNumber1,
	2 AS Role,
	CAST([POL] AS SMALLINT) AS Sex,	
	'' AS Surname,
	CAST([K_PRED] AS FLOAT)
FROM [statcom].[dbo].[KATME] e
	LEFT JOIN [dbo].[Countries] c
		ON c.[IsoCode] = CAST(e.[P_GRD] AS NVARCHAR)


INSERT INTO [dbo].[PersonStatisticalUnits] ( [Unit_Id], [Person_Id], [PersonType] )
SELECT s.[RegId], p.[Id], 2
FROM [dbo].[StatisticalUnits] AS s
	INNER JOIN [dbo].[Persons] AS p
		ON s.[K_PRED] = p.[K_PRED]