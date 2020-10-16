/* Table B would get one top level region at total
    And sub-level regions at the first column
    Row headers - UnitsSize
    Column headers - Sub-level Oblasts/Regions/Counties, Rayons level
 */

/*
	RegionLevel for kyrgyz database:
		1 Level : Kyrgyz Republic - Country level
		2 Level : Area, Oblast, Region, Counties
		3 Level : Rayon
		4 Level : City / Village
    Note: if you haven't region level for country Region/Counties etc would be 1 Level
*/

/* Input parameters from report body - filters that have to be defined by the user */
BEGIN
	DECLARE @InRegionId INT = $RegionId,
			@InStatusId NVARCHAR(MAX) = $StatusId,
			@InCurrentYear NVARCHAR(MAX) = YEAR(GETDATE())
END

/* Declare variables */
DECLARE @cols AS NVARCHAR(MAX),
    @selCols AS NVARCHAR(MAX),
		@query AS NVARCHAR(MAX),
		@totalSumCols AS NVARCHAR(MAX),
		@regionLevel AS NVARCHAR(MAX),
		@nameTotalColumn AS NVARCHAR(MAX)

/* Name of oblast/county for total column */
SET @nameTotalColumn  = (SELECT TOP 1 Name FROM Regions WHERE Id = @InRegionId)

/* Column - REGIONS, COUNTRY LEVEL */
SET @cols = STUFF((SELECT distinct ',' + QUOTENAME(r.Name)
            /* RegionLevel <= 2 - if there no Country Level in the Regions database */
            FROM Regions r  WHERE (RegionLevel <= 3 AND r.ParentId = @InRegionId) OR r.Id = @InRegionId
            FOR XML PATH(''), TYPE
            ).value('.', 'NVARCHAR(MAX)')
        ,1,1,'')
		PRINT @cols

/* List of Rayons/Municipalities/Sub-level of Oblast LEVEL */
SET @selCols = STUFF((SELECT distinct ',' + QUOTENAME(r.Name)
            /* RegionLevel = 2 - if there no Country Level in the Regions database */
            FROM Regions r  WHERE RegionLevel = 3 AND r.ParentId = @InRegionId
            FOR XML PATH(''), TYPE
            ).value('.', 'NVARCHAR(MAX)')
        ,1,1,'')
		PRINT @selCols

/* Column - Total of statistical units by selected region */
SET @totalSumCols = STUFF((SELECT distinct '+' + QUOTENAME(r.Name)
            /* RegionLevel = 2 - if there no Country Level in the Regions database */
            FROM Regions r  WHERE (RegionLevel = 3 AND r.ParentId = @InRegionId) OR r.Id = @InRegionId
            FOR XML PATH(''), TYPE
            ).value('.', 'NVARCHAR(MAX)')
        ,1,1,'')
		PRINT @totalSumCols

/* Set @regionLevel = 2 if database has no Country level and begins from the Oblasts/Counties/Regions */
SET @regionLevel = 3


/* Declare and fill Regions tree*/
BEGIN

/* Delete a temporary table #tempRegions if exists */
IF (OBJECT_ID('tempdb..#tempRegions') IS NOT NULL)
	BEGIN DROP TABLE #tempRegions END

/* Create a temporary table #tempRegions */
CREATE TABLE #tempRegions
(
    ID INT,
    Level INT,
    ParentId INT,
    Name NVARCHAR(MAX)
);

/* Create an index "ix_tempRegionsIndex" - to make search faster - Regions */
CREATE NONCLUSTERED INDEX ix_tempRegionsIndex ON #tempRegions ([ID]);

/* using CTE (Common Table Expressions), recursively collect the Regions tree */
;WITH RegionsCTE AS (
	SELECT Id, 0 AS Level, CAST(Id AS VARCHAR(255)) AS ParentId
	FROM Regions

	UNION ALL

	SELECT i.Id, Level + 1, CAST(itms.ParentId AS VARCHAR(255))
	FROM Regions i
	INNER JOIN RegionsCTE itms ON itms.Id = i.ParentId
	WHERE i.ParentId>0
),

