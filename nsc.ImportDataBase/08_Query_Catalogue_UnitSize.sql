DELETE FROM [dbo].[UnitsSize]
GO
DBCC CHECKIDENT ('dbo.UnitsSize',RESEED, 1)
GO

-- Strict insert, please edit insert values

INSERT INTO [dbo].[UnitsSize]
  ([IsDeleted],[Name],[NameLanguage1],[NameLanguage2])
VALUES
  (0, 'Small', NULL, NULL),
  (0, 'Medium', NULL, NULL),
  (0, 'Large', NULL, NULL)
GO
