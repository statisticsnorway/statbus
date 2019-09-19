DELETE FROM [DataSourceClassifications]
GO
DBCC CHECKIDENT ('dbo.DataSourceClassifications',RESEED, 1)
GO

INSERT INTO [dbo].[DataSourceClassifications]
  ([Code]
  ,[IsDeleted]
  ,[Name])
SELECT   
  ,NULL
  ,0
  ,[NAME_IST]
FROM [statcom].[dbo].[SPRIST]		
GO