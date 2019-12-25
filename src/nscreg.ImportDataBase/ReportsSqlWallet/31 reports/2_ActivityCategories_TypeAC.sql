/* Table AC
    would get all top level regions
    Row header 1 - Activity Categories Top Level
    Row header 2 - Activity Categories Sub level items
    Values = Count of statistical units
    Column headers - Regions Top level items */

/* Input parameters from report body - filters that have to be defined by the user */
BEGIN
	DECLARE @InStatusId NVARCHAR(MAX) = $StatusId,
			@InStatUnitType NVARCHAR(MAX) = $StatUnitType,
			@InCurrentYear NVARCHAR(MAX) = YEAR(GETDATE())
END

/* Delete a temporary table #tempTableForPivot if exists */
IF (OBJECT_ID('tempdb..#tempTableForPivot') IS NOT NULL)
BEGIN DROP TABLE #tempTableForPivot END

/* Create a temporary table for Pivot - result table that would be transformed to needed result view*/
CREATE TABLE #tempTableForPivot
(
	RegId INT NULL,
	ActivityParentId INT NULL,
	ActivityCategoryName NVARCHAR(MAX) NULL,
	ActivitySubCategoryName NVARCHAR(MAX) NULL,
	NameOblast NVARCHAR(MAX) NULL
)

/* using CTE (Common Table Expressions), recursively collect the Activity Categories tree
Level 1 */
;WITH ActivityCategoriesTotalHierarchyCTE(Id,ParentId,Name,DesiredLevel) AS(
	SELECT
		Id,
		ParentId,
		Name,
		DesiredLevel
	FROM v_ActivityCategoriesHierarchy
	WHERE DesiredLevel=1
),
/* Level 2 */
ActivityCategoriesHierarchyCTE(Id,ParentId,Name,DesiredLevel) AS(
	SELECT
		Id,
		ParentId,
		Name,
		DesiredLevel
	FROM v_ActivityCategoriesHierarchy
	WHERE DesiredLevel=2
),

/* using CTE (Common Table Expressions), recursively collect the Regions tree */
RegionsHierarchyCTE AS(
	SELECT
		Id,
		ParentId,
		Name,
		RegionLevel,
		DesiredLevel
	FROM v_Regions
  /* If there no Country-level at the Regions catalog,
  "WHERE" condition below from:
  WHERE DesiredLevel = 2 OR Id = 1 AND DesiredLevel  = 1
  should be just:
  WHERE DesiredLevel = 1
  */
	WHERE DesiredLevel = 2 OR Id = 1 AND DesiredLevel  = 1
),

/* using CTE (Common Table Expressions),
Check the history logs by StartPeriod less then current year -
to have the actual state of statistical units less than current year
*/
StatisticalUnitHistoryCTE AS (
	SELECT
		RegId,
		ParentId,
		AddressId,
		UnitStatusId,
		Discriminator,
		ROW_NUMBER() over (partition by ParentId order by StartPeriod desc) AS RowNumber
	FROM StatisticalUnitHistory
	WHERE DATEPART(YEAR,RegistrationDate) < @InCurrentYear AND DATEPART(YEAR,StartPeriod) < @InCurrentYear
),

