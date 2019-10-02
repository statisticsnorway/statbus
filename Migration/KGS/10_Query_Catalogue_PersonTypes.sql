DELETE FROM [dbo].[PersonTypes]
GO
DBCC CHECKIDENT ('dbo.PersonTypes',RESEED, 1)
GO

-- Strict insert, please edit insert values

INSERT INTO [dbo].[PersonTypes]
  ([IsDeleted],[Name],[NameLanguage1],[NameLanguage2])
VALUES
  (0, 'Contact Person', NULL, NULL),
  (0, 'Founder', NULL, NULL),
  (0, 'Owner', NULL, NULL),
  (0, 'Director', NULL, NULL)
GO
