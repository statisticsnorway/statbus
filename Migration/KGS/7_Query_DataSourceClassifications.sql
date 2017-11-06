INSERT INTO [dbo].[DataSourceClassifications]
    ([IsDeleted]
    ,[Name])
  SELECT   
	0
	,[NAME_IST]
  FROM [statcom].[dbo].[SPRIST]		
  GO


