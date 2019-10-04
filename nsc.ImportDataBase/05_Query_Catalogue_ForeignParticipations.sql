DELETE FROM [ForeignParticipations]
GO
DBCC CHECKIDENT ('dbo.ForeignParticipations',RESEED, 1)
GO

-- Strict insert, please edit insert values

INSERT INTO [dbo].[ForeignParticipations]
  ([Code],[IsDeleted],[Name],[NameLanguage1],[NameLanguage2])
VALUES
  ('Code1', 0, 'Name', 'NameLanguage1', 'NameLanguage2'),
  ('Code2', 0, 'Name', 'NameLanguage1', 'NameLanguage2')
GO

-- OR select from other database

-- INSERT INTO [dbo].[ForeignParticipations]
--   ([Code],[IsDeleted],[Name],[NameLanguage1],[NameLanguage2])
-- SELECT   
--   NULL,
--   0
--   ,[N_OPF2]
--   ,NULL
--   ,NULL
-- FROM [statcom].[dbo].[SPROPF2]		
-- GO
