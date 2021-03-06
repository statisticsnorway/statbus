DELETE FROM [dbo].[LegalForms]
GO
DBCC CHECKIDENT ('dbo.LegalForms',RESEED, 1)
GO

-- Strict insert, please edit insert values

INSERT INTO [dbo].[LegalForms]
  ([Code],[IsDeleted],[Name],[NameLanguage1],[NameLanguage2],[ParentId])
VALUES
  ('Code1', 0, 'Name', 'NameLanguage1', 'NameLanguage2', NULL),
  ('Code2', 0, 'Name', 'NameLanguage1', 'NameLanguage2', NULL)
GO

-- OR select from other database

-- INSERT INTO [dbo].[LegalForms]
--   ([Code],[IsDeleted],[Name],[NameLanguage1],[NameLanguage2],[ParentId])
-- SELECT 
--   [K_OPF]
--   ,0
--   ,[N_OPF]
--   ,NULL
--   ,NULL
--   ,NULL
-- FROM [statcom].[dbo].[SPROPF]
-- GO
