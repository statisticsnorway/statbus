BEGIN /* INPUT PARAMETERS from report body */
	DECLARE @InStatusId NVARCHAR(MAX) = $StatusId,
			@InStatUnitType NVARCHAR(MAX) = $StatUnitType,
			@InCurrentYear NVARCHAR(MAX) = YEAR(GETDATE()),
			@InPreviousYear NVARCHAR(MAX) = YEAR(GETDATE()) - 1
END

/* delete temp table if exists */
IF (OBJECT_ID('tempdb..#tempTableForPivot') IS NOT NULL)
BEGIN DROP TABLE #tempTableForPivot END

/* table with values for every region with levels(2,3) and ActivityCategory */
CREATE TABLE #tempTableForPivot
(
	ActivityCategoryCount INT NULL,
	ActivityCategoryName NVARCHAR(MAX) NULL,
	NameOblast NVARCHAR(MAX) NULL,
	OblastId INT NULL,
	NameRayon NVARCHAR(MAX) NULL
)

/* list of categories with level=1, which will be columns in resulting report */
DECLARE @cols NVARCHAR(MAX) = STUFF((SELECT ', ' + QUOTENAME(Name)
						FROM dbo.ActivityCategories
						WHERE ActivityCategoryLevel = 1
						GROUP BY Name 
						ORDER BY Name
                   FOR XML PATH(''), TYPE
                   ).value('.', 'NVARCHAR(MAX)'),1,2,''
);

/* list of columns with type definition needed to create result table */
DECLARE @colsWithTypeDefinition NVARCHAR(MAX) = STUFF((SELECT ', ' + QUOTENAME(Name) + N'NVARCHAR(MAX)'
						FROM dbo.ActivityCategories
						WHERE ActivityCategoryLevel = 1
						GROUP BY Name 
						ORDER BY Name
                   FOR XML PATH(''), TYPE
                   ).value('.', 'NVARCHAR(MAX)'),1,2,''
);

/* list of sum of columns */
DECLARE @colSum NVARCHAR(MAX) = STUFF((SELECT ', SUM(ISNULL(' + QUOTENAME(Name)+',0)) as '+ QUOTENAME(Name)
                         FROM dbo.ActivityCategories
                         WHERE ActivityCategoryLevel = 1
                         GROUP BY Name
                         ORDER BY Name
                   FOR XML PATH(''), TYPE
                   ).value('.', 'NVARCHAR(MAX)'),1,2,''
);

/* total sum of all columns */
DECLARE @colsTotal NVARCHAR(MAX) = STUFF((SELECT '+  SUM(ISNULL(' + QUOTENAME(Name)+',0))'
						FROM dbo.ActivityCategories
						WHERE ActivityCategoryLevel = 1
						GROUP BY Name 
						ORDER BY Name
                   FOR XML PATH(''), TYPE
                   ).value('.', 'NVARCHAR(MAX)'),1,2,''
);

