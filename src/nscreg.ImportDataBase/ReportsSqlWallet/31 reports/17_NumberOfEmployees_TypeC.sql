BEGIN /* INPUT PARAMETERS */
	DECLARE @InStatusId NVARCHAR(MAX) = $StatusId,
			@InStatUnitType NVARCHAR(MAX) = $StatUnitType,
			@InCurrentYear NVARCHAR(MAX) = YEAR(GETDATE())
END

IF (OBJECT_ID('tempdb..#tempTableForPivot') IS NOT NULL)
BEGIN DROP TABLE #tempTableForPivot END

CREATE TABLE #tempTableForPivot
(
	Employees INT NULL,
	ActivityCategoryName NVARCHAR(MAX) NULL,
	NameOblast NVARCHAR(MAX) NULL,
	OblastId NVARCHAR(MAX) NULL,
	NameRayon NVARCHAR(MAX) NULL
)

;WITH ActivityCategoriesHierarchyCTE(Id,ParentId,Name,DesiredLevel) AS(
	SELECT 
		Id,
		ParentId,
		Name,
		DesiredLevel
	FROM v_ActivityCategoriesHierarchy 
	WHERE DesiredLevel=1
),
RegionsTotalHierarchyCTE AS(
	SELECT 
		Id,
		ParentId,
		Name,
		RegionLevel,
		DesiredLevel
	FROM v_Regions
	WHERE DesiredLevel = 2 OR Id = 1 AND DesiredLevel  = 1
),
RegionsHierarchyCTE AS(
	SELECT 
		Id,
		ParentId,
		Name,
		RegionLevel,
		DesiredLevel
	FROM v_Regions
	WHERE DesiredLevel = 3
),
StatisticalUnitHistoryCTE AS (
	SELECT
		RegId,
		ParentId,	
		AddressId,
		Employees,
		ROW_NUMBER() over (partition by ParentId order by StartPeriod desc) AS RowNumber
	FROM StatisticalUnitHistory
	WHERE DATEPART(YEAR,StartPeriod)<@InCurrentYear
),
ResultTableCTE AS
(
	SELECT
		su.RegId as RegId,
		IIF(DATEPART(YEAR, su.RegistrationDate)<@InCurrentYear AND DATEPART(YEAR,su.StartPeriod)<@InCurrentYear,ac.Name,ach.Name) AS Name,
		IIF(DATEPART(YEAR, su.RegistrationDate)<@InCurrentYear AND DATEPART(YEAR,su.StartPeriod)<@InCurrentYear,tr.Name,trh.Name) AS NameOblast,
		IIF(DATEPART(YEAR, su.RegistrationDate)<@InCurrentYear AND DATEPART(YEAR,su.StartPeriod)<@InCurrentYear,tr.ParentId,trh.ParentId) AS OblastId,
		IIF(DATEPART(YEAR, su.RegistrationDate)<@InCurrentYear AND DATEPART(YEAR,su.StartPeriod)<@InCurrentYear,re.Name,reh.Name) AS NameRayon,
		IIF(DATEPART(YEAR, su.RegistrationDate)<@InCurrentYear AND DATEPART(YEAR,su.StartPeriod)<@InCurrentYear,su.Employees,asuhCTE.Employees) AS Employees,
		IIF(DATEPART(YEAR, su.RegistrationDate)<@InCurrentYear AND DATEPART(YEAR,su.StartPeriod)<@InCurrentYear,ac.ParentId,ach.ParentId) AS ActivityCategoryId
	FROM StatisticalUnits AS su	
		LEFT JOIN ActivityStatisticalUnits asu ON asu.Unit_Id = su.RegId
		LEFT JOIN Activities a ON a.Id = asu.Activity_Id
		LEFT JOIN ActivityCategoriesHierarchyCTE AS ac ON ac.Id = a.ActivityCategoryId
		LEFT JOIN dbo.Address AS addr ON addr.Address_id = su.AddressId
		INNER JOIN RegionsTotalHierarchyCTE AS tr ON tr.Id = addr.Region_id
		LEFT JOIN RegionsHierarchyCTE AS re ON re.Id = addr.Region_id

		LEFT JOIN StatisticalUnitHistoryCTE asuhCTE ON asuhCTE.ParentId = su.RegId and asuhCTE.RowNumber = 1
		LEFT JOIN ActivityStatisticalUnitHistory asuh ON asuh.Unit_Id = asuhCTE.RegId
		LEFT JOIN Activities ah ON ah.Id = asuh.Activity_Id
		LEFT JOIN ActivityCategoriesHierarchyCTE AS ach ON ach.Id = ah.ActivityCategoryId
		LEFT JOIN dbo.Address AS addrh ON addrh.Address_id = asuhCTE.AddressId
		LEFT JOIN RegionsTotalHierarchyCTE AS trh ON trh.Id = addrh.Region_id
		LEFT JOIN RegionsHierarchyCTE AS reh ON reh.Id = addrh.Region_id
	WHERE (@InStatUnitType ='All' OR su.Discriminator = @InStatUnitType) AND (@InStatusId = 0 OR su.UnitStatusId = @InStatusId)
			AND a.Activity_Type = 1
),
AddedRayons AS (
	SELECT DISTINCT re.Id AS RayonId 
	FROM dbo.Regions AS re 
		INNER JOIN ResultTableCTE ON ResultTableCTE.NameRayon = re.Name
),
AddedOblasts AS (
	SELECT DISTINCT OblastId 
	FROM ResultTableCTE
)

