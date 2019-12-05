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
	RegionParentId INT NULL,
	ActivityCategoryName NVARCHAR(MAX) NULL,
	RegionName NVARCHAR(MAX) NULL
)

DECLARE @cols NVARCHAR(MAX) = STUFF((SELECT ', ' + QUOTENAME(Name)
						FROM dbo.ActivityCategories
						WHERE ActivityCategoryLevel = 1
						GROUP BY Name 
						ORDER BY Name
                   FOR XML PATH(''), TYPE
                   ).value('.', 'NVARCHAR(MAX)'),1,2,''
);

DECLARE @colsWithoutBrackets NVARCHAR(MAX) = STUFF((SELECT ', ' + QUOTENAME(Name) + N'NVARCHAR(MAX)'
						FROM dbo.ActivityCategories
						WHERE ActivityCategoryLevel = 1
						GROUP BY Name 
						ORDER BY Name
                   FOR XML PATH(''), TYPE
                   ).value('.', 'NVARCHAR(MAX)'),1,2,''
);

DECLARE @colSum NVARCHAR(MAX) = STUFF((SELECT ', SUM(ISNULL(' + QUOTENAME(Name)+',0)) as '+ QUOTENAME(Name)
                         FROM dbo.ActivityCategories
                         WHERE ActivityCategoryLevel = 1
                         GROUP BY Name
                         ORDER BY Name
                   FOR XML PATH(''), TYPE
                   ).value('.', 'NVARCHAR(MAX)'),1,2,''
);
PRINT @colSum
DECLARE @colsTotal NVARCHAR(MAX) = STUFF((SELECT '+  SUM(ISNULL(' + QUOTENAME(Name)+',0))'
						FROM dbo.ActivityCategories
						WHERE ActivityCategoryLevel = 1
						GROUP BY Name 
						ORDER BY Name
                   FOR XML PATH(''), TYPE
                   ).value('.', 'NVARCHAR(MAX)'),1,2,''
);
PRINT @colsTotal
;WITH ActivityCategoriesHierarchyCTE(Id,ParentId,Name,DesiredLevel) AS(
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
		DesiredLevel  = 2 AND RegionLevel = 2
		OR DesiredLevel = 3
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
		 DesiredLevel = 2		
),
StatisticalUnitHistoryCTE AS (
	SELECT
		RegId,
		ParentId,	
		AddressId,
		ROW_NUMBER() over (partition by ParentId order by StartPeriod desc) AS RowNumber
	FROM StatisticalUnitHistory
	WHERE DATEPART(YEAR,StartPeriod) = @InPreviousYear
	
),
ResultTableCTE AS (
		SELECT 
			su.RegId,
			IIF(DATEPART(YEAR,su.RegistrationDate)=@InPreviousYear AND DATEPART(YEAR,su.StartPeriod)=@InPreviousYear,a.ActivityCategoryId,ah.ActivityCategoryId) AS ActivityCategoryId,
			IIF(DATEPART(YEAR,su.RegistrationDate)=@InPreviousYear AND DATEPART(YEAR,su.StartPeriod)=@InPreviousYear,su.AddressId,suhCTE.AddressId) AS AddressId,
			su.RegistrationDate,
			su.UnitStatusId,
			su.LiqDate
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
		ac.ParentId AS ActivityCategoryId, --supercategory
		r.AddressId,
		tr.RegionLevel,
		tr.Name AS RegionParentName,   --rayon if desired level = 3 or oblast if reg level = 2
		tr.ParentId AS RegionParentId, --rayon if desired level = 3 or oblast if reg level = 2
		rthCTE.ParentId AS RegionId,   --oblast
		r.RegistrationDate,
		r.UnitStatusId,
		r.LiqDate
	FROM ResultTableCTE AS r
	LEFT JOIN ActivityCategoriesHierarchyCTE AS ac ON ac.Id = r.ActivityCategoryId
	LEFT JOIN dbo.Address AS addr ON addr.Address_id = r.AddressId
	INNER JOIN RegionsHierarchyCTE AS tr ON tr.Id = addr.Region_id
	INNER JOIN RegionsTotalHierarchyCTE AS rthCTE ON rthCTE.Id = addr.Region_id
),
CountOfActivitiesInRegionCTE AS (
	SELECT 
		SUM(IIF(DATEPART(YEAR,RegistrationDate) >= 2018 AND UnitStatusId=1,1,0)) - SUM(IIF(LiqDate IS NOT NULL AND DATEPART(YEAR,LiqDate) >= 2018, 1,0)) AS Count,
		RegionId,
		ActivityCategoryId
	FROM ResultTableCTE2
	WHERE ResultTableCTE2.ActivityCategoryId IS NOT NULL
GROUP BY RegionId, ActivityCategoryId
)
,
RegionsToAdd AS (
	SELECT DISTINCT
		ParentId AS RegionParentId,
		Name AS RegionName
	FROM RegionsHierarchyCTE
 
),
RegionsToAddFiltered AS (
	SELECT
		rta.RegionParentId,
		rta.RegionName
	FROM RegionsToAdd AS rta LEFT JOIN	ResultTableCTE2 AS rtcte2 ON rta.RegionParentId = rtcte2.RegionParentId
	WHERE rtcte2.RegionParentId IS NULL
	UNION
	SELECT
		rta.RegionParentId,
		rta.RegionName
	FROM RegionsToAdd AS rta LEFT JOIN	ResultTableCTE2 AS rtcte2 ON rta.RegionParentId = rtcte2.RegionParentId
	WHERE rtcte2.RegionParentId IS NULL
	
),
SuperActivityCategories AS (
	SELECT Name AS ActivityCategoryName
	FROM dbo.ActivityCategories
	WHERE ActivityCategoryLevel = 1
)

