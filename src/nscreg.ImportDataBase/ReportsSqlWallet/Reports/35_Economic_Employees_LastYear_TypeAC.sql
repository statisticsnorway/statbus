BEGIN /* INPUT PARAMETERS from report body */
	DECLARE @InStatusId NVARCHAR(MAX) = $StatusId,
			@InStatUnitType NVARCHAR(MAX) = $StatUnitType,
			@InCurrentYear NVARCHAR(MAX) = YEAR(GETDATE()),
			@InPreviousYear NVARCHAR(MAX) = YEAR(GETDATE()) - 1
END

/* checking if temporary table exists and deleting it if it is true */
IF (OBJECT_ID('tempdb..#tempTableForPivot') IS NOT NULL)
BEGIN DROP TABLE #tempTableForPivot END

/* table with count of employees of new stat units for each ActivityCategory with level = 1 in each Oblast(region with level = 2) */
CREATE TABLE #tempTableForPivot
(
	Count INT NULL,
	ActivityParentId INT NULL,
	ActivityCategoryName NVARCHAR(MAX) NULL,
	ActivitySubCategoryName NVARCHAR(MAX) NULL,
	NameOblast NVARCHAR(MAX) NULL
);

/* table where ActivityCategories linked to the ancestor with level = 2 */
WITH ActivityCategoriesHierarchyCTE(Id,ParentId,Name,DesiredLevel) AS(
	SELECT 
		Id,
		ParentId,
		Name,
		DesiredLevel
	FROM v_ActivityCategoriesHierarchy 
	WHERE DesiredLevel = 2
),
/* table where ActivityCategories linked to the greatest ancestor */
ActivityCategoriesTotalHierarchyCTE(Id,ParentId,Name,DesiredLevel) AS(
	SELECT 
		Id,
		ParentId,
		Name,
		DesiredLevel
	FROM v_ActivityCategoriesHierarchy 
	WHERE DesiredLevel =1
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
		Employees,
		UnitStatusId,
		Discriminator,
		RegistrationDate,
		LiqDate,
		ROW_NUMBER() over (partition by ParentId order by StartPeriod desc) AS RowNumber
	FROM StatisticalUnitHistory
	WHERE DATEPART(YEAR,RegistrationDate) = @InPreviousYear AND DATEPART(YEAR,StartPeriod) = @InPreviousYear
),
/* list with all stat units linked to their primary ActivityCategory that were active in given dateperiod and have required StatUnitType */
ResultTableCTE AS
(
	SELECT
		IIF(DATEPART(YEAR,su.RegistrationDate) = @InPreviousYear AND DATEPART(YEAR,su.StartPeriod) = @InPreviousYear,su.RegId,suhCTE.RegId) AS RegId,
		IIF(DATEPART(YEAR,su.RegistrationDate) = @InPreviousYear AND DATEPART(YEAR,su.StartPeriod) = @InPreviousYear,a.ActivityCategoryId,ah.ActivityCategoryId) AS ActivityCategoryId,
		IIF(DATEPART(YEAR,su.RegistrationDate) = @InPreviousYear AND DATEPART(YEAR,su.StartPeriod) = @InPreviousYear,su.Discriminator,suhCTE.Discriminator) AS Discriminator,
		IIF(DATEPART(YEAR,su.RegistrationDate) = @InPreviousYear AND DATEPART(YEAR,su.StartPeriod) = @InPreviousYear,a.Activity_Type,ah.Activity_Type) AS ActivityType,
		IIF(DATEPART(YEAR,su.RegistrationDate) = @InPreviousYear AND DATEPART(YEAR,su.StartPeriod) = @InPreviousYear,su.AddressId,suhCTE.AddressId) AS AddressId,
		IIF(DATEPART(YEAR,su.RegistrationDate) = @InPreviousYear AND DATEPART(YEAR,su.StartPeriod) = @InPreviousYear,su.Employees,suhCTE.Employees) AS Employees,
		IIF(DATEPART(YEAR,su.RegistrationDate) = @InPreviousYear AND DATEPART(YEAR,su.StartPeriod) = @InPreviousYear,su.RegistrationDate,suhCTE.RegistrationDate) AS RegistrationDate,
		IIF(DATEPART(YEAR,su.RegistrationDate) = @InPreviousYear AND DATEPART(YEAR,su.StartPeriod) = @InPreviousYear,su.UnitStatusId,suhCTE.UnitStatusId) AS UnitStatusId,
		IIF(DATEPART(YEAR,su.RegistrationDate) = @InPreviousYear AND DATEPART(YEAR,su.StartPeriod) = @InPreviousYear,su.LiqDate,suhCTE.LiqDate) AS LiqDate,
		IIF(DATEPART(YEAR,su.RegistrationDate) = @InPreviousYear AND DATEPART(YEAR,su.StartPeriod) = @InPreviousYear,0,1) AS isHistory
	FROM dbo.StatisticalUnits AS su	
		LEFT JOIN dbo.ActivityStatisticalUnits asu ON asu.Unit_Id = su.RegId
		LEFT JOIN dbo.Activities a ON a.Id = asu.Activity_Id

		LEFT JOIN StatisticalUnitHistoryCTE suhCTE ON suhCTE.ParentId = su.RegId and suhCTE.RowNumber = 1
		LEFT JOIN dbo.ActivityStatisticalUnitHistory asuh ON asuh.Unit_Id = suhCTE.RegId
		LEFT JOIN dbo.Activities ah ON ah.Id = asuh.Activity_Id
    WHERE su.IsDeleted = 0
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
		r.LiqDate,
		r.Employees
	FROM ResultTableCTE AS r
		LEFT JOIN ActivityCategoriesTotalHierarchyCTE ac1 ON ac1.Id = r.ActivityCategoryId
		LEFT JOIN ActivityCategoriesHierarchyCTE AS ac2 ON ac2.Id = r.ActivityCategoryId
		LEFT JOIN dbo.Address AS addr ON addr.Address_id = r.AddressId
		INNER JOIN RegionsHierarchyCTE AS tr ON tr.Id = addr.Region_id
	WHERE DATEPART(YEAR, r.RegistrationDate) = @InPreviousYear AND Employees IS NOT NULL
			AND (@InStatUnitType ='All' OR (isHistory = 0 AND  r.Discriminator = @InStatUnitType) 
					OR (isHistory = 1 AND r.Discriminator = @InStatUnitType + 'History'))
			AND r.ActivityType = 1
),
ActivityCategoriesOrder AS (
	SELECT
		ac.Id,
		ROW_NUMBER() over (order BY ac.Name asc) AS OrderId
	FROM dbo.ActivityCategories AS ac
	WHERE ac.ActivityCategoryLevel = 1
)
/* 
	filling temporary table by all ActivityCategories with level 1 and 2,
	and number of employees in new stat units from ResultTableCTE linked to them 
*/
INSERT INTO #tempTableForPivot
/* inserting values for ActivityCategories with level = 1 */
SELECT 
	SUM(Employees) AS Count,
	aco.OrderId AS ActivityParentId,
	ac.Name AS ActivityCategoryName,
	'' AS ActivitySubCategoryName,
	rt.RegionParentName as NameOblast
