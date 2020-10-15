/* Table A would get all top level regions
    Row headers - Institutional Sector Codes
    Column headers - Oblasts/Regions/Counties
 */

/* Input parameters from report body - filters that have to be defined by the user */
BEGIN
	DECLARE @InStatusId NVARCHAR(MAX) = $StatusId,
			@InStatUnitType NVARCHAR(MAX) = $StatUnitType,
			@InCurrentYear NVARCHAR(MAX) = YEAR(GETDATE())
END

/* Declare variables */
DECLARE @cols AS NVARCHAR(MAX),
    @colsWithNullCheck AS NVARCHAR(MAX),
		@query  AS NVARCHAR(MAX),
		@totalSumCols AS NVARCHAR(MAX),
		@regionLevel AS NVARCHAR(MAX)

/* Column - REGIONS, COUNTRY LEVEL */
SET @cols = dbo.GetOblastColumnNames();
SET @colsWithNullCheck = dbo.GetOblastColumnNamesWithNullCheck();

/* Column - Total count of statistical units by whole country */
SET @totalSumCols = dbo.CountTotalEmployeesInOblastsAsSql();

/* Set @regionLevel = 1 if database has no Country level and begins from the Oblasts/Counties/Regions */
SET @regionLevel = 2

/* Delete a temporary table #tempRegions if exists */
BEGIN
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

/* Select all levels from Regions and order them */
CTE_RN2 AS
(
    SELECT Id,Level,ParentId, ROW_NUMBER() OVER (PARTITION BY r.Id ORDER BY r.Level DESC) RN
    FROM RegionsCTE r
)

/* Fill with data #tempRegions table */
INSERT INTO #tempRegions
SELECT r.Id, r.RN, r.ParentId, rp.Name AS ParentName
FROM CTE_RN2 r
	INNER JOIN Regions rp ON rp.Id = r.ParentId
	INNER JOIN Regions rc ON rc.Id = r.Id
WHERE r.RN = @regionLevel or r.Id = 1
END

/*
The resulting query
At the first checking the history logs that have StartPeriod less than current year
and then
ResultTable - get the actual state of statistical units where RegistrationDate and StartPeriod less than current year
and then
Count statistical units and using the pivot - transform from regions column to regions row
*/
set @query = '
;WITH StatisticalUnitHistoryCTE AS (
	SELECT
		RegId,
		ParentId,
		AddressId,
		UnitStatusId,
		Discriminator,
		InstSectorCodeId,
		ROW_NUMBER() over (partition by ParentId order by StartPeriod desc) AS RowNumber
	FROM StatisticalUnitHistory
	WHERE DATEPART(YEAR,StartPeriod)<'+@InCurrentYear+'
),
ResultTableCTE AS
(
	SELECT
		IIF(DATEPART(YEAR, su.RegistrationDate)<'+@InCurrentYear+' AND DATEPART(YEAR,su.StartPeriod)<'+@InCurrentYear+',su.RegId, asuhCTE.RegId) AS RegId,
		IIF(DATEPART(YEAR, su.RegistrationDate)<'+@InCurrentYear+' AND DATEPART(YEAR,su.StartPeriod)<'+@InCurrentYear+',su.AddressId,asuhCTE.AddressId) AS AddressId,
		IIF(DATEPART(YEAR, su.RegistrationDate)<'+@InCurrentYear+' AND DATEPART(YEAR,su.StartPeriod)<'+@InCurrentYear+',su.Discriminator,asuhCTE.Discriminator) AS Discriminator,
		IIF(DATEPART(YEAR, su.RegistrationDate)<'+@InCurrentYear+' AND DATEPART(YEAR,su.StartPeriod)<'+@InCurrentYear+',su.UnitStatusId,asuhCTE.UnitStatusId) AS UnitStatusId,
		IIF(DATEPART(YEAR, su.RegistrationDate)<'+@InCurrentYear+' AND DATEPART(YEAR,su.StartPeriod)<'+@InCurrentYear+',sc.Id, sch.Id) AS SectorCodeId,
		IIF(DATEPART(YEAR, su.RegistrationDate)<'+@InCurrentYear+' AND DATEPART(YEAR,su.StartPeriod)<'+@InCurrentYear+',0,1) AS isHistory
	FROM StatisticalUnits AS su
		LEFT JOIN SectorCodes AS sc ON sc.Id = su.InstSectorCodeId
		
		LEFT JOIN StatisticalUnitHistoryCTE asuhCTE ON asuhCTE.ParentId = su.RegId and asuhCTE.RowNumber = 1
		LEFT JOIN SectorCodes AS sch ON sch.Id = asuhCTE.InstSectorCodeId
    WHERE su.IsDeleted = 0
),
ResultTableCTE2 AS
(
	SELECT
		RegId,
		tr.Name AS NameOblast,
		rt.SectorCodeId
	FROM ResultTableCTE AS rt
		LEFT JOIN dbo.Address AS addr ON addr.Address_id = rt.AddressId
		INNER JOIN #tempRegions AS tr ON tr.Id = addr.Region_id
	WHERE (''' + @InStatUnitType + ''' = ''All'' OR (rt.isHistory = 0 AND  rt.Discriminator = ''' + @InStatUnitType + ''') 
				OR (rt.isHistory = 1 AND rt.Discriminator = ''' + @InStatUnitType + 'History' + '''))
			AND ('+@InStatusId+' = 0 OR rt.UnitStatusId = '+@InStatusId+')
)

SELECT Name, ' + @totalSumCols + ' as Total, ' + @colsWithNullCheck + ' from
           (
				SELECT
					sc.Name,
					rtCTE.RegId,
					rtCTE.NameOblast
				FROM SectorCodes as sc
				LEFT JOIN ResultTableCTE2 as rtCTE ON sc.Id = rtCTE.SectorCodeId
           ) SourceTable
            PIVOT
            (
                COUNT(RegId)
                FOR NameOblast IN (' + @cols + ')
            ) PivotTable
			'
/* execution of the query */
execute(@query)
