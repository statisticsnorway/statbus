DELETE FROM [ForeignParticipations]
GO
DBCC CHECKIDENT ('dbo.ForeignParticipations',RESEED, 1)
GO

INSERT INTO [dbo].[ForeignParticipations]
  ([Code]
  ,[IsDeleted]
  ,[Name])
SELECT   
  NULL,
  0
  ,[N_OPF2]
FROM [statcom].[dbo].[SPROPF2]		
GO


