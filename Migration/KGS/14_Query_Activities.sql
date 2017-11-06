  DELETE FROM [dbo].[Activities]
  GO
  DBCC CHECKIDENT ('nscreg.dbo.Activities',RESEED, 0)
  GO
  
  ALTER TABLE [dbo].[Activities]
  ADD K_PRED FLOAT NULL
  GO
  
  DECLARE @guid NVARCHAR(450)
  SELECT @guid = Id FROM [dbo].[AspNetUsers]

  INSERT INTO [dbo].[Activities] (
	[ActivityCategoryId]
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
  
  INSERT INTO [dbo].[ActivityStatisticalUnits] ( [Unit_Id], [Activity_Id])
  SELECT s.[RegId], a.[Id]
    FROM [dbo].[Activities] AS a
      INNER JOIN [dbo].[StatisticalUnits] AS s
	    ON a.[K_PRED] = s.[K_PRED]
  GO