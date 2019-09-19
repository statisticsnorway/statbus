ALTER TABLE [dbo].[StatisticalUnits] DROP CONSTRAINT [FK_StatisticalUnits_DataSourceClassifications_DataSourceClassificationId]
ALTER TABLE [dbo].[EnterpriseGroups] DROP CONSTRAINT [FK_EnterpriseGroups_DataSourceClassifications_DataSourceClassificationId]

TRUNCATE TABLE [dbo].[DataSourceClassifications]

INSERT INTO [dbo].[DataSourceClassifications]
  ([Name]
  ,[Code]
  ,[IsDeleted])
VALUES
  ('Указ Президента Кыргызской  Республики', '1', 0),
  ('Постановление Правительства Кыргызской Республики', '2', 0),
  ('Административный регистр Государственной Налоговой Службы (ГНС)', '3', 0),
  ('Приказ Министерства  юстиции о регистрации (перерегистрации) юридического лица', '4', 0),
  ('Извещение Министерства юстиции', '5', 0),
  ('Список ликвидируемых хозяйствующих субъектов', '6', 0),
  ('Выборочное статистическое обследование', '7', 0),
  ('Статистическая отчетность', '8', 0),
  ('Приказ СЭЗ', '9', 0)

ALTER TABLE [dbo].[StatisticalUnits]  WITH CHECK ADD  CONSTRAINT [FK_StatisticalUnits_DataSourceClassifications_DataSourceClassificationId] FOREIGN KEY([DataSourceClassificationId])
REFERENCES [dbo].[DataSourceClassifications] ([Id])
ALTER TABLE [dbo].[EnterpriseGroups]  WITH CHECK ADD  CONSTRAINT [FK_EnterpriseGroups_DataSourceClassifications_DataSourceClassificationId] FOREIGN KEY([DataSourceClassificationId])
REFERENCES [dbo].[DataSourceClassifications] ([Id])

ALTER TABLE [dbo].[StatisticalUnits] CHECK CONSTRAINT [FK_StatisticalUnits_DataSourceClassifications_DataSourceClassificationId]
ALTER TABLE [dbo].[EnterpriseGroups] CHECK CONSTRAINT [FK_EnterpriseGroups_DataSourceClassifications_DataSourceClassificationId]