/* Select all levels from Regions and order them by level */
CTE_RN2 AS
(
    SELECT Id,Level,ParentId, ROW_NUMBER() OVER (PARTITION BY r.Id ORDER BY r.Level DESC) RN
    FROM RegionsCTE r
)

/* Fill with data #tempRegions */
INSERT INTO #tempRegions
SELECT r.Id, r.RN, r.ParentId, rp.Name AS ParentName
FROM CTE_RN2 r
	INNER JOIN Regions rp ON rp.Id = r.ParentId
	INNER JOIN Regions rc ON rc.Id = r.Id
WHERE r.RN = @regionLevel OR (r.Id = @InRegionId AND r.RN = 2)
END


/*
The resulting query
At the first checking the history logs that have StartPeriod less than current year
and then
ResultTable - list with all stat units linked to UnitsSize catalog and were active in given dateperiod and have required StatUnitType
and then
Count statistical units and using the pivot - transform from regions column to regions row
*/
set @query = '
;WITH StatisticalUnitHistoryCTE AS (
	SELECT
		RegId,
		ParentId,
		AddressId,
		SizeId,
		UnitStatusId,
		ROW_NUMBER() over (partition by ParentId order by StartPeriod desc) AS RowNumber
	FROM StatisticalUnitHistory
	WHERE DATEPART(YEAR,StartPeriod)<'+@InCurrentYear+'
),
ResultTableCTE AS
(
	SELECT
		IIF(DATEPART(YEAR, su.RegistrationDate)<'+@InCurrentYear+' AND DATEPART(YEAR,su.StartPeriod)<'+@InCurrentYear+',su.RegId, asuhCTE.RegId) AS RegId,
		IIF(DATEPART(YEAR, su.RegistrationDate)<'+@InCurrentYear+' AND DATEPART(YEAR,su.StartPeriod)<'+@InCurrentYear+',su.AddressId,asuhCTE.AddressId) AS AddressId,
		IIF(DATEPART(YEAR, su.RegistrationDate)<'+@InCurrentYear+' AND DATEPART(YEAR,su.StartPeriod)<'+@InCurrentYear+',su.UnitStatusId,asuhCTE.UnitStatusId) AS UnitStatusId,
		IIF(DATEPART(YEAR, su.RegistrationDate)<'+@InCurrentYear+' AND DATEPART(YEAR,su.StartPeriod)<'+@InCurrentYear+',us.Id, ush.Id) AS SizeId,
		IIF(DATEPART(YEAR, su.RegistrationDate)<'+@InCurrentYear+' AND DATEPART(YEAR,su.StartPeriod)<'+@InCurrentYear+',0,1) AS isHistory
	FROM StatisticalUnits AS su
		LEFT JOIN UnitsSize AS us ON us.Id = su.SizeId

		LEFT JOIN StatisticalUnitHistoryCTE asuhCTE ON asuhCTE.ParentId = su.RegId and asuhCTE.RowNumber = 1
		LEFT JOIN UnitsSize AS ush ON ush.Id = asuhCTE.SizeId

    WHERE su.IsDeleted = 0
),
ResultTableCTE2 AS
(
	SELECT
		RegId,
		tr.Name AS NameOblast,
		rt.SizeId,
		rt.isHistory
	FROM ResultTableCTE AS rt
		LEFT JOIN dbo.Address AS addr ON addr.Address_id = rt.AddressId
		INNER JOIN #tempRegions AS tr ON tr.Id = addr.Region_id
	WHERE '+@InStatusId+' = 0 OR rt.UnitStatusId = '+@InStatusId+'
)

SELECT Name, ' + @totalSumCols + ' as [' + @nameTotalColumn+ '], ' + @selCols + ' from
            (
				SELECT
					us.Name,
					rtCTE.RegId,
					rtCTE.NameOblast
				FROM UnitsSize as us
				LEFT JOIN ResultTableCTE2 as rtCTE ON us.Id = rtCTE.SizeId
           ) SourceTable
            PIVOT
            (
                COUNT(RegId)
                FOR NameOblast IN (' + @cols + ')
            ) PivotTable'
/* execution of the query */
execute(@query)
