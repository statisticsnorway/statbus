BEGIN /* INPUT PARAMETERS */
	DECLARE @InStatusId NVARCHAR(MAX) = $StatusId,
			@InStatUnitType NVARCHAR(MAX) = $StatUnitType,
			@InPersonTypeId NVARCHAR(MAX) = $PersonTypeId,
			@InCurrentYear NVARCHAR(MAX) = YEAR(GETDATE())
END

IF (OBJECT_ID('tempdb..#tempTableForPivot') IS NOT NULL)
BEGIN DROP TABLE #tempTableForPivot END

CREATE TABLE #tempTableForPivot
(
	Count NVARCHAR(MAX) NULL,
	Sex TINYINT NULL,
	ActivityCategoryName NVARCHAR(MAX) NULL,
	OblastId INT NULL,
	RayonName NVARCHAR(MAX) NULL,
	OblastName NVARCHAR(MAX) NULL
)

--table where ActivityCategories linked to their greatest ancestor
;WITH ActivityCategoriesHierarchyCTE(Id,ParentId,Name,DesiredLevel) AS(
	SELECT 
		Id,
		ParentId,
		Name,
		DesiredLevel
	FROM v_ActivityCategoriesHierarchy 
	WHERE DesiredLevel=1
),
--table where regions linked to their oblast and region with Id=1
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
--table where regions linked to their rayon(region with level=3)
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
		ROW_NUMBER() over (partition by ParentId order by StartPeriod desc) AS RowNumber
	FROM StatisticalUnitHistory
	WHERE DATEPART(YEAR,StartPeriod) < @InCurrentYear
),
--table with all stat units linked to their primary activities' category with given StatUnitType
ResultTableCTE AS
(
	SELECT
		IIF(DATEPART(YEAR,su.RegistrationDate) < @InCurrentYear AND DATEPART(YEAR,su.StartPeriod) < @InCurrentYear,su.RegId,suhCTE.RegId) AS RegId,
		IIF(DATEPART(YEAR,su.RegistrationDate) < @InCurrentYear AND DATEPART(YEAR,su.StartPeriod) < @InCurrentYear,a.ActivityCategoryId,ah.ActivityCategoryId) AS ActivityCategoryId,
		IIF(DATEPART(YEAR,su.RegistrationDate) < @InCurrentYear AND DATEPART(YEAR,su.StartPeriod) < @InCurrentYear,su.AddressId,suhCTE.AddressId) AS AddressId,
		IIF(DATEPART(YEAR,su.RegistrationDate) < @InCurrentYear AND DATEPART(YEAR,su.StartPeriod) < @InCurrentYear,psu.Person_Id, psuh.Person_Id) AS PersonId,
		su.RegistrationDate,
		su.UnitStatusId,
		su.LiqDate
	FROM dbo.StatisticalUnits AS su	
		LEFT JOIN dbo.ActivityStatisticalUnits asu ON asu.Unit_Id = su.RegId
		LEFT JOIN dbo.Activities a ON a.Id = asu.Activity_Id
		LEFT JOIN dbo.PersonStatisticalUnits psu ON psu.Unit_Id = su.RegId

		LEFT JOIN StatisticalUnitHistoryCTE suhCTE ON suhCTE.ParentId = su.RegId and suhCTE.RowNumber = 1
		LEFT JOIN dbo.ActivityStatisticalUnitHistory asuh ON asuh.Unit_Id = suhCTE.RegId
		LEFT JOIN dbo.Activities ah ON ah.Id = asuh.Activity_Id
		LEFT JOIN dbo.PersonStatisticalUnitHistory psuh ON psuh.Unit_Id = su.RegId
	WHERE (@InStatUnitType ='All' OR su.Discriminator = @InStatUnitType) 
			AND (@InStatusId = 0 OR su.UnitStatusId = @InStatusId) 
			AND (@InPersonTypeId = 0 OR @InPersonTypeId = IIF(DATEPART(YEAR,su.RegistrationDate) < @InCurrentYear AND DATEPART(YEAR,su.StartPeriod) < @InCurrentYear,psu.PersonTypeId,psuh.PersonTypeId))
			AND a.Activity_Type = 1
),
--table where stat units with the superparent of their ActivityCategory and their oblast
ResultTableCTE2 AS
(
	SELECT
		r.RegId,
		r.PersonId,
		p.Sex,
		ac.ParentId AS ActivityCategoryId,
		tr.Name AS RayonName,
		tr.ParentId AS RayonId,
		ttr.ParentId AS OblastId,
		ttr.Name AS OblastName
	FROM ResultTableCTE AS r
	LEFT JOIN ActivityCategoriesHierarchyCTE AS ac ON ac.Id = r.ActivityCategoryId
	LEFT JOIN dbo.Address AS addr ON addr.Address_id = r.AddressId
	LEFT JOIN RegionsHierarchyCTE AS tr ON tr.Id = addr.Region_id
	INNER JOIN RegionsTotalHierarchyCTE AS ttr ON ttr.Id = addr.Region_id
	INNER JOIN dbo.Persons AS p ON r.PersonId = p.Id 
	WHERE DATEPART(YEAR, r.RegistrationDate) < @InCurrentYear AND r.PersonId IS NOT NULL
),
AddedRayons AS (
	SELECT DISTINCT RayonId 
	FROM ResultTableCTE2 AS rt2 
	WHERE rt2.RayonId IS NOT NULL
),
AddedOblasts AS (
	SELECT DISTINCT OblastId 
	FROM ResultTableCTE2
)

