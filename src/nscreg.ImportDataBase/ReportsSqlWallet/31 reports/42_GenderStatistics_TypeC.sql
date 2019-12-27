BEGIN /* INPUT PARAMETERS from report body */
	DECLARE @InStatusId NVARCHAR(MAX) = $StatusId,
			@InStatUnitType NVARCHAR(MAX) = $StatUnitType,
			@InPersonTypeId NVARCHAR(MAX) = $PersonTypeId,
			@InCurrentYear NVARCHAR(MAX) = YEAR(GETDATE())
END

/* checking if temporary table exists and deleting it if it is true */
IF (OBJECT_ID('tempdb..#tempTableForPivot') IS NOT NULL)
BEGIN DROP TABLE #tempTableForPivot END

/* 
	table with count of employees of new stat units
	for each Sex, 
	name of ActivityCategory with level = 1, 
	name and Id of Oblast(region with level = 2),
	and name of Rayon(region with level = 3)	
*/
CREATE TABLE #tempTableForPivot
(
	Count NVARCHAR(MAX) NULL,
	Sex TINYINT NULL,
	ActivityCategoryName NVARCHAR(MAX) NULL,
	OblastId INT NULL,
	RayonName NVARCHAR(MAX) NULL,
	OblastName NVARCHAR(MAX) NULL
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
/* table where regions linked to their ancestor - oblast(region with level = 2) and superregion with Id = 1(level = 1) linked to itself */
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
		DesiredLevel = 2 OR Id = 1 AND DesiredLevel  = 1
		To:
		DesiredLevel = 1
	*/
	WHERE DesiredLevel = 2 OR Id = 1 AND DesiredLevel  = 1
),
/* table where regions linked to their ancestor - rayon(region with level = 3) */
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
		DesiredLevel = 3
		To:
		DesiredLevel = 2
	*/
	WHERE DesiredLevel = 3
),
/* table with needed fields for previous states of stat units that were active in given dateperiod */
StatisticalUnitHistoryCTE AS (
	SELECT
		RegId,
		ParentId,	
		AddressId,
		ROW_NUMBER() over (partition by ParentId order by StartPeriod desc) AS RowNumber
	FROM StatisticalUnitHistory
	WHERE DATEPART(YEAR,StartPeriod) < @InCurrentYear
),
/* list with all stat units linked to their primary ActivityCategory that were active in given dateperiod and have required StatUnitType and Status */
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
/* list of stat units linked to their rayon(region with level = 3) and oblast(region with level = 2) */
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
/* list of rayons(regions with level = 3) from ResultTableCTE2 */
AddedRayons AS (
	SELECT DISTINCT RayonId 
	FROM ResultTableCTE2 AS rt2 
	WHERE rt2.RayonId IS NOT NULL
),
/* list of oblasts(regions with level = 2) from ResultTableCTE2 */
AddedOblasts AS (
	SELECT DISTINCT OblastId 
	FROM ResultTableCTE2
)

/* filling temporary table by all ActivityCategories with level=1, regions and counting number of persons of each gender from ResultTableCTE linked to them */ 
INSERT INTO #tempTableForPivot
/* inserting values for oblasts */
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
/* inserting values for rayons */
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
/* inserting values for not added oblasts(regions with level = 2) that will be the first headers column */
SELECT '0', 1, ac.Name, re.Id, '', re.Name
FROM dbo.Regions AS re
	CROSS JOIN (SELECT TOP 1 Name FROM dbo.ActivityCategories WHERE ActivityCategoryLevel = 1) AS ac
/* set re.RegionLevel = 1 if there is no Country level at Regions tree */
WHERE re.RegionLevel = 2 AND re.Id NOT IN (SELECT OblastId FROM AddedOblasts)

UNION
/* inserting values for not added rayons(regions with level = 3) that will be the second headers column */
SELECT '0', 1, ac.Name, re.ParentId, re.Name, ''
FROM dbo.Regions AS re
	CROSS JOIN (SELECT TOP 1 Name FROM dbo.ActivityCategories WHERE ActivityCategoryLevel = 1) AS ac
/* set re.RegionLevel = 2 if there is no Country level at Regions tree */
WHERE re.RegionLevel = 3 AND re.Id NOT IN (SELECT RayonId FROM AddedRayons)

/* 
	list of regions with level=2, that will be columns in report
	for select statement with replacing NULL values with zeroes as string
*/
DECLARE @colswithISNULL as NVARCHAR(MAX) = STUFF((SELECT distinct ', STR(ISNULL(' + QUOTENAME(Name + '1') + ', 0))  AS ' + QUOTENAME(Name + '1') + ', STR(ISNULL(' + QUOTENAME(Name + '2') + ', 0))  AS ' + QUOTENAME(Name + '2')
				FROM dbo.ActivityCategories  WHERE ActivityCategoryLevel = 1
				FOR XML PATH(''), TYPE
				).value('.', 'NVARCHAR(MAX)')
			,1,2,'');

/* total sum of male persons for select statement */
DECLARE @totalMale AS NVARCHAR(MAX) = STUFF((SELECT distinct '+ ISNULL(CONVERT(INT, ' + QUOTENAME(Name + '1') + '), 0)'
				FROM dbo.ActivityCategories  WHERE ActivityCategoryLevel = 1
				FOR XML PATH(''), TYPE
				).value('.', 'NVARCHAR(MAX)')
			,1,1,'')

/* total sum of female persons for select statement */
DECLARE @totalFemale AS NVARCHAR(MAX) = STUFF((SELECT distinct '+ISNULL(CONVERT(INT, ' + QUOTENAME(Name + '2') + '), 0)'
				FROM dbo.ActivityCategories  WHERE ActivityCategoryLevel = 1
				FOR XML PATH(''), TYPE
				).value('.', 'NVARCHAR(MAX)')
			,1,1,'')

/* list of names of regions that were used in #tempTableForPivot */
DECLARE @namesActivityCategoriesForPivot AS NVARCHAR(MAX) = STUFF((SELECT distinct ',' + QUOTENAME(Name + '1') + ',' + QUOTENAME(Name + '2')
				FROM dbo.ActivityCategories  WHERE ActivityCategoryLevel = 1
				FOR XML PATH(''), TYPE
				).value('.', 'NVARCHAR(MAX)')
			,1,1,'');

/* second line of headers, that will be used for naming columns as Male and Female */
DECLARE @maleFemaleLine AS NVARCHAR(MAX) = STUFF((SELECT distinct ', ''Male'' as ' + QUOTENAME(Name + '1') + ', ''Female'' as ' + QUOTENAME(Name + '2')
				FROM dbo.ActivityCategories  WHERE ActivityCategoryLevel = 1
				FOR XML PATH(''), TYPE
				).value('.', 'NVARCHAR(MAX)')
			,1,1,'');

/*
	perform pivot on list of number of employees of each sex 
	transforming names of ActivityCategories to columns,
	ordering rows by OblastId and RayonName(by order in inner select statement)
	and uniting it with line of headers(maleFemaleLine)
*/
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
