DELETE FROM [Statuses]
GO
DBCC CHECKIDENT ('dbo.Statuses',RESEED, 1)
GO
-- Note: [Statuses] table must have "Liquidated" status with Code = 7 
-- Strict insert, please edit insert values

INSERT INTO [dbo].[Statuses]
  ([Code],[IsDeleted],[Name],[NameLanguage1],[NameLanguage2])
VALUES
  ('1', 0, 'Единица действует (активная)', NULL, NULL),
  ('2', 0, 'Единица простаивает не более 1 года («спящая» единица)', NULL, NULL),
  ('3', 0, 'Единица находится в стадии ликвидации', NULL, NULL),
  ('4', 0, 'Вновь созданная статистическая единица', NULL, NULL),
  ('5', 0, 'Единица не действует (неактивная)', NULL, NULL),
  ('6', 0, 'Субъекты, не осуществляющие деятельность более 10 лет', NULL, NULL),
  ('7', 0, 'Единица ликвидирована', NULL, NULL),
  ('8', 0, 'Единица удалена', NULL, NULL),
  ('9', 0, 'Единица восстановлена', NULL, NULL),
  ('0', 0, 'Нет информации о единице', NULL, NULL)
GO

-- OR select from other database

-- INSERT INTO [dbo].[Statuses]
--   ([Code],[IsDeleted],[Name],[NameLanguage1],[NameLanguage2])
-- SELECT
--   ,NULL
--   ,0
--   ,[N_AKTIV]
--   ,NULL
--   ,NULL
-- FROM [statcom].[dbo].[SPRAKTIV]
-- GO