/* table where ActivityCategories linked to the greatest ancestor */
WITH ActivityCategoriesHierarchyCTE(Id,ParentId,Name,DesiredLevel) AS(
	SELECT 
		Id,
		ParentId,
		Name,
		DesiredLevel
	FROM v_ActivityCategoriesHierarchy 
	WHERE DesiredLevel=1
),
/* table where regions linked to their Rayon(region with level=3) and Oblasts(region with level=2) linked to themselves */
RegionsHierarchyCTE AS(
	SELECT 
		Id,
		ParentId,
		Name,
		RegionLevel,
		DesiredLevel
	FROM v_Regions
	WHERE 		
		DesiredLevel  = 2 AND RegionLevel = 2
		OR DesiredLevel = 3
),
/* table where each region linked to its Oblast(region with level 2) */
RegionsTotalHierarchyCTE AS(
	SELECT 
		Id,
		ParentId,
		Name,
		RegionLevel,
		DesiredLevel
	FROM v_Regions
	WHERE 		
		 DesiredLevel = 2		
),
/* table with needed fields for previous states of stat units that were created and started in given date period */
StatisticalUnitHistoryCTE AS (
	SELECT
		RegId,
		ParentId,	
		AddressId,
		Employees,
		ROW_NUMBER() over (partition by ParentId order by StartPeriod desc) AS RowNumber
	FROM StatisticalUnitHistory
	WHERE DATEPART(YEAR,StartPeriod) BETWEEN @InPreviousYear AND @InCurrentYear - 1
),
/* table with all stat units with given StatUnitType linked to their primary ActivityCategory */
ResultTableCTE AS (
		SELECT 
			su.RegId,
			IIF(DATEPART(YEAR,su.RegistrationDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1 AND DATEPART(YEAR,su.StartPeriod) BETWEEN @InPreviousYear AND @InCurrentYear - 1,a.ActivityCategoryId,ah.ActivityCategoryId) AS ActivityCategoryId,
			IIF(DATEPART(YEAR,su.RegistrationDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1 AND DATEPART(YEAR,su.StartPeriod) BETWEEN @InPreviousYear AND @InCurrentYear - 1,su.AddressId,suhCTE.AddressId) AS AddressId,
			IIF(DATEPART(YEAR,su.RegistrationDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1 AND DATEPART(YEAR,su.StartPeriod) BETWEEN @InPreviousYear AND @InCurrentYear - 1,su.Employees,suhCTE.Employees) AS Employees,
			su.RegistrationDate,
			su.UnitStatusId,
			su.LiqDate
		FROM StatisticalUnits AS su	
		LEFT JOIN ActivityStatisticalUnits asu ON asu.Unit_Id = su.RegId
		LEFT JOIN Activities a ON a.Id = asu.Activity_Id

		LEFT JOIN StatisticalUnitHistoryCTE suhCTE ON suhCTE.ParentId = su.RegId and suhCTE.RowNumber = 1
		LEFT JOIN ActivityStatisticalUnitHistory asuh ON asuh.Unit_Id = suhCTE.RegId
		LEFT JOIN Activities ah ON ah.Id = asuh.Activity_Id

		WHERE (@InStatUnitType ='All' OR su.Discriminator = @InStatUnitType) AND (@InStatusId = 0 OR su.UnitStatusId = @InStatusId) 
				AND a.Activity_Type = 1
),
--table where stat units with the superparent of their ActivityCategory and Rayon and Oblast of their address
ResultTableCTE2 AS (
	SELECT
		r.RegId,
		ac.ParentId AS ActivityCategoryId,
		r.AddressId,
		tr.RegionLevel,
		tr.Name AS NameRayon,
		tr.ParentId AS RayonId,
		rthCTE.ParentId AS OblastId,
		r.RegistrationDate,
		r.UnitStatusId,
		r.LiqDate,
		r.Employees
	FROM ResultTableCTE AS r
	LEFT JOIN ActivityCategoriesHierarchyCTE AS ac ON ac.Id = r.ActivityCategoryId
	LEFT JOIN dbo.Address AS addr ON addr.Address_id = r.AddressId
	INNER JOIN RegionsHierarchyCTE AS tr ON tr.Id = addr.Region_id
	INNER JOIN RegionsTotalHierarchyCTE AS rthCTE ON rthCTE.Id = addr.Region_id
	WHERE DATEPART(YEAR, r.RegistrationDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1 AND Employees IS NOT NULL
),
/* table where the number of employees counted by their oblast and superparent of ActivityCategory */
CountOfActivitiesInRegionCTE AS (
	SELECT 
		SUM(Employees) AS Count,
		rt2.OblastId,
		ActivityCategoryId
	FROM ResultTableCTE2 rt2
	WHERE rt2.ActivityCategoryId IS NOT NULL
GROUP BY rt2.OblastId, ActivityCategoryId
),
AddedRayons AS (
	SELECT DISTINCT re.Id AS RayonId 
	FROM dbo.Regions AS re 
		INNER JOIN ResultTableCTE2 rt2 ON rt2.NameRayon = re.Name
),
AddedOblasts AS (
	SELECT DISTINCT rt2.OblastId 
	FROM ResultTableCTE2 rt2
)

INSERT INTO #tempTableForPivot
/* inserting values for oblasts */
SELECT 
	cofir.Count,
	ac.Name,	
	re.Name AS NameOblast,
	cofir.OblastId AS OblastId,
	'' AS NameRayon
FROM CountOfActivitiesInRegionCTE AS cofir
	INNER JOIN dbo.ActivityCategories as ac ON ac.Id = cofir.ActivityCategoryId	
	INNER JOIN dbo.Regions re ON re.Id = cofir.OblastId

UNION ALL
/* inserting values for rayons */
SELECT
	SUM(rt.Employees) AS COUNT,
	ac.Name,
	'' AS NameOblast,
	rt.OblastId,
	rt.NameRayon
FROM ResultTableCTE2 AS rt
	LEFT JOIN dbo.ActivityCategories as ac ON ac.Id = rt.ActivityCategoryId	
	LEFT JOIN CountOfActivitiesInRegionCTE AS cofir ON cofir.OblastId = rt.OblastId AND cofir.ActivityCategoryId = ac.Id
	WHERE rt.RegionLevel > 2
	GROUP BY 
		rt.NameRayon,
		rt.OblastId,
		ac.Name

UNION ALL

/* inserting values for not added oblasts(regions with level = 2 that will be the first headers column) */
SELECT 0, ac.Name, re.Name, re.Id, ''
FROM dbo.Regions AS re
	CROSS JOIN (SELECT TOP 1 Name FROM dbo.ActivityCategories WHERE ActivityCategoryLevel = 1) AS ac
WHERE re.RegionLevel = 2 AND re.Id NOT IN (SELECT OblastId FROM AddedOblasts)

UNION ALL
/* inserting values for not added rayons(regions with level = 3 that will be the second headers column) */
SELECT 0, ac.Name, '', re.ParentId, re.Name
FROM dbo.Regions AS re
	CROSS JOIN (SELECT TOP 1 Name FROM dbo.ActivityCategories WHERE ActivityCategoryLevel = 1) AS ac
WHERE re.RegionLevel = 3 AND re.Id NOT IN (SELECT RayonId FROM AddedRayons)
		
/* count employees from #tempTableForPivot and perform pivot - transforming names of ActivityCateogries with level=1 to columns */
DECLARE @query NVARCHAR(MAX) = N'
SELECT NameOblast AS Oblast, NameRayon as Rayon,' + @colsTotal + N' as Total, ' + @colSum
      + N' from 
            (
				SELECT 
					ActivityCategoryCount,
					ActivityCategoryName,
					NameOblast,
					OblastId,
					NameRayon 
				FROM #tempTableForPivot				
           ) SourceTable
            PIVOT
            (
                SUM(ActivityCategoryCount)
                FOR ActivityCategoryName IN (' + @cols + N')
            ) PivotTable GROUP by OblastId, NameOblast, NameRayon
			order by OblastId, NameRayon
			';

EXECUTE (@query);