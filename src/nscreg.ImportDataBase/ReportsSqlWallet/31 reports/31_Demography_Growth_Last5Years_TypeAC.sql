BEGIN /* INPUT PARAMETERS from report body */
	DECLARE @InStatUnitType NVARCHAR(MAX) = $StatUnitType,
			@InCurrentYear NVARCHAR(MAX) = YEAR(GETDATE()),
			@InPreviousYear NVARCHAR(MAX) = YEAR(GETDATE()) - 5
END

/* checking if temporary table exists and deleting it if it is true */
IF (OBJECT_ID('tempdb..#tempTableForPivot') IS NOT NULL)
BEGIN DROP TABLE #tempTableForPivot END

/* 
	list of counts of stat units 
	for each Id and name of ActivityCategory with level = 1,
	name of ActivityCategory with level = 2,
	and name of oblast(region with level = 2(for kyrgyz database))
*/
CREATE TABLE #tempTableForPivot
(
	Count INT NOT NULL DEFAULT 0,
	ActivityCategoryParentId INT NULL,
	ActivityCategoryParentName NVARCHAR(MAX) NULL,
	ActivityCategoryName NVARCHAR(MAX) NULL,
	NameOblast NVARCHAR(MAX) NULL
);

/* table where ActivityCategories linked to the greatest ancestor */
WITH ActivityCategoriesTotalHierarchyCTE(Id,ParentId,Name,DesiredLevel) AS(
	SELECT 
		Id,
		ParentId,
		Name,
		DesiredLevel
	FROM v_ActivityCategoriesHierarchy 
	WHERE DesiredLevel=1
),
/* table where ActivityCategories linked to the ancestor with level = 2 */
ActivityCategoriesHierarchyCTE(Id,ParentId,Name,DesiredLevel) AS(
	SELECT 
		Id,
		ParentId,
		Name,
		DesiredLevel
	FROM v_ActivityCategoriesHierarchy 
	WHERE DesiredLevel=2
),
/* table where regions linked to their ancestor - oblast(region with level = 2) and superregion with Id = 1(level = 1) linked to itself */
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
		DesiredLevel = 2 OR Id = 1
		To:
		DesiredLevel = 1
	*/
	WHERE DesiredLevel = 2 OR Id = 1
),
/* table with needed fields for previous states of stat units that were active in given dateperiod */
StatisticalUnitHistoryCTE AS (
	SELECT
		RegId,
		ParentId,	
		AddressId,
		Discriminator,
		UnitStatusId,
		RegistrationDate,
		LiqDate,
		ROW_NUMBER() over (partition by ParentId order by StartPeriod desc) AS RowNumber
	FROM StatisticalUnitHistory
	WHERE DATEPART(YEAR,RegistrationDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1 AND DATEPART(YEAR,StartPeriod) BETWEEN @InPreviousYear AND @InCurrentYear - 1 OR DATEPART(YEAR,LiqDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1
),
/* list with all stat units linked to their primary ActivityCategory that were active in given dateperiod and have required StatUnitType */
ResultTableCTE AS
(
	SELECT
		IIF(DATEPART(YEAR,su.RegistrationDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1 AND DATEPART(YEAR,su.StartPeriod) BETWEEN @InPreviousYear AND @InCurrentYear - 1 OR DATEPART(YEAR,su.LiqDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1,su.RegId,suhCTE.RegId) AS RegId,
		IIF(DATEPART(YEAR,su.RegistrationDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1 AND DATEPART(YEAR,su.StartPeriod) BETWEEN @InPreviousYear AND @InCurrentYear - 1 OR DATEPART(YEAR,su.LiqDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1,a.ActivityCategoryId,ah.ActivityCategoryId) AS ActivityCategoryId,
		IIF(DATEPART(YEAR,su.RegistrationDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1 AND DATEPART(YEAR,su.StartPeriod) BETWEEN @InPreviousYear AND @InCurrentYear - 1 OR DATEPART(YEAR,su.LiqDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1,su.AddressId,suhCTE.AddressId) AS AddressId,
		IIF(DATEPART(YEAR,su.RegistrationDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1 AND DATEPART(YEAR,su.StartPeriod) BETWEEN @InPreviousYear AND @InCurrentYear - 1 OR DATEPART(YEAR,su.LiqDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1,su.RegistrationDate,suhCTE.RegistrationDate) AS RegistrationDate,
		IIF(DATEPART(YEAR,su.RegistrationDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1 AND DATEPART(YEAR,su.StartPeriod) BETWEEN @InPreviousYear AND @InCurrentYear - 1 OR DATEPART(YEAR,su.LiqDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1,su.UnitStatusId,suhCTE.UnitStatusId) AS UnitStatusId,
		IIF(DATEPART(YEAR,su.RegistrationDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1 AND DATEPART(YEAR,su.StartPeriod) BETWEEN @InPreviousYear AND @InCurrentYear - 1 OR DATEPART(YEAR,su.LiqDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1,su.LiqDate,suhCTE.LiqDate) AS LiqDate,
		IIF(DATEPART(YEAR,su.RegistrationDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1 AND DATEPART(YEAR,su.StartPeriod) BETWEEN @InPreviousYear AND @InCurrentYear - 1 OR DATEPART(YEAR,su.LiqDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1,su.Discriminator,suhCTE.Discriminator) AS Discriminator,
		IIF(DATEPART(YEAR,su.RegistrationDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1 AND DATEPART(YEAR,su.StartPeriod) BETWEEN @InPreviousYear AND @InCurrentYear - 1 OR DATEPART(YEAR,su.LiqDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1,a.Activity_Type,ah.Activity_Type) AS ActivityType,
		IIF(DATEPART(YEAR,su.RegistrationDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1 AND DATEPART(YEAR,su.StartPeriod) BETWEEN @InPreviousYear AND @InCurrentYear - 1 OR DATEPART(YEAR,su.LiqDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1,0,1) AS isHistory
	FROM dbo.StatisticalUnits AS su	
		LEFT JOIN dbo.ActivityStatisticalUnits asu ON asu.Unit_Id = su.RegId
		LEFT JOIN dbo.Activities a ON a.Id = asu.Activity_Id

		LEFT JOIN StatisticalUnitHistoryCTE suhCTE ON suhCTE.ParentId = su.RegId and suhCTE.RowNumber = 1
		LEFT JOIN dbo.ActivityStatisticalUnitHistory asuh ON asuh.Unit_Id = suhCTE.RegId
		LEFT JOIN dbo.Activities ah ON ah.Id = asuh.Activity_Id
),
/* list of stat units linked to their oblast(region with level = 2) */
ResultTableCTE2 AS
(
	SELECT
		r.RegId,
		ac1.ParentId AS ActivityCategoryId1,
		ac2.ParentId AS ActivityCategoryId2,
		r.AddressId,
		tr.RegionLevel,
		tr.Name AS RegionParentName,
		tr.ParentId AS RegionParentId,
		r.RegistrationDate,
		r.UnitStatusId,
		r.LiqDate
	FROM ResultTableCTE AS r
		LEFT JOIN ActivityCategoriesTotalHierarchyCTE AS ac1 ON ac1.Id = r.ActivityCategoryId
		LEFT JOIN ActivityCategoriesHierarchyCTE AS ac2 ON ac2.Id = r.ActivityCategoryId
		LEFT JOIN dbo.Address AS addr ON addr.Address_id = r.AddressId
		INNER JOIN RegionsHierarchyCTE AS tr ON tr.Id = addr.Region_id	
	WHERE (@InStatUnitType ='All' OR (isHistory = 0 AND  r.Discriminator = @InStatUnitType) 
				OR (r.isHistory = 1 AND r.Discriminator = @InStatUnitType + 'History'))
			AND r.ActivityType = 1
)

/* filling temporary table by all ActivityCategories with level 1 and 2, oblasts and stat units from ResultTableCTE linked to them */
INSERT INTO #tempTableForPivot
/* inserting values for ActivityCategories with level = 1 */
SELECT 
	SUM(IIF(DATEPART(YEAR,rt.RegistrationDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1 AND rt.UnitStatusId = 1,1,0)) - SUM(IIF(rt.LiqDate IS NOT NULL AND DATEPART(YEAR,rt.LiqDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1, 1,0)) AS Count,
	ac.Id,
	ac.Name,
	' ',
	rt.RegionParentName as NameOblast
FROM dbo.ActivityCategories as ac
	LEFT JOIN ResultTableCTE2 AS rt ON ac.Id = rt.ActivityCategoryId1
WHERE ac.ActivityCategoryLevel = 1
GROUP BY ac.Name, rt.RegionParentName, ac.Id
	
UNION
/* inserting values for ActivityCategories with level = 2 */
SELECT 
	SUM(IIF(DATEPART(YEAR,rt.RegistrationDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1 AND rt.UnitStatusId = 1,1,0)) - SUM(IIF(rt.LiqDate IS NOT NULL AND DATEPART(YEAR,rt.LiqDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1, 1,0)) AS Count,
	ac.ParentId,
	' ',
	ac.Name,
	rt.RegionParentName as NameOblast
FROM dbo.ActivityCategories as ac
	LEFT JOIN ResultTableCTE2 AS rt ON ac.Id = rt.ActivityCategoryId2
WHERE ac.ActivityCategoryLevel = 2
GROUP BY ac.Name, rt.RegionParentName, ac.ParentId

/* 
	list of regions with level=2, that will be columns in report
	for select statement with replacing NULL values with zeroes
*/
DECLARE @colswithISNULL as NVARCHAR(MAX) = STUFF((SELECT distinct ', ISNULL(' + QUOTENAME(Name) + ', 0)  AS ' + QUOTENAME(Name)
				/* set re.RegionLevel = 1 if there is no Country level at Regions tree */
				FROM dbo.Regions  WHERE RegionLevel = 2
				FOR XML PATH(''), TYPE
				).value('.', 'NVARCHAR(MAX)')
			,1,2,'');

/* total sum of values for select statement */
DECLARE @total AS NVARCHAR(MAX) = STUFF((SELECT distinct '+ISNULL(' + QUOTENAME(Name) + ', 0)'
				/* set re.RegionLevel = 1 if there is no Country level at Regions tree (without condition Id = 1) */
				FROM dbo.Regions  WHERE RegionLevel = 2 OR Id = 1
				FOR XML PATH(''), TYPE
				).value('.', 'NVARCHAR(MAX)')
			,1,1,'')

/* perform pivot on list of stat units transforming names of regions to columns and counting stat units for ActivityCategories with both levels 1 and 2 */
DECLARE @query AS NVARCHAR(MAX) = '
SELECT ActivityCategoryParentName as ActivityCategoryName, ActivityCategoryName as ActivitySubCategoryName, ' + @total + ' as Total, ' + @colswithISNULL + ' from 
            (
				SELECT 
					Count,
					ActivityCategoryParentId,
					ActivityCategoryParentName,
					ActivityCategoryName,
					NameOblast
				FROM #tempTableForPivot
           ) SourceTable
            PIVOT 
            (
                SUM(Count)
                FOR NameOblast IN (' + dbo.GetNamesRegionsForPivot(1,'FORINPIVOT',1) + ')
            ) PivotTable order by ActivityCategoryParentId, ActivitySubCategoryName'

execute(@query)