INSERT INTO #tempTableForPivot
SELECT

	cofir.Count,
	cofir.RegionId,
	ac.Name,	
	dbo.Regions.Name AS RegionName
FROM CountOfActivitiesInRegionCTE AS cofir
	INNER JOIN dbo.ActivityCategories as ac ON ac.Id = cofir.ActivityCategoryId	
	INNER JOIN dbo.Regions ON Regions.Id = cofir.RegionId

UNION ALL

SELECT
	SUM(IIF(DATEPART(YEAR,rt.RegistrationDate) >= 2018 AND rt.UnitStatusId=1,1,0)) - SUM(IIF(rt.LiqDate IS NOT NULL AND DATEPART(YEAR,rt.LiqDate) >= 2018, 1,0)) AS COUNT,
	rt.RegionParentId,
	ac.Name,	
	rt.RegionParentName
FROM ResultTableCTE2 AS rt
	LEFT JOIN dbo.ActivityCategories as ac ON ac.Id = rt.ActivityCategoryId	
	LEFT JOIN CountOfActivitiesInRegionCTE AS cofir ON cofir.RegionId = rt.RegionId AND cofir.ActivityCategoryId = ac.Id
	WHERE rt.RegionLevel > 2
	GROUP BY 
		rt.RegionParentName,
		rt.RegionParentId,
		ac.Name,
		rt.RegionLevel

UNION ALL

SELECT
	0 AS ActivityCategoryCount,
	RegionParentId,
	ActivityCategoryName,
	RegionName
FROM RegionsToAddFiltered
	CROSS JOIN SuperActivityCategories

IF OBJECT_ID ('dbo.tempResultTable') IS NOT NULL
   BEGIN DROP TABLE dbo.tempResultTable END

-- Oblast and Rayon are valid names for regions with level=2 and level=3 in KG
DECLARE @queryTable NVARCHAR(MAX) = N'
CREATE TABLE dbo.tempResultTable (
	Oblast NVARCHAR(MAX),
	Rayon NVARCHAR(MAX),
	Total INT,
	' + @colsWithoutBrackets + N'	
)
'
PRINT(@queryTable)
EXECUTE (@queryTable);
		
DECLARE @query NVARCHAR(MAX) = N'
INSERT INTO dbo.tempResultTable
SELECT '''' as Oblast, RegionName as Rayon,' + @colsTotal + N' as Total, ' + @colSum
      + N' from 
            (
				select ActivityCategoryCount,ActivityCategoryName,RegionName,RegionParentId from #tempTableForPivot				
           ) SourceTable
            PIVOT
            (
                SUM(ActivityCategoryCount)
                FOR ActivityCategoryName IN (' + @cols + N')
            ) PivotTable GROUP by RegionName,RegionParentId
			order by RegionParentId
			';


			PRINT @query
EXECUTE (@query);

UPDATE dbo.tempResultTable
SET Oblast = Rayon, Rayon = ''
WHERE Rayon IN (SELECT DISTINCT Name FROM dbo.Regions WHERE RegionLevel = 2)
;

SELECT * FROM dbo.tempResultTable;

IF OBJECT_ID ('dbo.tempResultTable') IS NOT NULL
   BEGIN DROP TABLE dbo.tempResultTable END
