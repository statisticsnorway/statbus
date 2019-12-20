BEGIN /* INPUT PARAMETERS */
	DECLARE @InStatUnitType NVARCHAR(MAX) = $StatUnitType,
			@InCurrentYear NVARCHAR(MAX) = YEAR(GETDATE()),
      @InPreviousYear NVARCHAR(MAX) = YEAR(GETDATE()) - 1
END

IF (OBJECT_ID('tempdb..#tempTableForPivot') IS NOT NULL)
BEGIN DROP TABLE #tempTableForPivot END

CREATE TABLE #tempTableForPivot
(
	Count INT NOT NULL DEFAULT 0,
	ActivityCategoryParentId INT NULL,
	ActivityCategoryParentName NVARCHAR(MAX) NULL,
	ActivityCategoryName NVARCHAR(MAX) NULL,
	NameOblast NVARCHAR(MAX) NULL
)

--table where ActivityCategories linked to the greatest ancestor
;WITH ActivityCategoriesTotalHierarchyCTE(Id,ParentId,Name,DesiredLevel) AS(
	SELECT 
		Id,
		ParentId,
		Name,
		DesiredLevel
	FROM v_ActivityCategoriesHierarchy 
	WHERE DesiredLevel=1
),
--table where ActivityCategories linked to their ancestor with level=2
ActivityCategoriesHierarchyCTE(Id,ParentId,Name,DesiredLevel) AS(
	SELECT 
		Id,
		ParentId,
		Name,
		DesiredLevel
	FROM v_ActivityCategoriesHierarchy 
	WHERE DesiredLevel=2
),
--table where regions linked to their oblast and Kyrgyz Republic linked to itself
RegionsHierarchyCTE AS(
	SELECT 
		Id,
		ParentId,
		Name,
		RegionLevel,
		DesiredLevel
	FROM v_Regions
	WHERE DesiredLevel = 2 OR Id = 1 AND DesiredLevel  = 1
),
StatisticalUnitHistoryCTE AS (
	SELECT
		RegId,
		ParentId,	
		AddressId,
		ROW_NUMBER() over (partition by ParentId order by StartPeriod desc) AS RowNumber
	FROM StatisticalUnitHistory
	WHERE DATEPART(YEAR,StartPeriod) BETWEEN @InPreviousYear AND @InCurrentYear - 1
),
--table with all stat units linked to their primary activities' category with given StatUnitType
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
--table where stat units with the superparent of their ActivityCategory and their oblast
ResultTableCTE2 AS
(
	SELECT
		r.RegId,
		ac1.ParentId AS ActivityCategoryId1,
		ac2.ParentId AS ActivityCategoryId2,
		r.AddressId,
		tr.RegionLevel,
		tr.Name AS RegionParentName,
		tr.ParentId AS RegionParentId,
		r.RegistrationDate,
		r.UnitStatusId,
		r.LiqDate
	FROM ResultTableCTE AS r
	LEFT JOIN ActivityCategoriesTotalHierarchyCTE AS ac1 ON ac1.Id = r.ActivityCategoryId
	LEFT JOIN ActivityCategoriesHierarchyCTE AS ac2 ON ac2.Id = r.ActivityCategoryId
	LEFT JOIN dbo.Address AS addr ON addr.Address_id = r.AddressId
	INNER JOIN RegionsHierarchyCTE AS tr ON tr.Id = addr.Region_id	
)

--inserting values for oblast by activity categories
INSERT INTO #tempTableForPivot
SELECT 
	SUM(IIF(DATEPART(YEAR,rt.RegistrationDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1 AND rt.UnitStatusId = 1,1,0)) - SUM(IIF(rt.LiqDate IS NOT NULL AND DATEPART(YEAR,rt.LiqDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1, 1,0)) AS Count,
	ac.Id,
	ac.Name,
	' ',
	rt.RegionParentName as NameOblast
FROM dbo.ActivityCategories as ac
	LEFT JOIN ResultTableCTE2 AS rt ON ac.Id = rt.ActivityCategoryId1
	WHERE ac.ActivityCategoryLevel = 1
	GROUP BY ac.Name, rt.RegionParentName, ac.Id
	
UNION

SELECT 
	SUM(IIF(DATEPART(YEAR,rt.RegistrationDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1 AND rt.UnitStatusId = 1,1,0)) - SUM(IIF(rt.LiqDate IS NOT NULL AND DATEPART(YEAR,rt.LiqDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1, 1,0)) AS Count,
	ac.ParentId,
	' ',
	ac.Name,
	rt.RegionParentName as NameOblast
FROM dbo.ActivityCategories as ac
	LEFT JOIN ResultTableCTE2 AS rt ON ac.Id = rt.ActivityCategoryId2
	WHERE ac.ActivityCategoryLevel = 2
	GROUP BY ac.Name, rt.RegionParentName, ac.ParentId


--replacing NULL values with zeroes for regions and activity categories
DECLARE @colswithISNULL as NVARCHAR(MAX) = STUFF((SELECT distinct ', ISNULL(' + QUOTENAME(Name) + ', 0)  AS ' + QUOTENAME(Name)
				FROM dbo.Regions  WHERE ParentId = 1 AND RegionLevel IN (1,2,3)
				FOR XML PATH(''), TYPE
				).value('.', 'NVARCHAR(MAX)')
			,1,2,'');

--total sum of values for particular activity category
DECLARE @total AS NVARCHAR(MAX) = STUFF((SELECT distinct '+ISNULL(' + QUOTENAME(Name) + ', 0)'
				FROM dbo.Regions  WHERE ParentId = 1 AND RegionLevel IN (1,2,3) OR Id = 1
				FOR XML PATH(''), TYPE
				).value('.', 'NVARCHAR(MAX)')
			,1,1,'')

DECLARE @query AS NVARCHAR(MAX) = '
SELECT ActivityCategoryParentName as ActivityCategoryName, ActivityCategoryName as ActivitySubCategoryName, ' + @total + ' as Total, ' + @colswithISNULL + ' from 
            (
				SELECT 
					Count,
					ActivityCategoryParentId,
					ActivityCategoryParentName,
					ActivityCategoryName,
					NameOblast
				FROM #tempTableForPivot
           ) SourceTable
            PIVOT 
            (
                SUM(Count)
                FOR NameOblast IN (' + dbo.GetNamesRegionsForPivot(1,'FORINPIVOT',1) + ')
            ) PivotTable order by ActivityCategoryParentId, ActivitySubCategoryName'
execute(@query)
