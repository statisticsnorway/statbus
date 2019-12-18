BEGIN /*INPUT PARAMETERS*/
	DECLARE @InStatUnitType NVARCHAR(MAX) = $StatUnitType,
			@InCurrentYear NVARCHAR(MAX) = YEAR(GETDATE()),
			@InPreviousYear NVARCHAR(MAX) = YEAR(GETDATE()) - 1
END

IF (OBJECT_ID('tempdb..#tempTableForPivot') IS NOT NULL)
BEGIN DROP TABLE #tempTableForPivot END

CREATE TABLE #tempTableForPivot
(
	ActivityCategoryCount INT NULL,
	ActivityCategoryName NVARCHAR(MAX) NULL,
	NameOblast NVARCHAR(MAX) NULL,
	OblastId INT NULL,
	NameRayon NVARCHAR(MAX) NULL
)

DECLARE @cols NVARCHAR(MAX) = STUFF((SELECT ', ' + QUOTENAME(Name)
						FROM dbo.ActivityCategories
						WHERE ActivityCategoryLevel = 1
						GROUP BY Name 
						ORDER BY Name
                   FOR XML PATH(''), TYPE
                   ).value('.', 'NVARCHAR(MAX)'),1,1,''
);

DECLARE @colSum NVARCHAR(MAX) = STUFF((SELECT ', SUM(ISNULL(' + QUOTENAME(Name)+',0)) as '+ QUOTENAME(Name)
                         FROM dbo.ActivityCategories
                         WHERE ActivityCategoryLevel = 1
                         GROUP BY Name
                         ORDER BY Name
                   FOR XML PATH(''), TYPE
                   ).value('.', 'NVARCHAR(MAX)'),1,1,''
);

DECLARE @colsTotal NVARCHAR(MAX) = STUFF((SELECT '+  SUM(ISNULL(' + QUOTENAME(Name)+',0))'
						FROM dbo.ActivityCategories
						WHERE ActivityCategoryLevel = 1
						GROUP BY Name 
						ORDER BY Name
                   FOR XML PATH(''), TYPE
                   ).value('.', 'NVARCHAR(MAX)'),1,1,''
);

WITH ActivityCategoriesHierarchyCTE(Id,ParentId,Name,DesiredLevel) AS(
	SELECT 
		Id,
		ParentId,
		Name,
		DesiredLevel
	FROM v_ActivityCategoriesHierarchy 
	WHERE DesiredLevel=1
),
RegionsHierarchyCTE AS(
	SELECT 
		Id,
		ParentId,
		Name,
		RegionLevel,
		DesiredLevel
	FROM v_Regions
	WHERE 		
		DesiredLevel  = 2 AND RegionLevel =2
		OR DesiredLevel  = 3
),
RegionsTotalHierarchyCTE AS(
	SELECT 
		Id,
		ParentId,
		Name,
		RegionLevel,
		DesiredLevel
	FROM v_Regions
	WHERE 		
		 DesiredLevel  = 2		
),
StatisticalUnitHistoryCTE AS (
	SELECT
		RegId,
		ParentId,	
		AddressId,
		ROW_NUMBER() over (partition by ParentId order by StartPeriod desc) AS RowNumber
	FROM StatisticalUnitHistory
	WHERE DATEPART(YEAR,RegistrationDate)>=@InPreviousYear AND DATEPART(YEAR, RegistrationDate)<@InCurrentYear AND DATEPART(YEAR,StartPeriod)<@InCurrentYear
	
),
ResultTableCTE AS (
		SELECT 
			su.RegId,
			IIF(DATEPART(YEAR, su.RegistrationDate)<@InCurrentYear AND DATEPART(YEAR, su.RegistrationDate)>=@InPreviousYear AND DATEPART(YEAR,su.StartPeriod)<@InCurrentYear,a.ActivityCategoryId,ah.ActivityCategoryId) AS ActivityCategoryId,
			IIF(DATEPART(YEAR, su.RegistrationDate)<@InCurrentYear AND DATEPART(YEAR, su.RegistrationDate)>=@InPreviousYear AND DATEPART(YEAR,su.StartPeriod)<@InCurrentYear,su.AddressId,suhCTE.AddressId) AS AddressId
		FROM StatisticalUnits AS su	
		LEFT JOIN ActivityStatisticalUnits asu ON asu.Unit_Id = su.RegId
		LEFT JOIN Activities a ON a.Id = asu.Activity_Id

		LEFT JOIN StatisticalUnitHistoryCTE suhCTE ON suhCTE.ParentId = su.RegId and suhCTE.RowNumber = 1
		LEFT JOIN ActivityStatisticalUnitHistory asuh ON asuh.Unit_Id = suhCTE.RegId
		LEFT JOIN Activities ah ON ah.Id = asuh.Activity_Id

	WHERE (@InStatUnitType ='All' OR su.Discriminator = @InStatUnitType) AND a.Activity_Type = 1
),
ResultTableCTE2 AS (
	SELECT
		r.RegId,
		ac.ParentId AS ActivityCategoryId,
		r.AddressId,
		tr.RegionLevel,
		tr.Name AS NameRayon,
		tr.ParentId AS RayonId,
		rthCTE.ParentId AS OblastId
	FROM ResultTableCTE AS r
	LEFT JOIN ActivityCategoriesHierarchyCTE AS ac ON ac.Id = r.ActivityCategoryId
	LEFT JOIN dbo.Address AS addr ON addr.Address_id = r.AddressId
	INNER JOIN RegionsHierarchyCTE AS tr ON tr.Id = addr.Region_id
	INNER JOIN RegionsTotalHierarchyCTE AS rthCTE ON rthCTE.Id = addr.Region_id
),
CountOfActivitiesInRegionCTE AS (
	SELECT 
		COUNT(RegId) AS Count,
		OblastId,
		ActivityCategoryId
	FROM ResultTableCTE2
GROUP BY OblastId, ActivityCategoryId
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
	COUNT(rt.RegId),
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


/* count stat units from #tempTableForPivot and perform pivot - transforming names of ActivityCateogries with level=1 to columns */
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