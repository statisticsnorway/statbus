BEGIN /* INPUT PARAMETERS from report body */
	DECLARE @InRegionId INT = $RegionId,
			@InStatUnitType NVARCHAR(MAX) = $StatUnitType,
			@InCurrentYear NVARCHAR(MAX) = YEAR(GETDATE()),
      @InPreviousYear NVARCHAR(MAX) = YEAR(GETDATE()) - 5
END

/* name of given oblast */
DECLARE @nameTotalColumn AS NVARCHAR(MAX) = (SELECT TOP 1 Name FROM dbo.Regions WHERE Id = @InRegionId)

/* delete temp table if exists */
IF (OBJECT_ID('tempdb..#tempTableForPivot') IS NOT NULL)
BEGIN DROP TABLE #tempTableForPivot END

/* table with values for each ActivityCategory with level = 1 in each Rayon(regions with level = 3) in given Oblast(region with level = 2) with Id = @RegionId */
CREATE TABLE #tempTableForPivot
(
	Count INT NOT NULL DEFAULT 0,
	Name NVARCHAR(MAX) NULL,
	NameOblast NVARCHAR(MAX) NULL
)
--table where ActivityCategories linked to the greatest ancestor
;WITH ActivityCategoriesHierarchyCTE(Id,ParentId,Name,DesiredLevel) AS(
	SELECT 
		Id,
		ParentId,
		Name,
		DesiredLevel
	FROM v_ActivityCategoriesHierarchy 
	WHERE DesiredLevel=1
),
/* table where regions linked to their Rayon(region with level = 3) and oblast(region with level = 2) with Id = @RegionId linked to itself */
RegionsHierarchyCTE AS(
	SELECT 
		Id,
		ParentId,
		Name,
		RegionLevel,
		DesiredLevel
	FROM v_Regions
	WHERE DesiredLevel = 3 OR Id = @InRegionId AND DesiredLevel  = 2
),
/* table with needed fields for previous states of stat units that were created and started in given date period */
StatisticalUnitHistoryCTE AS (
	SELECT
		RegId,
		ParentId,	
		AddressId,
		ROW_NUMBER() over (partition by ParentId order by StartPeriod desc) AS RowNumber
	FROM StatisticalUnitHistory
	WHERE DATEPART(YEAR,StartPeriod) BETWEEN @InPreviousYear AND @InCurrentYear - 1
),
/* table with all stat units with given StatUnitType linked to their primary ActivityCategory */
ResultTableCTE AS
(
	SELECT
		su.RegId as RegId,
		IIF(DATEPART(YEAR,su.RegistrationDate)>=@InPreviousYear AND DATEPART(YEAR, su.RegistrationDate)<@InCurrentYear AND DATEPART(YEAR,su.StartPeriod)>=@InPreviousYear AND DATEPART(YEAR,su.StartPeriod)<@InCurrentYear,a.ActivityCategoryId,ah.ActivityCategoryId) AS ActivityCategoryId,
		IIF(DATEPART(YEAR,su.RegistrationDate)>=@InPreviousYear AND DATEPART(YEAR, su.RegistrationDate)<@InCurrentYear AND DATEPART(YEAR,su.StartPeriod)>=@InPreviousYear AND DATEPART(YEAR,su.StartPeriod)<@InCurrentYear,su.AddressId,suhCTE.AddressId) AS AddressId,
		su.RegistrationDate,
		su.UnitStatusId,
		su.LiqDate
	FROM dbo.StatisticalUnits AS su	
		LEFT JOIN dbo.ActivityStatisticalUnits asu ON asu.Unit_Id = su.RegId
		LEFT JOIN dbo.Activities a ON a.Id = asu.Activity_Id

		LEFT JOIN StatisticalUnitHistoryCTE suhCTE ON suhCTE.ParentId = su.RegId and suhCTE.RowNumber = 1
		LEFT JOIN dbo.ActivityStatisticalUnitHistory asuh ON asuh.Unit_Id = suhCTE.RegId
		LEFT JOIN dbo.Activities ah ON ah.Id = asuh.Activity_Id
	WHERE (@InStatUnitType ='All' OR su.Discriminator = @InStatUnitType) AND a.Activity_Type = 1
),
/* table where stat units with the superparent of their ActivityCategory and their rayon or oblast(if address cannot be linked to rayon) */
ResultTableCTE2 AS
(
	SELECT
		r.RegId,
		ac.ParentId AS ActivityCategoryId,
		r.AddressId,
		tr.RegionLevel,
		tr.Name AS RegionParentName,
		tr.ParentId AS RegionParentId,
		r.RegistrationDate,
		r.UnitStatusId,
		r.LiqDate
	FROM ResultTableCTE AS r
	LEFT JOIN ActivityCategoriesHierarchyCTE AS ac ON ac.Id = r.ActivityCategoryId
	LEFT JOIN dbo.Address AS addr ON addr.Address_id = r.AddressId
	INNER JOIN RegionsHierarchyCTE AS tr ON tr.Id = addr.Region_id
)

/* inserting values for rayon or oblast(if address cannot be linked to rayon) by activity categories */
INSERT INTO #tempTableForPivot
SELECT 
	SUM(IIF(DATEPART(YEAR,rt.RegistrationDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1 AND rt.UnitStatusId = 1,1,0)) - SUM(IIF(rt.LiqDate IS NOT NULL AND DATEPART(YEAR,rt.LiqDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1, 1,0)) AS Count,
	ac.Name,
	rt.RegionParentName as NameOblast
FROM dbo.ActivityCategories as ac
	LEFT JOIN ResultTableCTE2 AS rt ON ac.Id = rt.ActivityCategoryId
	WHERE ac.ActivityCategoryLevel = 1
	GROUP BY ac.Name, rt.RegionParentName

/* 
	declaration list of columns(regions with level = 3(direct children of region with Id = @RegionId)) 
	for select with replacing NULL values with zeroes
*/
DECLARE @colswithISNULL as NVARCHAR(MAX) = STUFF((SELECT distinct ', ISNULL(' + QUOTENAME(Name) + ', 0)  AS ' + QUOTENAME(Name)
				FROM dbo.Regions  WHERE ParentId = @InRegionId AND RegionLevel = 3
				FOR XML PATH(''), TYPE
				).value('.', 'NVARCHAR(MAX)')
			,1,2,'');

/* declaring total sum of values for particular activity category for select */
DECLARE @total AS NVARCHAR(MAX) = STUFF((SELECT distinct '+ISNULL(' + QUOTENAME(Name) + ', 0)'
				FROM dbo.Regions  WHERE ParentId = @InRegionId AND RegionLevel IN (1,2,3) OR Id = @InRegionId
				FOR XML PATH(''), TYPE
				).value('.', 'NVARCHAR(MAX)')
			,1,1,'')
		
/* count stat units from #tempTableForPivot and perform pivot - transforming names of regions with level=3 to columns */
DECLARE @query AS NVARCHAR(MAX) = '
SELECT Name, ' + @colswithISNULL + ', ' + @total + ' as ' + QUOTENAME(@nameTotalColumn) + ' FROM 
            (
				SELECT 
					Count,
					Name,
					NameOblast
				FROM #tempTableForPivot
           ) SourceTable
            PIVOT 
            (
                SUM(Count)
                FOR NameOblast IN (' + dbo.GetNamesRegionsForPivot(@InRegionId,'FORINPIVOT',1) + ')
            ) PivotTable order by Name'
execute(@query)