INSERT INTO #tempTableForPivot
SELECT 
	SUM(rt.Employees),
	ac.Name AS ActivityCategoryName,
	rt.NameOblast,
	rt.OblastId,
	'' AS NameRayon
FROM dbo.ActivityCategories AS ac
	LEFT JOIN ResultTableCTE AS rt ON ac.Id = rt.ActivityCategoryId
WHERE ac.ActivityCategoryLevel = 1 AND rt.OblastId IS NOT NULL
GROUP BY rt.NameOblast, ac.Name, rt.OblastId
UNION ALL
SELECT
	SUM(rt.Employees),
	ac.Name AS ActivityCategoryName,
	 '' AS NameOblast,
	rt.OblastId,
	rt.NameRayon
FROM dbo.ActivityCategories AS ac
	LEFT JOIN ResultTableCTE AS rt ON ac.Id = rt.ActivityCategoryId
WHERE ac.ActivityCategoryLevel = 1 AND rt.NameRayon IS NOT NULL
GROUP BY rt.NameRayon, ac.Name, rt.OblastId

UNION 

SELECT 0, ac.Name, re.Name, re.Id, ''
FROM dbo.Regions AS re
	CROSS JOIN (SELECT TOP 1 Name FROM dbo.ActivityCategories WHERE ActivityCategoryLevel = 1) AS ac
WHERE re.RegionLevel = 2 AND re.Id NOT IN (SELECT OblastId FROM AddedOblasts)

UNION

SELECT 0, ac.Name, '', re.ParentId, re.Name
FROM dbo.Regions AS re
	CROSS JOIN (SELECT TOP 1 Name FROM dbo.ActivityCategories WHERE ActivityCategoryLevel = 1) AS ac
WHERE re.RegionLevel = 3 AND re.Id NOT IN (SELECT RayonId FROM AddedRayons)


DECLARE @colsInSelect NVARCHAR(MAX) = STUFF((SELECT distinct ', ISNULL(' + QUOTENAME(Name) + ', 0) AS ' + QUOTENAME(Name)
				FROM dbo.ActivityCategories
				WHERE ActivityCategoryLevel = 1
				FOR XML PATH(''), TYPE
				).value('.', 'NVARCHAR(MAX)') 
			,1,1,''),
		@total NVARCHAR(MAX) = STUFF((SELECT distinct '+ ISNULL(' + QUOTENAME(Name) + ', 0)'
				FROM dbo.ActivityCategories
				WHERE ActivityCategoryLevel = 1
				FOR XML PATH(''), TYPE
				).value('.', 'NVARCHAR(MAX)')
				,1,1,''),
		@cols NVARCHAR(MAX) = STUFF((SELECT ', ' + QUOTENAME(Name)
					FROM dbo.ActivityCategories
					WHERE ActivityCategoryLevel = 1
					GROUP BY Name 
					ORDER BY Name
                FOR XML PATH(''), TYPE
                ).value('.', 'NVARCHAR(MAX)'),1,2,''
);
DECLARE @query AS NVARCHAR(MAX) = '
SELECT NameOblast, NameRayon, ' + @colsInSelect + ', ' + @total + ' as Total from 
            (
				SELECT 
					Employees,
					ActivityCategoryName,
					NameOblast,
					OblastId,
					NameRayon
				FROM #tempTableForPivot
           ) SourceTable
            PIVOT 
            (
                SUM(Employees)
                FOR ActivityCategoryName IN (' + @cols + ')
            ) PivotTable order by OblastId, NameRayon'
execute(@query)