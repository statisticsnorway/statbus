DELETE FROM [DataSourceClassifications]
GO
DBCC CHECKIDENT ('dbo.DataSourceClassifications',RESEED, 1)
GO

-- Strict insert, please edit insert values

INSERT INTO [dbo].[DataSourceClassifications]
  ([Code],[IsDeleted],[Name],[NameLanguage1],[NameLanguage2])
VALUES
  ('1', 0, 'Указ Президента Кыргызской  Республики', NULL, NULL),
  ('2', 0, 'Постановление Правительства Кыргызской Республики', NULL, NULL),
  ('3', 0, 'Административный регистр Государственной Налоговой Службы (ГНС)', NULL, NULL),
  ('4', 0, 'Приказ Министерства  юстиции о регистрации (перерегистрации) юридического лица', NULL, NULL),
  ('5', 0, 'Извещение Министерства юстиции', NULL, NULL),
  ('6', 0, 'Список ликвидируемых хозяйствующих субъектов', NULL, NULL),
  ('7', 0, 'Выборочное статистическое обследование', NULL, NULL),
  ('8', 0, 'Статистическая отчетность', NULL, NULL),
  ('9', 0, 'Приказ СЭЗ', NULL, NULL)
GO

-- OR select from other database

-- INSERT INTO [dbo].[DataSourceClassifications]
--   ([Code],[IsDeleted],[Name],[NameLanguage1],[NameLanguage2])
-- SELECT   
--   ,NULL
--   ,0
--   ,[NAME_IST]
--   ,NULL
--   ,NULL
-- FROM [statcom].[dbo].[SPRIST]		
-- GO
