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
	Count INT NULL,
	Sex TINYINT NULL,
	ActivityParentId INT NULL,
	ActivityCategoryName NVARCHAR(MAX) NULL,
	ActivitySubCategoryName NVARCHAR(MAX) NULL,
	NameOblast NVARCHAR(MAX) NULL
)

--table where ActivityCategories linked to the ancestor with level=2
;WITH ActivityCategoriesHierarchyCTE(Id,ParentId,Name,DesiredLevel) AS(
	SELECT 
		Id,
		ParentId,
		Name,
		DesiredLevel
	FROM v_ActivityCategoriesHierarchy 
	WHERE DesiredLevel=2
),
--table where ActivityCategories linked to the greatest ancestor(with level=1)
ActivityCategoriesTotalHierarchyCTE(Id,ParentId,Name,DesiredLevel) AS(
	SELECT 
		Id,
		ParentId,
		Name,
		DesiredLevel
	FROM v_ActivityCategoriesHierarchy 
	WHERE DesiredLevel=1
),

--table where regions linked to their oblast and region with Id=1
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
		ac1.ParentId AS ActivityCategoryId1,
		ac2.ParentId AS ActivityCategoryId2,
		tr.Name AS RegionParentName,
		tr.ParentId AS RegionParentId
	FROM ResultTableCTE AS r
	LEFT JOIN ActivityCategoriesTotalHierarchyCTE AS ac1 ON ac1.Id = r.ActivityCategoryId
	LEFT JOIN ActivityCategoriesHierarchyCTE AS ac2 ON ac2.Id = r.ActivityCategoryId
	LEFT JOIN dbo.Address AS addr ON addr.Address_id = r.AddressId
	INNER JOIN RegionsHierarchyCTE AS tr ON tr.Id = addr.Region_id
	INNER JOIN dbo.Persons AS p ON r.PersonId = p.Id 
	WHERE DATEPART(YEAR, r.RegistrationDate) < @InCurrentYear AND r.PersonId IS NOT NULL
)

--inserting values for oblast by activity categories
INSERT INTO #tempTableForPivot
SELECT 
	COUNT(rt.Sex) AS Count,
	rt.Sex,
	ac.Id AS ActivityParentId,
	ac.Name AS ActivityCategoryName,
	N' ' AS ActivitySubCategoryName,
	rt.RegionParentName + IIF(rt.Sex = 1, '1', '2') as NameOblast
FROM dbo.ActivityCategories as ac
	LEFT JOIN ResultTableCTE2 AS rt ON ac.Id = rt.ActivityCategoryId1
	WHERE ac.ActivityCategoryLevel = 1
	GROUP BY ac.Name, rt.RegionParentName, rt.Sex, ac.Id

UNION 

SELECT 
	COUNT(rt.Sex) AS Count,
	rt.Sex,
	ac.ParentId AS ActivityParentId,
	N' ' AS ActivityCategoryName,
	ac.Name AS ActivitySubCategoryName,
	rt.RegionParentName + IIF(rt.Sex = 1, '1', '2') as NameOblast
FROM dbo.ActivityCategories as ac
	LEFT JOIN ResultTableCTE2 AS rt ON ac.Id = rt.ActivityCategoryId2
	WHERE ac.ActivityCategoryLevel = 2
	GROUP BY ac.Name, rt.RegionParentName, rt.Sex, ac.ParentId

--replacing NULL values with zeroes for regions and activity categories
DECLARE @colswithISNULL as NVARCHAR(MAX) = STUFF((SELECT distinct ', ISNULL(' + QUOTENAME(Name + '1') + ', 0)  AS ' + QUOTENAME(Name + '1') + ', ISNULL(' + QUOTENAME(Name + '2') + ', 0)  AS ' + QUOTENAME(Name + '2')
				FROM dbo.Regions  WHERE ParentId = 1 AND RegionLevel IN (1,2,3)
				FOR XML PATH(''), TYPE
				).value('.', 'NVARCHAR(MAX)')
			,1,2,'');

--total sum of values for particular activity category
DECLARE @totalMale AS NVARCHAR(MAX) = STUFF((SELECT distinct '+ ISNULL(' + QUOTENAME(Name + '1') + ', 0)'
				FROM dbo.Regions  WHERE ParentId = 1 AND RegionLevel IN (1,2,3) OR Id = 1
				FOR XML PATH(''), TYPE
				).value('.', 'NVARCHAR(MAX)')
			,1,1,'')

--total sum of values for particular activity category
DECLARE @totalFemale AS NVARCHAR(MAX) = STUFF((SELECT distinct '+ISNULL(' + QUOTENAME(Name + '2') + ', 0)'
				FROM dbo.Regions  WHERE ParentId = 1 AND RegionLevel IN (1,2,3) OR Id = 1
				FOR XML PATH(''), TYPE
				).value('.', 'NVARCHAR(MAX)')
			,1,1,'')

--regions that will be used in columns
DECLARE @namesRegionsForPivot AS NVARCHAR(MAX) = STUFF((SELECT distinct ',' + QUOTENAME(Name + '1') + ',' + QUOTENAME(Name + '2')
				FROM dbo.Regions  WHERE ParentId = 1 AND RegionLevel IN (1,2,3) OR Id = 1
				FOR XML PATH(''), TYPE
				).value('.', 'NVARCHAR(MAX)')
			,1,1,'');

