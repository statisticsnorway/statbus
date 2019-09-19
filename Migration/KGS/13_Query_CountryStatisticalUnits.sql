DELETE FROM [CountryStatisticalUnits]
GO
DBCC CHECKIDENT ('dbo.CountryStatisticalUnits',RESEED, 1)
GO

INSERT INTO [dbo].[CountryStatisticalUnits]
    ([Unit_Id]
    ,[Country_Id])
SELECT 
	su.RegId
	, c.Id	
FROM [statcom].[dbo].[KATME_LAND] kl
INNER JOIN [dbo].[Countries] c
	ON c.[IsoCode] = kl.ZAR_PAR
INNER JOIN [dbo].[StatisticalUnits] su
	ON kl.K_PRED = su.K_PRED
GROUP BY su.RegId, c.Id	