FROM dbo.ActivityCategories as ac
	INNER JOIN ActivityCategoriesOrder AS aco ON aco.Id = ac.Id
	LEFT JOIN ResultTableCTE2 AS rt ON ac.Id = rt.ActivityCategoryId1
WHERE ac.ActivityCategoryLevel = 1
GROUP BY ac.Name, rt.RegionParentName, aco.OrderId

UNION
/* inserting values for ActivityCategories with level = 2 */
SELECT 
	SUM(Employees) AS Count,
	aco.OrderId AS ActivityParentId,
	'' AS ActivityCategoryName,
	ac.Name AS Name2,
	rt.RegionParentName as NameOblast
FROM dbo.ActivityCategories as ac
	INNER JOIN ActivityCategoriesOrder AS aco ON aco.Id = ac.ParentId
	LEFT JOIN ResultTableCTE2 AS rt ON ac.Id = rt.ActivityCategoryId2
WHERE ac.ActivityCategoryLevel = 2
GROUP BY ac.Name, rt.RegionParentName, aco.OrderId

/*
	list of regions with level=2, that will be columns in report
	for select statement with replacing NULL values with zeroes
*/
DECLARE @colswithISNULL as NVARCHAR(MAX) = dbo.GetOblastColumnNamesWithNullCheck();

/* total sum of values for select statement */
DECLARE @total AS NVARCHAR(MAX) = dbo.CountTotalEmployeesInOblastsAsSql();
DECLARE @cols  AS NVARCHAR(MAX) = dbo.GetOblastColumnNames();
/* perform pivot on list of number of employees transforming names of regions to columns and summarizing number of employees for ActivityCategories */
DECLARE @query AS NVARCHAR(MAX) = '
SELECT ActivityCategoryName, ActivitySubCategoryName, ' + @total + ' as Total, ' + @colswithISNULL + ' from 
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
                FOR NameOblast IN (' + @cols + ')
            ) PivotTable order by ActivityParentId, ActivitySubCategoryName'

execute(@query)
