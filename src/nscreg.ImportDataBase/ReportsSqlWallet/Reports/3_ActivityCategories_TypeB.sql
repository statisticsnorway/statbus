/* Table B
    would get one top level region at the total column
    And sub-level regions - Rayons level */

/* Input parameters from report body - filters that have to be defined by the user */
BEGIN
	DECLARE @InRegionId INT =  $RegionId,
			@InStatUnitType NVARCHAR(MAX) = $StatUnitType,
    		@InStatusId NVARCHAR(MAX) = $StatusId,
			@InCurrentYear NVARCHAR(MAX) = YEAR(GETDATE())
END

/* Name of oblast/county for the total column */
DECLARE @nameTotalColumn AS NVARCHAR(MAX) = (SELECT TOP 1 Name FROM dbo.Regions WHERE Id = @InRegionId)

/* Delete #tempTableForPivot temporary table if exists */
IF (OBJECT_ID('tempdb..#tempTableForPivot') IS NOT NULL)
BEGIN DROP TABLE #tempTableForPivot END

/* Create a temporary table for Pivot - result table */
CREATE TABLE #tempTableForPivot
(
	RegId INT NULL,
	Name NVARCHAR(MAX) NULL,
	NameOblast NVARCHAR(MAX) NULL
)

/* using CTE (Common Table Expressions), recursively collect the Activity Categories tree */
;WITH ActivityCategoriesHierarchyCTE(Id,ParentId,Name,DesiredLevel) AS(
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
  WHERE DesiredLevel = 3 OR Id = @InRegionId AND DesiredLevel  = 2
  should be just:
  WHERE Id = @InRegionId AND DesiredLevel = 2
  */
	WHERE DesiredLevel = 3 OR Id = @InRegionId AND DesiredLevel  = 2
),

/* using CTE (Common Table Expressions),
Check the history logs by StartPeriod less then current year -
to have the actual state of statistical units less than current year
*/
StatisticalUnitHistoryCTE AS (
	SELECT
		suh.RegId,
		suh.ParentId,
		ach.ParentId as achParentId,
		ach.Name as acchName,
		trh.Name as trhParentName,
		suh.AddressId,
		suh.UnitStatusId,
		suh.Discriminator,
		ROW_NUMBER() over (partition by suh.ParentId order by suh.StartPeriod desc) AS RowNumber
	FROM dbo.StatisticalUnitHistory as suh
		LEFT JOIN dbo.ActivityStatisticalUnitHistory asuh ON asuh.Unit_Id = suh.RegId
		LEFT JOIN dbo.Activities ah ON ah.Id = asuh.Activity_Id
		LEFT JOIN ActivityCategoriesHierarchyCTE AS ach ON ach.Id = ah.ActivityCategoryId
		LEFT JOIN dbo.Address AS addrh ON addrh.Address_id = suh.AddressId
		LEFT JOIN RegionsHierarchyCTE as trh ON trh.Id = addrh.Region_id
	WHERE DATEPART(YEAR,suh.StartPeriod)<@InCurrentYear AND ah.Activity_Type = 1
),

