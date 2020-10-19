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
	DECLARE @InRegionId INT = $RegionId,
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
SET @selCols = dbo.GetRayonsColumnNamesWithNullCheck(@InRegionId);
SET @cols = dbo.GetRayonsColumnNames(@InRegionId);
/* Column - Total count of statistical units by selected region */
SET @totalSumCols = dbo.CountTotalInRayonsAsSql(@InRegionId);

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
WHERE r.RN = @regionLevel OR (r.Id = @InRegionId AND r.RN = 2)
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
		Discriminator,
		UnitStatusId,
		Turnover,
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
		IIF(DATEPART(YEAR, su.RegistrationDate)<'+@InCurrentYear+' AND DATEPART(YEAR,su.StartPeriod)<'+@InCurrentYear+',su.Discriminator,asuhCTE.Discriminator) AS Discriminator,
		IIF(DATEPART(YEAR, su.RegistrationDate)<'+@InCurrentYear+' AND DATEPART(YEAR,su.StartPeriod)<'+@InCurrentYear+',su.Turnover,asuhCTE.Turnover) AS Turnover,
		IIF(DATEPART(YEAR, su.RegistrationDate)<'+@InCurrentYear+' AND DATEPART(YEAR,su.StartPeriod)<'+@InCurrentYear+',0,1) AS isHistory
	FROM StatisticalUnits AS su
		LEFT JOIN StatisticalUnitHistoryCTE asuhCTE ON asuhCTE.ParentId = su.RegId and asuhCTE.RowNumber = 1
    WHERE su.IsDeleted = 0
),
ResultTableCTE2 AS
(
	SELECT
		RegId,
		tr.Name AS NameOblast,
		Turnover
	FROM ResultTableCTE AS rt
		LEFT JOIN dbo.Address AS addr ON addr.Address_id = rt.AddressId
		INNER JOIN #tempRegions AS tr ON tr.Id = addr.Region_id

	WHERE (''' + @InStatUnitType + ''' = ''All'' OR (rt.isHistory = 0 AND  rt.Discriminator = ''' + @InStatUnitType + ''') 
				OR (rt.isHistory = 1 AND rt.Discriminator = ''' + @InStatUnitType + 'History' + '''))
			AND ('+@InStatusId+' = 0 OR rt.UnitStatusId = '+@InStatusId+')
),
TurnoverCTE AS
(
	SELECT
		CASE WHEN (rtCTE.Turnover=0 OR rtCTE.Turnover IS NULL) THEN 0
				WHEN (rtCTE.Turnover>0 AND rtCTE.Turnover<5) THEN 1
				WHEN (rtCTE.Turnover>=5 AND rtCTE.Turnover<10) THEN 2
				WHEN (rtCTE.Turnover>=10 AND rtCTE.Turnover<20) THEN 3
				WHEN (rtCTE.Turnover>=20 AND rtCTE.Turnover<50) THEN 4
				WHEN (rtCTE.Turnover>=50 AND rtCTE.Turnover<100) THEN 5
				WHEN (rtCTE.Turnover>=100 AND rtCTE.Turnover<250) THEN 6
				WHEN (rtCTE.Turnover>=250) THEN 7
		ELSE 0 END as TurnoverId,
		rtCTE.NameOblast
	FROM ResultTableCTE2 as rtCTE
	WHERE rtCTE.Turnover IS NOT NULL
)

SELECT Turnover, ' + @totalSumCols + ' as [' + @nameTotalColumn+ '], ' + @selCols + ' from
            (
				SELECT
					l.Turnover,
					l.Id,
					tcte.TurnoverId,
					tcte.NameOblast
				FROM @listOfResultRows as l
				LEFT JOIN TurnoverCTE as tcte ON l.Id = tcte.TurnoverId
           ) SourceTable
            PIVOT
            (
                COUNT(TurnoverId)
                FOR NameOblast IN (' + @selectCols + ')
            ) PivotTable'
/* execution of the query */
execute(@query)
