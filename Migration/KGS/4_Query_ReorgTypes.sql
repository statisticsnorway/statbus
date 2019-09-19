DELETE FROM [ReorgTypes]
GO
DBCC CHECKIDENT ('dbo.ReorgTypes',RESEED, 1)
GO

INSERT INTO [dbo].[ReorgTypes]
  ([Code]
  ,[IsDeleted]
  ,[Name])
SELECT
  NULL,
  0
  ,[N_DEM]
FROM [statcom].[dbo].[SPRDEM]
GO

