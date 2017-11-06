INSERT INTO [dbo].[UnitStatuses]
    ([IsDeleted]
    ,[Name])
  SELECT   
	0
	,[N_AKTIV]
  FROM [statcom].[dbo].[SPRAKTIV]
  GO
GO


