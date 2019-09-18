DELETE FROM [dbo].[UnitsSize]
GO
DBCC CHECKIDENT ('dbo.UnitsSize',RESEED, 1)
GO
  
INSERT INTO [dbo].[UnitsSize]
  ([IsDeleted]
  ,[Name])
SELECT 0,'Small'
UNION ALL 
SELECT 0,'Medium'
UNION ALL 
SELECT 0,'Large'
GO


