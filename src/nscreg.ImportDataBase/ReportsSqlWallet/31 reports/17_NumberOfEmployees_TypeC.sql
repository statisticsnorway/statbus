/* Table C
    Row header 1 - Regions Top level - Oblasts, Counties
    Row header 2 - Regions Sub-level - Rayons
    Values = Sum of Employees
    Column headers - Activity Categories Top level
 */

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
	DECLARE @InStatusId NVARCHAR(MAX) = $StatusId,
			@InStatUnitType NVARCHAR(MAX) = $StatUnitType,
			@InCurrentYear NVARCHAR(MAX) = YEAR(GETDATE())
END

/* Delete a temporary table #tempTableForPivot if exists */
IF (OBJECT_ID('tempdb..#tempTableForPivot') IS NOT NULL)
BEGIN DROP TABLE #tempTableForPivot END

/* Create a temporary table #tempTableForPivot */
CREATE TABLE #tempTableForPivot
(
	Employees INT NULL,
	ActivityCategoryName NVARCHAR(MAX) NULL,
	NameOblast NVARCHAR(MAX) NULL,
	OblastId NVARCHAR(MAX) NULL,
	NameRayon NVARCHAR(MAX) NULL
)

/* Collect the Activity Categories Tree using CTE */
;WITH ActivityCategoriesHierarchyCTE(Id,ParentId,Name,DesiredLevel) AS(
	SELECT
		Id,
		ParentId,
		Name,
		DesiredLevel
	FROM v_ActivityCategoriesHierarchy
	WHERE DesiredLevel=1
),

/* Regions Top level */
RegionsTotalHierarchyCTE AS(
	SELECT
		Id,
		ParentId,
		Name,
		RegionLevel,
		DesiredLevel /*  */
	FROM v_Regions
  /* If there no Country level, edit the "WHERE" condition below from:
  DesiredLevel = 2
  To:
  DesiredLevel = 1
  */
	WHERE DesiredLevel = 2
),

/* Regions Sub-level */
RegionsHierarchyCTE AS(
	SELECT
		Id,
		ParentId,
		Name,
		RegionLevel,
		DesiredLevel
	FROM v_Regions
  /* If there no Country level, edit the "WHERE" condition below from:
  DesiredLevel = 3
  To:
  DesiredLevel = 2
  */
	WHERE DesiredLevel = 3
),

/* Check the history logs that have StartPeriod less than current year */
StatisticalUnitHistoryCTE AS (
	SELECT
		RegId,
		ParentId,
		AddressId,
		UnitStatusId,
		Discriminator,
		Employees,
		ROW_NUMBER() over (partition by ParentId order by StartPeriod desc) AS RowNumber
	FROM StatisticalUnitHistory
	WHERE DATEPART(YEAR,StartPeriod)<@InCurrentYear
),

/* Result table */
ResultTableCTE AS
(
	SELECT
		IIF(DATEPART(YEAR, su.RegistrationDate) < @InCurrentYear AND DATEPART(YEAR,su.StartPeriod) < @InCurrentYear,su.RegId, asuhCTE.RegId) AS RegId,
		IIF(DATEPART(YEAR, su.RegistrationDate) < @InCurrentYear AND DATEPART(YEAR,su.StartPeriod) < @InCurrentYear,0,1) AS isHistory,
		IIF(DATEPART(YEAR, su.RegistrationDate) < @InCurrentYear AND DATEPART(YEAR,su.StartPeriod) < @InCurrentYear,su.UnitStatusId,asuhCTE.UnitStatusId) AS UnitStatusId,
		IIF(DATEPART(YEAR, su.RegistrationDate) < @InCurrentYear AND DATEPART(YEAR,su.StartPeriod) < @InCurrentYear,su.Discriminator,asuhCTE.Discriminator) AS Discriminator,
		IIF(DATEPART(YEAR, su.RegistrationDate) < @InCurrentYear AND DATEPART(YEAR,su.StartPeriod) < @InCurrentYear,su.Employees,asuhCTE.Employees) AS Employees,
		IIF(DATEPART(YEAR, su.RegistrationDate) < @InCurrentYear AND DATEPART(YEAR,su.StartPeriod) < @InCurrentYear,su.AddressId,asuhCTE.AddressId) AS AddressId,
		IIF(DATEPART(YEAR, su.RegistrationDate) < @InCurrentYear AND DATEPART(YEAR,su.StartPeriod) < @InCurrentYear,a.Activity_Type,ah.Activity_Type) AS ActivityType,
		IIF(DATEPART(YEAR, su.RegistrationDate) < @InCurrentYear AND DATEPART(YEAR,su.StartPeriod) < @InCurrentYear,ac.ParentId,ach.ParentId) AS ActivityCategoryId
	FROM StatisticalUnits AS su
		LEFT JOIN ActivityStatisticalUnits asu ON asu.Unit_Id = su.RegId
		LEFT JOIN Activities a ON a.Id = asu.Activity_Id
		LEFT JOIN ActivityCategoriesHierarchyCTE AS ac ON ac.Id = a.ActivityCategoryId

		LEFT JOIN StatisticalUnitHistoryCTE asuhCTE ON asuhCTE.ParentId = su.RegId and asuhCTE.RowNumber = 1
		LEFT JOIN ActivityStatisticalUnitHistory asuh ON asuh.Unit_Id = asuhCTE.RegId
		LEFT JOIN Activities ah ON ah.Id = asuh.Activity_Id
		LEFT JOIN ActivityCategoriesHierarchyCTE AS ach ON ach.Id = ah.ActivityCategoryId
),
ResultTableCTE2 AS
(
	SELECT
		RegId,
		tr.Name AS NameOblast,
		tr.ParentId as OblastId,
		tr2.Name as NameRayon,
		rt.ActivityCategoryId,
		rt.Employees
	FROM ResultTableCTE AS rt
		LEFT JOIN dbo.Address AS addr ON addr.Address_id = rt.AddressId
		INNER JOIN RegionsTotalHierarchyCTE AS tr ON tr.Id = addr.Region_id
		LEFT JOIN RegionsHierarchyCTE as tr2 ON tr2.Id = addr.Region_id

	WHERE (@InStatUnitType ='All' OR (isHistory = 0 AND  rt.Discriminator = @InStatUnitType) 
				OR (isHistory = 1 AND rt.Discriminator = @InStatUnitType + 'History'))
			AND (@InStatusId = 0 OR rt.UnitStatusId = @InStatusId)
			AND rt.ActivityType = 1
),
/* List of Rayons that not presented at Result table - if there no value it would put 0 */
AddedRayons AS (
	SELECT DISTINCT re.Id AS RayonId
	FROM dbo.Regions AS re
		INNER JOIN ResultTableCTE2 ON ResultTableCTE2.NameRayon = re.Name
),

