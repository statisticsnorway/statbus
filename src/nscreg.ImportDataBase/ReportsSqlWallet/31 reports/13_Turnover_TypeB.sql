/* Table B would get one top level region for total
    And sub-level regions column
    Row headers - Turnover variables
    Column headers - Sub-level of Oblasts/Regions/Counties, Rayons level
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
	DECLARE @InRegionId NVARCHAR(MAX) = $RegionId,
			    @InStatusId NVARCHAR(MAX) = $StatusId,
          @InStatUnitType NVARCHAR(MAX) = $StatUnitType,
          @InCurrentYear NVARCHAR(MAX) = YEAR(GETDATE())
END

/* Declare variables */
DECLARE @cols AS NVARCHAR(MAX),
    @selCols AS NVARCHAR(MAX),
		@selectCols AS NVARCHAR(MAX),
		@query AS NVARCHAR(MAX),
		@totalSumCols AS NVARCHAR(MAX),
		@regionLevel AS NVARCHAR(MAX),
		@nameTotalColumn AS NVARCHAR(MAX)

SET @selectCols = STUFF((SELECT distinct ','+QUOTENAME(r.Name)
			FROM Regions r  WHERE (RegionLevel <= 3 AND r.ParentId = @InRegionId) OR r.Id = @InRegionId
			FOR XML PATH(''), TYPE
			).value('.', 'NVARCHAR(MAX)')
		,1,1,'')

/* Name of oblast/county for total column */
SET @nameTotalColumn  = (SELECT TOP 1 Name FROM Regions WHERE Id = @InRegionId)

/* List of Rayons/Municipalities/Sub-level of Oblast LEVEL */
SET @selCols = STUFF((SELECT distinct ',ISNULL(' + QUOTENAME(r.Name)+',0) AS "' + r.Name + '"'
            /* RegionLevel = 2 - if there no Country Level in the Regions database */
            FROM Regions r  WHERE RegionLevel = 3 AND r.ParentId = @InRegionId
            FOR XML PATH(''), TYPE
            ).value('.', 'NVARCHAR(MAX)')
        ,1,1,'')
		PRINT @selCols

/* Column - Total count of statistical units by selected region */
SET @totalSumCols = STUFF((SELECT distinct '+ISNULL(' + QUOTENAME(r.Name)+',0)'
            /* RegionLevel = 2 - if there no Country Level in the Regions database */
            FROM Regions r  WHERE (RegionLevel = 3 AND r.ParentId = @InRegionId) OR r.Id = @InRegionId
            FOR XML PATH(''), TYPE
            ).value('.', 'NVARCHAR(MAX)')
        ,1,1,'')
		PRINT @totalSumCols

/* Set @regionLevel = 2 if database has no Country level and begins from the Oblasts/Counties/Regions */
SET @regionLevel = 3

/* Declare and fill Regions tree */
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
END

/*
The resulting query
At the first checking the history logs that have StartPeriod less than current year
and then
ResultTable - list with all stat units were active in given dateperiod and have required StatUnitType
and then
Count statistical units and using the pivot - transform from regions column to regions row

if you want to edit the turnover condition values and output row headers,
please check the output row header and the conditions list,
they must be the same
*/
set @query = '
DECLARE @listOfResultRows TABLE (ID INT, Turnover NVARCHAR(MAX))
INSERT INTO @listOfResultRows(ID,Turnover)
VALUES
(0,N''No turnover''),
(1,N''1 - 4''),
(2,N''5 - 9''),
(3,N''10 - 19''),
(4,N''20 - 49''),
(5,N''50 - 99''),
(6,N''100 - 249''),
(7,N''250 +'')

;WITH StatisticalUnitHistoryCTE AS (
	SELECT
		RegId,
		ParentId,
		AddressId,
		ROW_NUMBER() over (partition by ParentId order by StartPeriod desc) AS RowNumber
	FROM StatisticalUnitHistory
	WHERE DATEPART(YEAR,StartPeriod)<'+@InCurrentYear+'
),
ResultTableCTE AS
(
	SELECT
		su.RegId,
		IIF(DATEPART(YEAR, su.RegistrationDate)<'+@InCurrentYear+' AND DATEPART(YEAR,su.StartPeriod)<'+@InCurrentYear+',tr.Name, trh.Name) AS NameOblast
	FROM StatisticalUnits su
	LEFT JOIN dbo.Address addr ON addr.Address_id = su.AddressId
	INNER JOIN #tempRegions as tr ON tr.Id = addr.Region_id	AND tr.Level = ' + @InRegionId + '

	LEFT JOIN StatisticalUnitHistoryCTE asuhCTE ON asuhCTE.ParentId = su.RegId and asuhCTE.RowNumber = 1
	LEFT JOIN dbo.Address addrh ON addrh.Address_id = asuhCTE.AddressId
	LEFT JOIN #tempRegions as trh ON trh.Id = addrh.Region_id
    WHERE ('''+@InStatUnitType+''' = ''All'' OR su.Discriminator = '''+@InStatUnitType+''') AND ('+@InStatusId+' = 0 OR su.UnitStatusId = ' + @InStatusId +')
),
TurnoverCTE AS
(
	SELECT
		CASE WHEN COUNT(rtCTE.RegId)=0 THEN 0
				WHEN (COUNT(rtCTE.RegId)>=1 AND COUNT(rtCTE.RegId)<=4) THEN 1
				WHEN (COUNT(rtCTE.RegId)>=5 AND COUNT(rtCTE.RegId)<=9) THEN 2
				WHEN (COUNT(rtCTE.RegId)>=10 AND COUNT(rtCTE.RegId)<=19) THEN 3
				WHEN (COUNT(rtCTE.RegId)>=20 AND COUNT(rtCTE.RegId)<=49) THEN 4
				WHEN (COUNT(rtCTE.RegId)>=50 AND COUNT(rtCTE.RegId)<=99) THEN 5
				WHEN (COUNT(rtCTE.RegId)>=100 AND COUNT(rtCTE.RegId)<=99) THEN 6
				WHEN (COUNT(rtCTE.RegId)>250) THEN 7
		ELSE 0 END as TurnoverId,
		COUNT(rtCTE.RegId) as Count,
		rtCTE.NameOblast
	FROM ResultTableCTE as rtCTE
	GROUP BY rtCTE.NameOblast
)

SELECT Turnover, ' + @totalSumCols + ' as [' + @nameTotalColumn+ '], ' + @selCols + ' from
            (
				SELECT
					l.Turnover,
					l.Id,
					tcte.Count,
					tcte.NameOblast
				FROM @listOfResultRows as l
				LEFT JOIN TurnoverCTE as tcte ON l.Id = tcte.TurnoverId
           ) SourceTable
            PIVOT
            (
                SUM(Count)
                FOR NameOblast IN (' + @selectCols + ')
            ) PivotTable'
/* execution of the query */
execute(@query)
