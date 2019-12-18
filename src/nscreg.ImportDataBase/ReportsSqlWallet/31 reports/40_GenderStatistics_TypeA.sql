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
	Name NVARCHAR(MAX) NULL,
	NameOblast NVARCHAR(MAX) NULL
)

--table where ActivityCategories linked to the greatest ancestor
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
		ac.ParentId AS ActivityCategoryId,
		tr.Name AS RegionParentName,
		tr.ParentId AS RegionParentId
	FROM ResultTableCTE AS r
	LEFT JOIN ActivityCategoriesHierarchyCTE AS ac ON ac.Id = r.ActivityCategoryId
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
	ac.Name,
	rt.RegionParentName + IIF(rt.Sex = 1, '1', '2') as NameOblast
FROM dbo.ActivityCategories as ac
	LEFT JOIN ResultTableCTE2 AS rt ON ac.Id = rt.ActivityCategoryId
	WHERE ac.ActivityCategoryLevel = 1
	GROUP BY ac.Name, rt.RegionParentName, rt.Sex

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

--second line of headers, that will be used for naming columns as male and female statistics
DECLARE @maleFemaleLine AS NVARCHAR(MAX) = STUFF((SELECT distinct ', ''Male'' as ' + QUOTENAME(Name) + ', ''Female'' as ''                   '''
				FROM dbo.Regions  WHERE ParentId = 1 AND RegionLevel IN (1,2,3)
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
	Name NVARCHAR(MAX) NULL,
	' + @colsWithTypeDefinition + N',
	[Total Male] INT NULL,
	[Total Female] INT NULL
)
'
EXECUTE (@createQuery);

DECLARE @insertQuery AS NVARCHAR(MAX) = N'
INSERT INTO ##tempResultTable
SELECT Name, ' + @colswithISNULL + ', ' + @totalMale + ' as [Total Male], ' + @totalFemale + ' as [Total Female] from 
            (
				SELECT 
					Count,
					Name,
					NameOblast
				FROM #tempTableForPivot
           ) SourceTable
            PIVOT 
            (
                SUM(Count)
                FOR NameOblast IN (' + @namesRegionsForPivot + ')
            ) PivotTable order by Name'
execute(@insertQuery)

--converting Count from int type to string to match them with names of sex
DECLARE @colsAsString as NVARCHAR(MAX) = STUFF((SELECT distinct ', STR(' + QUOTENAME(Name + '1') + ')  AS ' + QUOTENAME(Name) + ', STR(' + QUOTENAME(Name + '2') + ')  AS ''           '' '
	FROM dbo.Regions  WHERE ParentId = 1 AND RegionLevel IN (1,2,3)
	FOR XML PATH(''), TYPE
	).value('.', 'NVARCHAR(MAX)')
,1,2,'');

DECLARE @resultQuery AS NVARCHAR(MAX) = '
SELECT '''' as Name, ''Male'' as Total, ''Female'' as ''     '', ' + @maleFemaleLine + '
UNION ALL
SELECT Name, STR([Total Male]) as Total, STR([Total Female]) as ''     '', ' + @colsAsString + '
FROM ##tempResultTable
'
EXECUTE (@resultQuery)