/* Get the actual state of statistical units where StartPeriod and RegistrationDate less than current year, with history logs */
ResultTableCTE AS
(
	SELECT
		IIF(DATEPART(YEAR, su.RegistrationDate) < @InCurrentYear AND DATEPART(YEAR,su.StartPeriod) < @InCurrentYear,su.RegId, asuhCTE.RegId) AS RegId,
		IIF(DATEPART(YEAR, su.RegistrationDate) < @InCurrentYear AND DATEPART(YEAR,su.StartPeriod) < @InCurrentYear,ac1.ParentId,ach1.ParentId) AS ActivityCategoryId1,
		IIF(DATEPART(YEAR, su.RegistrationDate) < @InCurrentYear AND DATEPART(YEAR,su.StartPeriod) < @InCurrentYear,ac2.ParentId,ach2.ParentId) AS ActivityCategoryId2,
		IIF(DATEPART(YEAR, su.RegistrationDate) < @InCurrentYear AND DATEPART(YEAR,su.StartPeriod) < @InCurrentYear,su.AddressId,asuhCTE.AddressId) AS AddressId,
		IIF(DATEPART(YEAR, su.RegistrationDate) < @InCurrentYear AND DATEPART(YEAR,su.StartPeriod) < @InCurrentYear,su.UnitStatusId,asuhCTE.UnitStatusId) AS UnitStatusId,
		IIF(DATEPART(YEAR, su.RegistrationDate) < @InCurrentYear AND DATEPART(YEAR,su.StartPeriod) < @InCurrentYear,su.Discriminator,asuhCTE.Discriminator) AS Discriminator,
		IIF(DATEPART(YEAR, su.RegistrationDate) < @InCurrentYear AND DATEPART(YEAR,su.StartPeriod) < @InCurrentYear,a.Activity_Type,ah.Activity_Type) AS ActivityType,
		IIF(DATEPART(YEAR, su.RegistrationDate) < @InCurrentYear AND DATEPART(YEAR,su.StartPeriod) < @InCurrentYear,0,1) AS isHistory
	FROM StatisticalUnits AS su
		LEFT JOIN ActivityStatisticalUnits asu ON asu.Unit_Id = su.RegId
		LEFT JOIN Activities a ON a.Id = asu.Activity_Id
		LEFT JOIN ActivityCategoriesTotalHierarchyCTE AS ac1 ON ac1.Id = a.ActivityCategoryId
		LEFT JOIN ActivityCategoriesHierarchyCTE AS ac2 ON ac2.Id = a.ActivityCategoryId
		
		LEFT JOIN StatisticalUnitHistoryCTE asuhCTE ON asuhCTE.ParentId = su.RegId and asuhCTE.RowNumber = 1
		LEFT JOIN ActivityStatisticalUnitHistory asuh ON asuh.Unit_Id = asuhCTE.RegId
		LEFT JOIN Activities ah ON ah.Id = asuh.Activity_Id
		LEFT JOIN ActivityCategoriesTotalHierarchyCTE AS ach1 ON ach1.Id = ah.ActivityCategoryId
		LEFT JOIN ActivityCategoriesHierarchyCTE AS ach2 ON ach2.Id = ah.ActivityCategoryId
),
ResultTableCTE2 AS
(
	SELECT
		RegId,
		tr.Name AS NameOblast,
		rt.ActivityCategoryId1,
		rt.ActivityCategoryId2
	FROM ResultTableCTE AS rt
		LEFT JOIN dbo.Address AS addr ON addr.Address_id = rt.AddressId
		INNER JOIN RegionsHierarchyCTE AS tr ON tr.Id = addr.Region_id

	WHERE (@InStatUnitType ='All' OR (isHistory = 0 AND  rt.Discriminator = @InStatUnitType) 
				OR (isHistory = 1 AND rt.Discriminator = @InStatUnitType + 'History'))
			AND (@InStatusId = 0 OR rt.UnitStatusId = @InStatusId)
			AND rt.ActivityType = 1
)
/* Fill with data the #tempTableForPivot */
INSERT INTO #tempTableForPivot
SELECT
	rt.RegId,
	ac.Id AS ActivityParentId,
	ac.Name AS ActivityCategoryName,
	'' AS ActivitySubCategoryName,
	rt.NameOblast
FROM dbo.ActivityCategories as ac
	LEFT JOIN ResultTableCTE2 AS rt ON ac.Id = rt.ActivityCategoryId1
	WHERE ac.ActivityCategoryLevel = 1

UNION

SELECT
	rt.RegId,
	ac.ParentId AS ActivityParentId,
	'' AS ActivityCategoryName,
	ac.Name AS ActivitySubCategoryName,
	rt.NameOblast
FROM dbo.ActivityCategories as ac
	LEFT JOIN ResultTableCTE2 AS rt ON ac.Id = rt.ActivityCategoryId2
	WHERE ac.ActivityCategoryLevel = 2

/* Create a query and pivot the regions */
DECLARE @query AS NVARCHAR(MAX) = '
	SELECT ActivityCategoryName, ActivitySubCategoryName, ' + dbo.[GetNamesRegionsForPivot](1, 'TOTAL',1) + ' as Total, ' + dbo.GetNamesRegionsForPivot(1,'FORINPIVOT',0) + ' from
            (
				SELECT
					RegId,
					ActivityParentId,
					ActivityCategoryName,
					ActivitySubCategoryName,
					NameOblast
				FROM #tempTableForPivot
           ) SourceTable
            PIVOT
            (
                COUNT(RegId)
                FOR NameOblast IN (' + dbo.GetNamesRegionsForPivot(1,'FORINPIVOT',1) + ')
            ) PivotTable order by ActivityParentId, ActivityCategoryName DESC, ActivitySubCategoryName'
/* execution of the query */
execute(@query)
