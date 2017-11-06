ALTER TABLE [dbo].[Address]
ADD K_PRED FLOAT NULL
GO


--ALTER TABLE [dbo].[Address] DROP COLUMN K_PRED

DROP INDEX [IX_Address_Address_part1_Address_part2_Address_part3_Region_id_GPS_coordinates] ON [dbo].[Address]
GO


DROP INDEX [IX_Address_Region_id] ON [dbo].[Address]
GO

ALTER TABLE [dbo].[Address] DROP CONSTRAINT [FK_Address_Regions_Region_id]
GO



--CREATE UNIQUE NONCLUSTERED INDEX [IX_Address_Address_part1_Address_part2_Address_part3_Region_id_GPS_coordinates] ON [dbo].[Address]
--(
--	[Address_part1] ASC,
--	[Address_part2] ASC,
--	[Address_part3] ASC,
--	[Region_id] ASC,
--	[GPS_coordinates] ASC
--)
--WHERE ([Address_part1] IS NOT NULL AND [Address_part2] IS NOT NULL AND [Address_part3] IS NOT NULL AND [GPS_coordinates] IS NOT NULL)
--WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
--GO


--CREATE NONCLUSTERED INDEX [IX_Address_Region_id] ON [dbo].[Address]
--(
--	[Region_id] ASC
--)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
--GO



--ALTER TABLE [dbo].[Address]  WITH CHECK ADD  CONSTRAINT [FK_Address_Regions_Region_id] FOREIGN KEY([Region_id])
--REFERENCES [dbo].[Regions] ([Id])
--ON DELETE CASCADE
--GO

--ALTER TABLE [dbo].[Address] CHECK CONSTRAINT [FK_Address_Regions_Region_id]
--GO



INSERT INTO [dbo].[Address] (Address_part1, Address_part2, Address_part3, GPS_coordinates, Region_id, K_PRED)
SELECT 
	''AS  Address_part1,
	'' AS  Address_part2,	 
	[ADRESF] AS  Address_part3,	
	NULL AS  GPS_coordinates,
	r.[Id] AS  Region_id,
	[K_PRED]
FROM [statcom].[dbo].[KATME] e
	INNER JOIN [dbo].[Regions] r
    	ON e.[K_NPUF] =  r.[Code] COLLATE Cyrillic_General_CS_AS
GO


