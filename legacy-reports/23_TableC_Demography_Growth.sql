BEGIN /*INPUT PARAMETERS*/
	DECLARE @InStatUnitType NVARCHAR(MAX) = 'LegalUnit',
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
PRINT @colSum
DECLARE @colsTotal NVARCHAR(MAX) = STUFF((SELECT '+  SUM(ISNULL(' + QUOTENAME(Name)+',0))'
						FROM dbo.ActivityCategories
						WHERE ActivityCategoryLevel = 1
						GROUP BY Name 
						ORDER BY Name
                   FOR XML PATH(''), TYPE
                   ).value('.', 'NVARCHAR(MAX)'),1,1,''
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
	WHERE DATEPART(YEAR,StartPeriod)>=@InPreviousYear AND DATEPART(YEAR,StartPeriod)<@InCurrentYear
	
),
ResultTableCTE AS (
		SELECT 
			su.RegId,
			IIF(DATEPART(YEAR,su.RegistrationDate)>=@InPreviousYear AND DATEPART(YEAR, su.RegistrationDate)<@InCurrentYear AND DATEPART(YEAR,su.StartPeriod)>=@InPreviousYear AND DATEPART(YEAR,su.StartPeriod)<@InCurrentYear,a.ActivityCategoryId,ah.ActivityCategoryId) AS ActivityCategoryId,
			IIF(DATEPART(YEAR,su.RegistrationDate)>=@InPreviousYear AND DATEPART(YEAR, su.RegistrationDate)<@InCurrentYear AND DATEPART(YEAR,su.StartPeriod)>=@InPreviousYear AND DATEPART(YEAR,su.StartPeriod)<@InCurrentYear,su.AddressId,suhCTE.AddressId) AS AddressId,
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
		ac.ParentId AS ActivityCategoryId,
		r.AddressId,
		tr.RegionLevel,
		tr.Name AS RegionParentName,
		tr.ParentId AS RegionParentId,
		rthCTE.ParentId AS RegionId,
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
		--COUNT(ActivityCategoryId) AS Count,
		SUM(IIF(DATEPART(YEAR,RegistrationDate) >= 2018 AND UnitStatusId=1,1,0)) - SUM(IIF(LiqDate IS NOT NULL AND DATEPART(YEAR,LiqDate) >= 2018, 1,0)) AS Count,
		RegionId 
	FROM ResultTableCTE2
GROUP BY RegionId
)
INSERT INTO #tempTableForPivot
SELECT
	--IIF(rt.RegionLevel=2,cofir.Count,COUNT(rt.RegId)),
	IIF(rt.RegionLevel=2,cofir.Count, SUM(IIF(DATEPART(YEAR,rt.RegistrationDate) >= 2018 AND rt.UnitStatusId=1,1,0)) - SUM(IIF(rt.LiqDate IS NOT NULL AND DATEPART(YEAR,rt.LiqDate) >= 2018, 1,0))) AS Count,
	rt.RegionParentId,
	ac.Name,	
	IIF(rt.RegionLevel!=2,'  '+rt.RegionParentName,rt.RegionParentName)
FROM ResultTableCTE2 AS rt
	LEFT JOIN dbo.ActivityCategories as ac ON ac.Id = rt.ActivityCategoryId	
	LEFT JOIN CountOfActivitiesInRegionCTE AS cofir ON cofir.RegionId = rt.RegionId
	
	GROUP BY 
		rt.RegionParentName,
		rt.RegionParentId,
		ac.Name,
		cofir.Count,
		rt.RegionLevel


DECLARE @query NVARCHAR(MAX) = N'
SELECT RegionName as Regions,'+ @colsTotal + ' as Total, ' + @colSum
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
