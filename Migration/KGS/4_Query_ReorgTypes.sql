INSERT INTO [dbo].[ReorgTypes]
    ([IsDeleted]
    ,[Name])
  SELECT   
	0
	,[N_DEM]
  FROM [statcom].[dbo].[SPRDEM]
  GO