/* List of Oblasts that not presented at Result table - if there no value it would put 0 */
AddedOblasts AS (
	SELECT DISTINCT OblastId
	FROM ResultTableCTE2
)

/* Fill with data #tempTableForPivot table */
INSERT INTO #tempTableForPivot
/* Oblasts level - 1 column */
SELECT
	SUM(rt.Employees), -- Sum of Employees
	ac.Name AS ActivityCategoryName,
	rt.NameOblast,
	rt.OblastId,
	'' AS NameRayon
FROM dbo.ActivityCategories AS ac
	LEFT JOIN ResultTableCTE2 AS rt ON ac.Id = rt.ActivityCategoryId
WHERE ac.ActivityCategoryLevel = 1 AND rt.OblastId IS NOT NULL
GROUP BY rt.NameOblast, ac.Name, rt.OblastId

UNION ALL
/* Rayons level - 2 column */
SELECT
	SUM(rt.Employees), -- Sum of Employees
	ac.Name AS ActivityCategoryName,
	 '' AS NameOblast,
	rt.OblastId,
	rt.NameRayon
FROM dbo.ActivityCategories AS ac
	LEFT JOIN ResultTableCTE2 AS rt ON ac.Id = rt.ActivityCategoryId
WHERE ac.ActivityCategoryLevel = 1 AND rt.NameRayon IS NOT NULL
GROUP BY rt.NameRayon, ac.Name, rt.OblastId

UNION
/* Oblasts level - 1 column - if there no value, put 0 at the result */
SELECT 0, ac.Name, re.Name, re.Id, ''
FROM dbo.Regions AS re
	CROSS JOIN (SELECT TOP 1 Name FROM dbo.ActivityCategories WHERE ActivityCategoryLevel = 1) AS ac
/* set re.RegionLevel = 1 if there no Country level at Regions tree */
WHERE re.RegionLevel = 2 AND re.Id NOT IN (SELECT OblastId FROM AddedOblasts)

UNION
/* Rayons level - 2 column - if there no value, put 0 at the result */
SELECT 0, ac.Name, '', re.ParentId, re.Name
FROM dbo.Regions AS re
	CROSS JOIN (SELECT TOP 1 Name FROM dbo.ActivityCategories WHERE ActivityCategoryLevel = 1) AS ac
/* set re.RegionLevel = 2 if there no Country level at Regions tree */
WHERE re.RegionLevel = 3 AND re.Id NOT IN (SELECT RayonId FROM AddedRayons)


DECLARE @colsInSelect NVARCHAR(MAX) = STUFF((SELECT distinct ', ISNULL(' + QUOTENAME(Name) + ', 0) AS ' + QUOTENAME(Name)
				FROM dbo.ActivityCategories
				WHERE ActivityCategoryLevel = 1
				FOR XML PATH(''), TYPE
				).value('.', 'NVARCHAR(MAX)')
			,1,1,''),
		/* Total column */
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

/* A query to execute */
DECLARE @query AS NVARCHAR(MAX) = '
SELECT NameOblast, NameRayon, ' + @total + ' as Total, ' + @colsInSelect + ' from
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
/* execution of the query */
execute(@query)
