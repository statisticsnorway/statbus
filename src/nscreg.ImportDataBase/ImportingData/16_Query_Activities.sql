DELETE FROM [dbo].[Activities]
GO
DBCC CHECKIDENT ('dbo.Activities',RESEED, 1)
GO

ALTER TABLE [dbo].[Activities]
ADD K_PRED FLOAT NULL
GO

DECLARE @guid NVARCHAR(450)
SELECT @guid = Id FROM [dbo].[AspNetUsers]

INSERT INTO [dbo].[Activities]
  ([ActivityCategoryId]
  ,[Activity_Type]
  ,[Activity_Year]
  ,[Employees]
  ,[Id_Date]
  ,[Turnover]
  ,[Updated_By]
  ,[Updated_Date]
  ,[K_PRED])
SELECT
	a.[Id] AS ActivityCategoryId,
	1 AS Activity_Type,
	CASE
		WHEN [DND] IS NULL THEN 2017
		ELSE LEFT(CONVERT(NVARCHAR, [DND], 21), 4)
    END AS Activity_Year,
	S_SPR1 AS Employees,
	GETDATE() AS Id_Date,
	0 AS Turnover,
	@guid AS Updated_By,
	GETDATE() AS Updated_Date,
	k.[K_PRED]
FROM [statcom].[dbo].KATME k
  INNER JOIN [dbo].[ActivityCategories] a
    ON k.[OKED_3] = a.[Code] COLLATE Cyrillic_General_CS_AS
WHERE k.[OKED_3] IS NOT NULL
GO

DELETE FROM [dbo].[ActivityStatisticalUnits]
GO

INSERT INTO [dbo].[ActivityStatisticalUnits]
  ([Unit_Id]
  ,[Activity_Id])
SELECT
  s.[RegId],
  a.[Id]
FROM [dbo].[Activities] AS a
  INNER JOIN [dbo].[StatisticalUnits] AS s
    ON a.[K_PRED] = s.[K_PRED]
GO

INSERT INTO dbo.ActivityStatisticalUnits
SELECT
	LegalUnitId,
	Activity_Id
FROM dbo.StatisticalUnits
	INNER JOIN dbo.ActivityStatisticalUnits
		ON Unit_Id = RegId
WHERE Discriminator = 'LocalUnit' AND LegalUnitId IS NOT NULL

INSERT INTO dbo.ActivityStatisticalUnits
SELECT
	loc.RegId,
	Activity_Id
FROM dbo.StatisticalUnits leg
	INNER JOIN dbo.ActivityStatisticalUnits
		ON Unit_Id = RegId
	INNER JOIN dbo.StatisticalUnits loc
		ON loc.LegalUnitId = leg.RegId
			AND loc.K_PRED IS NULL
WHERE leg.Discriminator = 'LegalUnit'

INSERT INTO dbo.ActivityStatisticalUnits
SELECT
	EnterpriseUnitRegId,
	Activity_Id
FROM dbo.StatisticalUnits
	INNER JOIN dbo.ActivityStatisticalUnits
		ON Unit_Id = RegId
WHERE Discriminator = 'LegalUnit' AND EnterpriseUnitRegId IS NOT NULL