--columns with type definition for table creation
DECLARE @colsWithTypeDefinition AS NVARCHAR(MAX) = STUFF((SELECT distinct ', ' + QUOTENAME(Name + '1') + ' INT NULL, ' + QUOTENAME(Name + '2') + ' INT NULL'
				FROM dbo.Regions  WHERE ParentId = 1 AND RegionLevel IN (1,2,3)
				FOR XML PATH(''), TYPE
				).value('.', 'NVARCHAR(MAX)')
			,1,2,'');

IF OBJECT_ID ('tempdb..##tempResultTable') IS NOT NULL
   BEGIN DROP TABLE ##tempResultTable END

--creating temporary table for result
DECLARE @createQuery NVARCHAR(MAX) = N'
CREATE TABLE ##tempResultTable (
	ActivityCategoryName NVARCHAR(MAX) NULL,
	ActivitySubCategoryName NVARCHAR(MAX) NULL,
	ActivityParentId INT NULL,
	' + @colsWithTypeDefinition + N',
	[Total Male] INT NULL,
	[Total Female] INT NULL
)
'
EXECUTE (@createQuery);

DECLARE @insertQuery AS NVARCHAR(MAX) = N'
INSERT INTO ##tempResultTable
SELECT ActivityCategoryName, ActivitySubCategoryName, ActivityParentId, ' + @colswithISNULL + ', ' + @totalMale + ' as [Total Male], ' + @totalFemale + ' as [Total Female] from 
            (
				SELECT 
					Count,
					ActivityParentId,
					ActivityCategoryName,
					ActivitySubCategoryName,
					NameOblast
				FROM #tempTableForPivot
           ) SourceTable
            PIVOT 
            (
                SUM(Count)
                FOR NameOblast IN (' + @namesRegionsForPivot + ')
            ) PivotTable order by ActivityParentId, ActivitySubCategoryName'
execute(@insertQuery)

--columns with type definition for table creation
DECLARE @colsWithTypeDefinitionAsNVARCHAR AS NVARCHAR(MAX) = STUFF((SELECT distinct ', ' + QUOTENAME(Name + '1') + ' NVARCHAR(MAX) NULL, ' + QUOTENAME(Name + '2') + ' NVARCHAR(MAX) NULL'
				FROM dbo.Regions  WHERE ParentId = 1 AND RegionLevel IN (1,2,3)
				FOR XML PATH(''), TYPE
				).value('.', 'NVARCHAR(MAX)')
			,1,2,'');


IF OBJECT_ID ('tempdb..##tempResultTable2') IS NOT NULL
   BEGIN DROP TABLE ##tempResultTable2 END

--creating temporary table for result with values as nvarchar()
DECLARE @createQuery2 NVARCHAR(MAX) = N'
CREATE TABLE ##tempResultTable2 (
	ActivityCategoryName NVARCHAR(MAX) NULL,
	ActivitySubCategoryName NVARCHAR(MAX) NULL,
	ActivityParentId INT NULL,
	[Total Male] NVARCHAR(MAX) NULL,
	[Total Female] NVARCHAR(MAX) NULL,
	' + @colsWithTypeDefinitionAsNVARCHAR + N'
)
'
EXECUTE(@createQuery2)

--second line of headers, that will be used for naming columns as male and female statistics
DECLARE @maleFemaleLine AS NVARCHAR(MAX) = STUFF((SELECT distinct ', ''Male'' as ' + QUOTENAME(Name + '1') + ', ''Female'' as ' + QUOTENAME(Name + '2')
				FROM dbo.Regions  WHERE ParentId = 1 AND RegionLevel IN (1,2,3)
				FOR XML PATH(''), TYPE
				).value('.', 'NVARCHAR(MAX)')
			,1,1,'');

--converting Count from int type to string to match them with names of sex
DECLARE @colsAsString as NVARCHAR(MAX) = STUFF((SELECT distinct ', STR(' + QUOTENAME(Name + '1') + ')  AS ' + QUOTENAME(Name + '1') + ', STR(' + QUOTENAME(Name + '2') + ')  AS ' + QUOTENAME(Name + '2')
	FROM dbo.Regions  WHERE ParentId = 1 AND RegionLevel IN (1,2,3)
	FOR XML PATH(''), TYPE
	).value('.', 'NVARCHAR(MAX)')
,1,2,'');

DECLARE @insertQuery2 AS NVARCHAR(MAX) = '
INSERT INTO ##tempResultTable2
SELECT '''' as ActivityCategoryName, '''' as ActivitySubCategoryName, 0 as ActivityParentId, ''Male'' as [Total Male], ''Female'' as [Total Female], ' + @maleFemaleLine + '
UNION ALL
SELECT ActivityCategoryName, ActivitySubCategoryName, ActivityParentId, STR([Total Male]) as [Total Male], STR([Total Female]) as [Total Female], ' + @colsAsString + '
FROM ##tempResultTable
'
EXECUTE (@insertQuery2)

--converting Count from int type to string to match them with names of sex
DECLARE @colsAsString2 as NVARCHAR(MAX) = STUFF((SELECT distinct ', ' + QUOTENAME(Name + '1') + '  AS ' + QUOTENAME(Name) + ', ' + QUOTENAME(Name + '2') + '  AS ''           '' '
	FROM dbo.Regions  WHERE ParentId = 1 AND RegionLevel IN (1,2,3)
	FOR XML PATH(''), TYPE
	).value('.', 'NVARCHAR(MAX)')
,1,2,'');

DECLARE @resultQuery AS NVARCHAR(MAX) = '
SELECT ActivityCategoryName, ActivitySubCategoryName, [Total Male] as Total, [Total Female] as ''     '', ' + @colsAsString2 + '
FROM ##tempResultTable2
ORDER BY ActivityParentId, ActivitySubCategoryName
'

EXECUTE(@resultQuery)
