/* Table AC
    would get all top level regions
    Row header 1 - Activity Categories Top Level
    Row header 2 - Activity Categories Sub level items
    Values = Sum of Employees
    Column headers - Regions
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

/* Delete temporary table #tempTableForPivot if exists */
IF (OBJECT_ID('tempdb..#tempTableForPivot') IS NOT NULL)
BEGIN DROP TABLE #tempTableForPivot END

/* Create temporary table for Pivot - result table that would be transformed to needed result view */
CREATE TABLE #tempTableForPivot
(
	RegId INT NULL,
	Employees INT NULL,
	ActivityCategoryId INT NULL,
	ActivityCategoryName NVARCHAR(MAX) NULL,
	ActivitySubCategoryName NVARCHAR(MAX) NULL,
	NameOblast NVARCHAR(MAX) NULL
)

/* using CTE (Common Table Expressions), recursively collect the Activity Categories tree
Level 2
*/
;WITH ActivityCategoriesHierarchyCTE(Id,ParentId,Name,DesiredLevel) AS(
	SELECT
		Id,
		ParentId,
		Name,
		DesiredLevel
	FROM v_ActivityCategoriesHierarchy
	WHERE DesiredLevel=2
),
/* Level 1 */
ActivityCategoriesTotalHierarchyCTE(Id,ParentId,Name,DesiredLevel) AS(
	SELECT
		Id,
		ParentId,
		Name,
		DesiredLevel
	FROM v_ActivityCategoriesHierarchy
	WHERE DesiredLevel=1
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
		Employees,
		ROW_NUMBER() over (partition by ParentId order by StartPeriod desc) AS RowNumber
	FROM StatisticalUnitHistory
	WHERE DATEPART(YEAR,StartPeriod)<@InCurrentYear
),

/* Get the actual state of statistical units where StartPeriod and registrationDate less than current year, with history logs */
ResultTableCTE AS
(
	SELECT
		su.RegId as RegId,
		IIF(DATEPART(YEAR, su.RegistrationDate)<@InCurrentYear AND DATEPART(YEAR,su.StartPeriod)<@InCurrentYear,ac1.Name,ach1.Name) AS Name,
		IIF(DATEPART(YEAR, su.RegistrationDate)<@InCurrentYear AND DATEPART(YEAR,su.StartPeriod)<@InCurrentYear,tr.Name,trh.Name) AS NameOblast,
		IIF(DATEPART(YEAR, su.RegistrationDate)<@InCurrentYear AND DATEPART(YEAR,su.StartPeriod)<@InCurrentYear,su.Employees,asuhCTE.Employees) AS Employees,
		IIF(DATEPART(YEAR, su.RegistrationDate)<@InCurrentYear AND DATEPART(YEAR,su.StartPeriod)<@InCurrentYear,ac1.ParentId,ach1.ParentId) AS ActivityCategoryId1,
		IIF(DATEPART(YEAR, su.RegistrationDate)<@InCurrentYear AND DATEPART(YEAR,su.StartPeriod)<@InCurrentYear,ac2.ParentId,ach2.ParentId) AS ActivityCategoryId2

	FROM StatisticalUnits AS su
		LEFT JOIN ActivityStatisticalUnits asu ON asu.Unit_Id = su.RegId
		LEFT JOIN Activities a ON a.Id = asu.Activity_Id
		LEFT JOIN ActivityCategoriesTotalHierarchyCTE AS ac1 ON ac1.Id = a.ActivityCategoryId
		LEFT JOIN ActivityCategoriesHierarchyCTE AS ac2 ON ac2.Id = a.ActivityCategoryId
		LEFT JOIN dbo.Address AS addr ON addr.Address_id = su.AddressId
		INNER JOIN RegionsHierarchyCTE AS tr ON tr.Id = addr.Region_id

		LEFT JOIN StatisticalUnitHistoryCTE asuhCTE ON asuhCTE.ParentId = su.RegId and asuhCTE.RowNumber = 1
		LEFT JOIN ActivityStatisticalUnitHistory asuh ON asuh.Unit_Id = asuhCTE.RegId
		LEFT JOIN Activities ah ON ah.Id = asuh.Activity_Id
		LEFT JOIN ActivityCategoriesTotalHierarchyCTE AS ach1 ON ach1.Id = ah.ActivityCategoryId
		LEFT JOIN ActivityCategoriesHierarchyCTE AS ach2 ON ach2.Id = ah.ActivityCategoryId
		LEFT JOIN dbo.Address AS addrh ON addrh.Address_id = asuhCTE.AddressId
		LEFT JOIN RegionsHierarchyCTE AS trh ON trh.Id = addrh.Region_id
	WHERE (@InStatUnitType ='All' OR su.Discriminator = @InStatUnitType) AND (@InStatusId = 0 OR su.UnitStatusId = @InStatusId)
  AND a.Activity_Type = 1
)

/* Fill with data the #tempTableForPivot */
INSERT INTO #tempTableForPivot
SELECT
	rt.RegId,
	rt.Employees,
	ac.Id AS ActivityCategoryId,
	ac.Name AS ActivityCategoryName,
	'' AS ActivitySubCategoryName,
	rt.NameOblast
FROM dbo.ActivityCategories as ac
	LEFT JOIN ResultTableCTE AS rt ON ac.Id = rt.ActivityCategoryId1
	WHERE ac.ActivityCategoryLevel = 1
UNION
SELECT
	rt.RegId,
	rt.Employees,
	ac.ParentId AS ActivityCategoryId,
	'' AS ActivityCategoryName,
	ac.Name AS ActivitySubCategoryName,
	rt.NameOblast
FROM dbo.ActivityCategories as ac
	LEFT JOIN ResultTableCTE AS rt ON ac.Id = rt.ActivityCategoryId2
	WHERE ac.ActivityCategoryLevel = 2


DECLARE @cols NVARCHAR(MAX) = STUFF((SELECT distinct ', ISNULL(' + QUOTENAME(Name) + ', 0) AS ' + QUOTENAME(Name)
        /* If there no Country level in your Regions table, below "WHERE" condition from:
            WHERE RegionLevel = 2
            Must be:
            WHERE RegionLevel = 1
        */
        FROM dbo.Regions  WHERE RegionLevel = 2
				FOR XML PATH(''), TYPE
				).value('.', 'NVARCHAR(MAX)')
			,1,1,''),

    /* COLUMN - Total value by whole country */
    @total NVARCHAR(MAX) = STUFF((SELECT distinct '+ ISNULL(' + QUOTENAME(Name) + ', 0)'
				/* If there no Country level in your Regions table, below "WHERE" condition from:
            WHERE RegionLevel IN (1, 2)
            Must be:
            WHERE RegionLevel = 1
        */
        FROM dbo.Regions  WHERE RegionLevel IN (1, 2)
				FOR XML PATH(''), TYPE
				).value('.', 'NVARCHAR(MAX)')
			,1,1,'');


/*
Create a query and pivot the regions
*/
DECLARE @query AS NVARCHAR(MAX) = '
SELECT ActivityCategoryName, ActivitySubCategoryName, ' + @total + ' as Total, ' + @cols + ' from
            (
				SELECT
					Employees,
					ActivityCategoryId,
					ActivityCategoryName,
					ActivitySubCategoryName,
					NameOblast
				FROM #tempTableForPivot
           ) SourceTable
            PIVOT
            (
                SUM(Employees)
                FOR NameOblast IN (' + dbo.GetNamesRegionsForPivot(1,'FORINPIVOT',1) + ')
            ) PivotTable order by ActivityCategoryId, ActivitySubCategoryName'
/* execution of the query */
execute(@query)
