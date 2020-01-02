BEGIN /* INPUT PARAMETERS from report body */
	DECLARE @InStatUnitType NVARCHAR(MAX) = $StatUnitType,
			@InCurrentYear NVARCHAR(MAX) = YEAR(GETDATE()),
			@InPreviousYear NVARCHAR(MAX) = YEAR(GETDATE()) - 5
END

/* checking if temporary table exists and deleting it if it is true */
IF (OBJECT_ID('tempdb..#tempTableForPivot') IS NOT NULL)
BEGIN DROP TABLE #tempTableForPivot END

/* 
	list of counts of stat units that satisfy necessary requirements 
	by ActivityCategory with level = 1,
	name and Id of oblast(region with level = 2(for kyrgyz database)),
	and name of rayon(region with level = 3),
*/
CREATE TABLE #tempTableForPivot
(
	ActivityCategoryCount INT NULL,
	ActivityCategoryName NVARCHAR(MAX) NULL,
	NameOblast NVARCHAR(MAX) NULL,
	OblastId INT NULL,
	NameRayon NVARCHAR(MAX) NULL
)

/* list of ActivityCategories with level=1, that will be columns in report */
DECLARE @cols NVARCHAR(MAX) = STUFF((SELECT ', ' + QUOTENAME(Name)
						FROM dbo.ActivityCategories
						WHERE ActivityCategoryLevel = 1
						GROUP BY Name 
						ORDER BY Name
                   FOR XML PATH(''), TYPE
                   ).value('.', 'NVARCHAR(MAX)'),1,1,''
);

/* list of columns with sums for using it in select statement */
DECLARE @colSum NVARCHAR(MAX) = STUFF((SELECT ', SUM(ISNULL(' + QUOTENAME(Name)+',0)) as '+ QUOTENAME(Name)
                         FROM dbo.ActivityCategories
                         WHERE ActivityCategoryLevel = 1
                         GROUP BY Name
                         ORDER BY Name
                   FOR XML PATH(''), TYPE
                   ).value('.', 'NVARCHAR(MAX)'),1,1,''
);

