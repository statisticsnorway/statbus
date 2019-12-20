/*
	RegionLevel:
		1 : Kyrgyz Republic
		2 : Area
		3 : Region
		4 : City / Village
*/
BEGIN /* INPUT PARAMETERS from report body */
	DECLARE @InRegionId INT = $RegionId,
			@InStatusId NVARCHAR(MAX) = $StatusId,
      @InCurrentYear NVARCHAR(MAX) = YEAR(GETDATE())
END
DECLARE @cols AS NVARCHAR(MAX),
    @selCols AS NVARCHAR(MAX),
		@query AS NVARCHAR(MAX), 
		@totalSumCols AS NVARCHAR(MAX), 
		@regionLevel AS NVARCHAR(MAX),
		@nameTotalColumn AS NVARCHAR(MAX)

SET @nameTotalColumn  = (SELECT TOP 1 Name FROM Regions WHERE Id = @InRegionId)
SET @cols = STUFF((SELECT distinct ',' + QUOTENAME(r.Name)
            FROM Regions r  WHERE (RegionLevel <= 3 AND r.ParentId = @InRegionId) OR r.Id = @InRegionId
            FOR XML PATH(''), TYPE
            ).value('.', 'NVARCHAR(MAX)')
        ,1,1,'')
		PRINT @cols
SET @selCols = STUFF((SELECT distinct ',' + QUOTENAME(r.Name)
            FROM Regions r  WHERE RegionLevel = 3 AND r.ParentId = @InRegionId
            FOR XML PATH(''), TYPE
            ).value('.', 'NVARCHAR(MAX)')
        ,1,1,'')
		PRINT @selCols
SET @totalSumCols = STUFF((SELECT distinct '+' + QUOTENAME(r.Name)
            FROM Regions r  WHERE (RegionLevel = 3 AND r.ParentId = @InRegionId) OR r.Id = @InRegionId
            FOR XML PATH(''), TYPE
            ).value('.', 'NVARCHAR(MAX)')
        ,1,1,'')
		PRINT @totalSumCols

/* SET THIS TO 2 if database has no Country level and begins from the Oblasts/Counties/Regions - to selectr Rayons */
SET @regionLevel = 3

/* Delete temporary table if exists */
BEGIN
IF (OBJECT_ID('tempdb..#tempRegions') IS NOT NULL)
	BEGIN DROP TABLE #tempRegions END

/* Create temporary table */
CREATE TABLE #tempRegions
(
    ID INT,
    Level INT,
    ParentId INT,
    Name NVARCHAR(MAX)
);

/* Create an index "ix_tempRegionsIndex" - to make search faster - Regions */
CREATE NONCLUSTERED INDEX ix_tempRegionsIndex ON #tempRegions ([ID]);

/* using CTE (Common Table Expressions), revursively collect the Regions tree */
;WITH RegionsCTE AS (
	SELECT Id, 0 AS Level, CAST(Id AS VARCHAR(255)) AS ParentId
	FROM Regions 

	UNION ALL

	SELECT i.Id, Level + 1, CAST(itms.ParentId AS VARCHAR(255))
	FROM Regions i
	INNER JOIN RegionsCTE itms ON itms.Id = i.ParentId
	WHERE i.ParentId>0
),

/* Select all levels from Regions and order them */
CTE_RN2 AS 
(
    SELECT Id,Level,ParentId, ROW_NUMBER() OVER (PARTITION BY r.Id ORDER BY r.Level DESC) RN
    FROM RegionsCTE r
)

/* Fill the temporary table to pivot the result */
INSERT INTO #tempRegions
SELECT r.Id, r.RN, r.ParentId, rp.Name AS ParentName
FROM CTE_RN2 r
	INNER JOIN Regions rp ON rp.Id = r.ParentId
	INNER JOIN Regions rc ON rc.Id = r.Id
END	

/*
The resulting query 
At the first checking the history logs that have StartPeriod less than current year
and then
ResultTable - get the actual state of statistical units where RegistrationDate and StartPeriod less than current year
and then
Select by Institutional Sector Codes all statistical units
and then
Count statistical units using pivot transform Regions - from column to row
*/
set @query = '
;WITH StatisticalUnitHistoryCTE AS (
	SELECT
		RegId,
		ParentId,	
		AddressId,
		InstSectorCodeId,
		ROW_NUMBER() over (partition by ParentId order by StartPeriod desc) AS RowNumber
	FROM StatisticalUnitHistory
	WHERE DATEPART(YEAR,StartPeriod)<'+@InCurrentYear+'
),
ResultTableCTE AS
(	
	SELECT
		su.RegId,
		IIF(DATEPART(YEAR, su.RegistrationDate)<'+@InCurrentYear+' AND DATEPART(YEAR,su.StartPeriod)<'+@InCurrentYear+',tr.Name, trh.Name) AS NameOblast,
		IIF(DATEPART(YEAR, su.RegistrationDate)<'+@InCurrentYear+' AND DATEPART(YEAR,su.StartPeriod)<'+@InCurrentYear+',sc.Id, sch.Id) AS SectorCodeId
	FROM StatisticalUnits su
	LEFT JOIN SectorCodes AS sc ON sc.Id = su.InstSectorCodeId		
	LEFT JOIN dbo.Address addr ON addr.Address_id = su.AddressId
	INNER JOIN #tempRegions as tr ON tr.Id = addr.Region_id	AND tr.Level = ' + @regionLevel + '			

	LEFT JOIN StatisticalUnitHistoryCTE asuhCTE ON asuhCTE.ParentId = su.RegId and asuhCTE.RowNumber = 1
	LEFT JOIN SectorCodes AS sch ON sch.Id = asuhCTE.InstSectorCodeId
	LEFT JOIN dbo.Address addrh ON addrh.Address_id = asuhCTE.AddressId
	LEFT JOIN #tempRegions as trh ON trh.Id = addrh.Region_id
    
    WHERE su.UnitStatusId = ' + @InStatusId +'
)
SELECT Name, ' + @totalSumCols + ' as [' + @nameTotalColumn+ '], ' + @selCols + ' from
            (
				SELECT
					sc.Name,
					rtCTE.RegId,
					rtCTE.NameOblast
				FROM SectorCodes as sc
				LEFT JOIN ResultTableCTE as rtCTE ON sc.Id = rtCTE.SectorCodeId
           ) SourceTable
            PIVOT 
            (
                COUNT(RegId)
                FOR NameOblast IN (' + @cols + ')
            ) PivotTable'

/* execution of the query */
execute(@query)
