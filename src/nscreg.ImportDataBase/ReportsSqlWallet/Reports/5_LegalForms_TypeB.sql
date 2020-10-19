/* Table B would get one top level region at the total
    And sub-level region items
    Row headers - Legal forms
    Column headers - Sub-level, Rayons level */
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
DECLARE @cols AS NVARCHAR(MAX),
		@selCols AS NVARCHAR(MAX),
		@query AS NVARCHAR(MAX),
		@totalSumCols AS NVARCHAR(MAX),
		@regionLevel AS NVARCHAR(MAX),
		@nameTotalColumn AS NVARCHAR(MAX)

/* Declare Oblast/County/Region - to take only Rayons/Municipalities/Sub-level of Oblast */
SET @nameTotalColumn  = (SELECT TOP 1 Name FROM Regions WHERE Id = @InRegionId)

/* Column - REGIONS, OBLASTS LEVEL */
SET @cols = dbo.GetRayonsColumnNames(@InRegionId);

/* Column - Rayons/Municipalities/Sub-level of Oblast LEVEL */
SET @selCols = dbo.GetRayonsColumnNamesWithNullCheck(@InRegionId);

/* Column - Total count of statistical units by selected region */
SET @totalSumCols = dbo.CountTotalInRayonsAsSql(@InRegionId);

/* Set @regionLevel = 2 if database has no Country level and begins from the Oblasts/Counties/Regions */
SET @regionLevel = 3

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
ResultTable - get the actual state of statistical units where RegistrationDate and StartPeriod less than current year
and then
Join Activity Categories to select statistical units
and then
Count statistical units and using the pivot - transform from regions column to regions row
*/
set @query = '
;WITH StatisticalUnitHistoryCTE AS (
	SELECT
		RegId,
		ParentId,
		AddressId,
		LegalFormId,
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
		IIF(DATEPART(YEAR, su.RegistrationDate)<'+@InCurrentYear+' AND DATEPART(YEAR,su.StartPeriod)<'+@InCurrentYear+',lf.Id, lfh.Id) AS LegalFormId,
		IIF(DATEPART(YEAR, su.RegistrationDate)<'+@InCurrentYear+' AND DATEPART(YEAR,su.StartPeriod)<'+@InCurrentYear+',0,1) AS isHistory
	FROM StatisticalUnits AS su
		LEFT JOIN LegalForms AS lf ON lf.Id = su.LegalFormId
		
		LEFT JOIN StatisticalUnitHistoryCTE asuhCTE ON asuhCTE.ParentId = su.RegId and asuhCTE.RowNumber = 1
		LEFT JOIN LegalForms AS lfh ON lfh.Id = asuhCTE.LegalFormId
    WHERE su.IsDeleted = 0
),
ResultTableCTE2 AS
(
	SELECT
		RegId,
		tr.Name AS NameOblast,
		LegalFormId
	FROM ResultTableCTE AS rt
		LEFT JOIN dbo.Address AS addr ON addr.Address_id = rt.AddressId
		INNER JOIN #tempRegions as tr ON tr.Id = addr.Region_id
	WHERE '+@InStatusId+' = 0 OR rt.UnitStatusId = '+@InStatusId+'
)

SELECT Name, ' + @totalSumCols + ' as [' + @nameTotalColumn+ '], ' + @selCols + ' from
            (
				SELECT
					lf.Name,
					rtCTE.RegId,
					rtCTE.NameOblast
				FROM LegalForms as lf
				LEFT JOIN ResultTableCTE2 as rtCTE ON lf.Id = rtCTE.LegalFormId
           ) SourceTable
            PIVOT
            (
                COUNT(RegId)
                FOR NameOblast IN (' + @cols + ')
            ) PivotTable'
/* execution of the query */
execute(@query)