--inserting values for oblast by activity categories
INSERT INTO #tempTableForPivot
SELECT 
	STR(COUNT(rt.PersonId)) AS Count,
	rt.Sex,
	ac.Name + IIF(rt.Sex = 1, '1', '2') AS ActivityCategoryName,
	rt.OblastId,
	'' AS RayonName,
	rt.OblastName
FROM dbo.ActivityCategories as ac
	LEFT JOIN ResultTableCTE2 AS rt ON ac.Id = rt.ActivityCategoryId
	WHERE ac.ActivityCategoryLevel = 1 AND rt.OblastId IS NOT NULL
	GROUP BY ac.Name, rt.OblastId, rt.Sex, rt.OblastName

UNION 

SELECT 
	STR(COUNT(rt.PersonId)) AS Count,
	rt.Sex,
	ac.Name + IIF(rt.Sex = 1, '1', '2') AS ActivityCategoryName,
	rt.OblastId,
	rt.RayonName,
	'' AS OblastName
FROM dbo.ActivityCategories as ac
	LEFT JOIN ResultTableCTE2 AS rt ON ac.Id = rt.ActivityCategoryId
	WHERE ac.ActivityCategoryLevel = 1 AND rt.RayonId IS NOT NULL
	GROUP BY ac.Name, rt.OblastId, rt.Sex, rt.RayonName

UNION

SELECT '0', 1, ac.Name, re.Id, '', re.Name
FROM dbo.Regions AS re
	CROSS JOIN (SELECT TOP 1 Name FROM dbo.ActivityCategories WHERE ActivityCategoryLevel = 1) AS ac
WHERE re.RegionLevel = 2 AND re.Id NOT IN (SELECT OblastId FROM AddedOblasts)

UNION

SELECT '0', 1, ac.Name, re.ParentId, re.Name, ''
FROM dbo.Regions AS re
	CROSS JOIN (SELECT TOP 1 Name FROM dbo.ActivityCategories WHERE ActivityCategoryLevel = 1) AS ac
WHERE re.RegionLevel = 3 AND re.Id NOT IN (SELECT RayonId FROM AddedRayons)

--replacing NULL values with zeroes for regions and activity categories
DECLARE @colswithISNULL as NVARCHAR(MAX) = STUFF((SELECT distinct ', STR(ISNULL(' + QUOTENAME(Name + '1') + ', 0))  AS ' + QUOTENAME(Name + '1') + ', STR(ISNULL(' + QUOTENAME(Name + '2') + ', 0))  AS ' + QUOTENAME(Name + '2')
				FROM dbo.ActivityCategories  WHERE ActivityCategoryLevel = 1
				FOR XML PATH(''), TYPE
				).value('.', 'NVARCHAR(MAX)')
			,1,2,'');

--total sum of values for particular activity category
DECLARE @totalMale AS NVARCHAR(MAX) = STUFF((SELECT distinct '+ ISNULL(CONVERT(INT, ' + QUOTENAME(Name + '1') + '), 0)'
				FROM dbo.ActivityCategories  WHERE ActivityCategoryLevel = 1
				FOR XML PATH(''), TYPE
				).value('.', 'NVARCHAR(MAX)')
			,1,1,'')

--total sum of values for particular activity category
DECLARE @totalFemale AS NVARCHAR(MAX) = STUFF((SELECT distinct '+ISNULL(CONVERT(INT, ' + QUOTENAME(Name + '2') + '), 0)'
				FROM dbo.ActivityCategories  WHERE ActivityCategoryLevel = 1
				FOR XML PATH(''), TYPE
				).value('.', 'NVARCHAR(MAX)')
			,1,1,'')

--ActivityCategories that will be used in columns
DECLARE @namesActivityCategoriesForPivot AS NVARCHAR(MAX) = STUFF((SELECT distinct ',' + QUOTENAME(Name + '1') + ',' + QUOTENAME(Name + '2')
				FROM dbo.ActivityCategories  WHERE ActivityCategoryLevel = 1
				FOR XML PATH(''), TYPE
				).value('.', 'NVARCHAR(MAX)')
			,1,1,'');

--second line of headers, that will be used for naming columns as male and female statistics
DECLARE @maleFemaleLine AS NVARCHAR(MAX) = STUFF((SELECT distinct ', ''Male'' as ' + QUOTENAME(Name + '1') + ', ''Female'' as ' + QUOTENAME(Name + '2')
				FROM dbo.ActivityCategories  WHERE ActivityCategoryLevel = 1
				FOR XML PATH(''), TYPE
				).value('.', 'NVARCHAR(MAX)')
			,1,1,'');

DECLARE @query AS NVARCHAR(MAX) = N'
SELECT '''' as OblastName, '''' as RayonName, ''Male'' as [Total Male], ''Female'' as [Total Female], ' + @maleFemaleLine + '
UNION ALL
SELECT OblastName, RayonName, STR(' + @totalMale + '), STR(' + @totalFemale + '), ' + @colswithISNULL + ' from 
            (
				SELECT 
					Count,
					OblastId,
					RayonName,
					OblastName,
					ActivityCategoryName
				FROM #tempTableForPivot
           ) SourceTable
            PIVOT 
            (
                MAX(Count)
                FOR ActivityCategoryName IN (' + @namesActivityCategoriesForPivot + ')
            ) PivotTable'
execute(@query)
