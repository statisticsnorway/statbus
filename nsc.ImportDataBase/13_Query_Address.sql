DELETE FROM [Address]
GO
DBCC CHECKIDENT ('dbo.Address',RESEED, 1)
GO

-- DROP INDEX [IX_Address_Address_part1_Address_part2_Address_part3_Region_id_Latitude_Longitude] ON [dbo].[Address]
-- GO

-- DROP INDEX [IX_Address_Region_id] ON [dbo].[Address]
-- GO

-- ALTER TABLE [dbo].[Address] DROP CONSTRAINT [FK_Address_Regions_Region_id]
-- GO

ALTER TABLE [dbo].[Address]
ADD K_PRED FLOAT NULL
GO

INSERT INTO [dbo].[Address]
	([Address_part1]
	,[Address_part2]
	,[Address_part3]
	,[Latitude]
	,[Longitude]
	,[Region_id]
	,[K_PRED])
SELECT
	'' AS Address_part1,
	'' AS Address_part2,
	[ADRESF] AS Address_part3,
	NULL AS Latitude,
	NULL AS Longitude,
	[dbo].[Regions].[Id] AS Region_id,
	[K_PRED]
FROM [statcom].[dbo].[KATME]
	INNER JOIN [dbo].[Regions]
        ON [dbo].[KATME].[K_NPUF] = [dbo].[Regions].[Code] COLLATE Cyrillic_General_CS_AS
GO

--ALTER TABLE [dbo].[Address] DROP COLUMN K_PRED