/* total sum of all columns */
DECLARE @colsTotal NVARCHAR(MAX) = STUFF((SELECT '+  SUM(ISNULL(' + QUOTENAME(Name)+',0))'
						FROM dbo.ActivityCategories
						WHERE ActivityCategoryLevel = 1
						GROUP BY Name 
						ORDER BY Name
                   FOR XML PATH(''), TYPE
                   ).value('.', 'NVARCHAR(MAX)'),1,1,''
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
/* 
	table where regions linked to their ancestor - rayon(region with level = 3),
	and oblasts(regions with level = 2) linked to themselves 
*/
RegionsHierarchyCTE AS(
	SELECT 
		Id,
		ParentId,
		Name,
		RegionLevel,
		DesiredLevel
	FROM v_Regions
	/* 
		If there no Country level in database, edit WHERE condition below from:
		DesiredLevel = 2 AND RegionLevel = 2 OR DesiredLevel = 3
		To:
		DesiredLevel = 1 AND RegionLevel = 1 OR DesiredLevel = 2
	*/
	WHERE 		
		DesiredLevel = 2 AND RegionLevel = 2
		OR DesiredLevel = 3
),
/* table where regions linked to their oblast(region with level = 2) */
RegionsTotalHierarchyCTE AS(
	SELECT 
		Id,
		ParentId,
		Name,
		RegionLevel,
		DesiredLevel
	FROM v_Regions
	/* 
		If there no Country level in database, edit WHERE condition below from:
		DesiredLevel = 2
		To:
		DesiredLevel = 1
	*/
	WHERE 		
		 DesiredLevel = 2		
),
/* table with needed fields for previous states of stat units that were active in given dateperiod */
StatisticalUnitHistoryCTE AS (
	SELECT
		RegId,
		ParentId,	
		AddressId,
		Discriminator,
		ROW_NUMBER() over (partition by ParentId order by StartPeriod desc) AS RowNumber
	FROM StatisticalUnitHistory
	WHERE DATEPART(YEAR,RegistrationDate)>=@InPreviousYear AND DATEPART(YEAR, RegistrationDate)<@InCurrentYear AND DATEPART(YEAR,StartPeriod)<@InCurrentYear
	
),
/* list with all stat units linked to their primary ActivityCategory that were active in given dateperiod and have required StatUnitType */
ResultTableCTE AS (
		SELECT 
			su.RegId,
			IIF(DATEPART(YEAR, su.RegistrationDate)<@InCurrentYear AND DATEPART(YEAR,su.StartPeriod)<@InCurrentYear,a.ActivityCategoryId,ah.ActivityCategoryId) AS ActivityCategoryId,
			IIF(DATEPART(YEAR, su.RegistrationDate)<@InCurrentYear AND DATEPART(YEAR,su.StartPeriod)<@InCurrentYear,su.Discriminator,suhCTE.Discriminator) AS Discriminator,
			IIF(DATEPART(YEAR, su.RegistrationDate)<@InCurrentYear AND DATEPART(YEAR,su.StartPeriod)<@InCurrentYear,a.Activity_Type,ah.Activity_Type) AS ActivityType,
			IIF(DATEPART(YEAR, su.RegistrationDate)<@InCurrentYear AND DATEPART(YEAR,su.StartPeriod)<@InCurrentYear,su.AddressId,suhCTE.AddressId) AS AddressId,
			IIF(DATEPART(YEAR, su.RegistrationDate)<@InCurrentYear AND DATEPART(YEAR,su.StartPeriod)<@InCurrentYear,0,1) AS isHistory
		FROM StatisticalUnits AS su	
		LEFT JOIN ActivityStatisticalUnits asu ON asu.Unit_Id = su.RegId
		LEFT JOIN Activities a ON a.Id = asu.Activity_Id

		LEFT JOIN StatisticalUnitHistoryCTE suhCTE ON suhCTE.ParentId = su.RegId and suhCTE.RowNumber = 1
		LEFT JOIN ActivityStatisticalUnitHistory asuh ON asuh.Unit_Id = suhCTE.RegId
		LEFT JOIN Activities ah ON ah.Id = asuh.Activity_Id
),
/* list of stat units linked to their rayon(region with level = 3) and oblast(region with level = 2) */
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
	WHERE (@InStatUnitType ='All' OR (isHistory = 0 AND  r.Discriminator = @InStatUnitType) 
				OR (isHistory = 1 AND r.Discriminator = @InStatUnitType + 'History'))
			AND r.ActivityType = 1
),
/* count stat units from ResultTableCTE2 for oblasts and ActivityCategories */
CountOfActivitiesInRegionCTE AS (
	SELECT 
		COUNT(RegId) AS Count,
		OblastId,
		ActivityCategoryId
	FROM ResultTableCTE2
GROUP BY OblastId, ActivityCategoryId
),
/* list of rayons(regions with level = 3) from ResultTableCTE2 */
AddedRayons AS (
	SELECT DISTINCT re.Id AS RayonId 
	FROM dbo.Regions AS re 
		INNER JOIN ResultTableCTE2 rt2 ON rt2.NameRayon = re.Name
),
/* list of oblasts(regions with level = 2) from ResultTableCTE2 */
AddedOblasts AS (
	SELECT DISTINCT rt2.OblastId 
	FROM ResultTableCTE2 rt2
)

/* filling temporary table by all ActivityCategories with level=1, regions and stat units from ResultTableCTE linked to them */ 
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
/* set rt.RegionLevel > 1 if there is no Country level at Regions tree */
WHERE rt.RegionLevel > 2
GROUP BY 
	rt.NameRayon,
	rt.OblastId,
	ac.Name

UNION ALL
/* inserting values for not added oblasts(regions with level = 2) that will be the first headers column */
SELECT 0, ac.Name, re.Name, re.Id, ''
FROM dbo.Regions AS re
	CROSS JOIN (SELECT TOP 1 Name FROM dbo.ActivityCategories WHERE ActivityCategoryLevel = 1) AS ac
/* set re.RegionLevel = 1 if there is no Country level at Regions tree */
WHERE re.RegionLevel = 2 AND re.Id NOT IN (SELECT OblastId FROM AddedOblasts)

UNION ALL
/* inserting values for not added rayons(regions with level = 3) that will be the second headers column */
SELECT 0, ac.Name, '', re.ParentId, re.Name
FROM dbo.Regions AS re
	CROSS JOIN (SELECT TOP 1 Name FROM dbo.ActivityCategories WHERE ActivityCategoryLevel = 1) AS ac
/* set re.RegionLevel = 2 if there is no Country level at Regions tree */
WHERE re.RegionLevel = 3 AND re.Id NOT IN (SELECT RayonId FROM AddedRayons)

/* perform pivot on list of stat units transforming names of regions to columns and counting stat units for ActivityCategories with both levels 1 and 2 */
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