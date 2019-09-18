DELETE FROM [Statuses]
GO
DBCC CHECKIDENT ('dbo.Statuses',RESEED, 1)
GO

INSERT INTO [dbo].[Statuses]
  ([Code]
  ,[IsDeleted]
  ,[Name])
SELECT
  ,NULL
  ,0
  ,[N_AKTIV]
FROM [statcom].[dbo].[SPRAKTIV]
GO