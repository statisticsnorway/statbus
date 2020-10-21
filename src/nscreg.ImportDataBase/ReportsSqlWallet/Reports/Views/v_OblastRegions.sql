CREATE OR ALTER VIEW vw_OblastRegions
AS 
SELECT
    Id,
    Name
FROM
    Regions
WHERE RegionLevel =  IIF(dbo.HasCountryAsLevel1() = 1,2,1)