/* Get the actual state of statistical units where StartPeriod and RegistrationDate less than current year, with history logs */
ResultTableCTE AS
(
	SELECT
		IIF(DATEPART(YEAR, su.RegistrationDate) < @InCurrentYear AND DATEPART(YEAR,su.StartPeriod) < @InCurrentYear,su.RegId, asuhCTE.RegId) AS RegId,
		IIF(DATEPART(YEAR, su.RegistrationDate) < @InCurrentYear AND DATEPART(YEAR,su.StartPeriod) < @InCurrentYear,ac.ParentId,ach.ParentId) AS ActivityCategoryId,
		IIF(DATEPART(YEAR, su.RegistrationDate) < @InCurrentYear AND DATEPART(YEAR,su.StartPeriod) < @InCurrentYear,su.AddressId,asuhCTE.AddressId) AS AddressId,
		IIF(DATEPART(YEAR, su.RegistrationDate) < @InCurrentYear AND DATEPART(YEAR,su.StartPeriod) < @InCurrentYear,su.UnitStatusId,asuhCTE.UnitStatusId) AS UnitStatusId,
		IIF(DATEPART(YEAR, su.RegistrationDate) < @InCurrentYear AND DATEPART(YEAR,su.StartPeriod) < @InCurrentYear,su.Discriminator,asuhCTE.Discriminator) AS Discriminator,
		IIF(DATEPART(YEAR, su.RegistrationDate) < @InCurrentYear AND DATEPART(YEAR,su.StartPeriod) < @InCurrentYear,a.Activity_Type,ah.Activity_Type) AS ActivityType,
		IIF(DATEPART(YEAR, su.RegistrationDate) < @InCurrentYear AND DATEPART(YEAR,su.StartPeriod) < @InCurrentYear,0,1) AS isHistory
	FROM StatisticalUnits AS su
		LEFT JOIN ActivityStatisticalUnits asu ON asu.Unit_Id = su.RegId
		LEFT JOIN Activities a ON a.Id = asu.Activity_Id
		LEFT JOIN ActivityCategoriesHierarchyCTE AS ac ON ac.Id = a.ActivityCategoryId
		
		LEFT JOIN StatisticalUnitHistoryCTE asuhCTE ON asuhCTE.ParentId = su.RegId and asuhCTE.RowNumber = 1
		LEFT JOIN ActivityStatisticalUnitHistory asuh ON asuh.Unit_Id = asuhCTE.RegId
		LEFT JOIN Activities ah ON ah.Id = asuh.Activity_Id
		LEFT JOIN ActivityCategoriesHierarchyCTE AS ach ON ach.Id = ah.ActivityCategoryId
    WHERE su.IsDeleted = 0
),
ResultTableCTE2 AS
(
	SELECT
		RegId,
		tr.Name AS NameOblast,
		ActivityCategoryId
	FROM ResultTableCTE AS rt
		LEFT JOIN dbo.Address AS addr ON addr.Address_id = rt.AddressId
		INNER JOIN RegionsHierarchyCTE AS tr ON tr.Id = addr.Region_id

	WHERE (@InStatUnitType ='All' OR (isHistory = 0 AND  rt.Discriminator = @InStatUnitType) 
				OR (isHistory = 1 AND rt.Discriminator = @InStatUnitType + 'History'))
			AND (@InStatusId = 0 OR rt.UnitStatusId = @InStatusId)
			AND rt.ActivityType = 1
)
/* Fill with data the temporary table for pivot */
INSERT INTO #tempTableForPivot
SELECT
	rt.RegId,
	ac.Name,
	rt.NameOblast
FROM dbo.ActivityCategories as ac
	LEFT JOIN ResultTableCTE2 AS rt ON ac.Id = rt.ActivityCategoryId
	WHERE ac.ActivityCategoryLevel = 1

DECLARE
  @selectedCols NVARCHAR(MAX) = dbo.GetRayonsColumnNamesWithNullCheck(@InRegionId),
  @cols NVARCHAR(MAX) = dbo.GetRayonsColumnNames(@InRegionId),
  @total NVARCHAR(MAX) = dbo.CountTotalInRayonsAsSql(@InRegionId);

/* Create a query and pivot the regions */
DECLARE @query AS NVARCHAR(MAX) = '
SELECT
	Name, ' + @total + ' as [' + @nameTotalColumn+ '], ' + @selectedCols + ' from
		(
				SELECT
					RegId,
					Name,
					NameOblast
				FROM #tempTableForPivot
           ) SourceTable
            PIVOT
            (
                COUNT(RegId)
                FOR NameOblast IN (' + @cols + ')
            ) PivotTable
			'
/* execution of the query */
execute(@query)
