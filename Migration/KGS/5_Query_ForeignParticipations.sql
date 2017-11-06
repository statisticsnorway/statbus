INSERT INTO [dbo].[ForeignParticipations]
    ([IsDeleted]
    ,[Name])
  SELECT   
	0
	,[N_OPF2]
  FROM [statcom].[dbo].[SPROPF2]		
  GO
GO


