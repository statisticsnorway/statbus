BEGIN /* INPUT PARAMETERS from report body */
	DECLARE @InStatUnitType NVARCHAR(MAX) = $StatUnitType,
			@InCurrentYear NVARCHAR(MAX) = YEAR(GETDATE()),
			@InPreviousYear NVARCHAR(MAX) = YEAR(GETDATE()) - 1	
END

/* checking if temporary table exists and deleting it if it is true */
IF (OBJECT_ID('tempdb..#tempTableForPivot') IS NOT NULL)
BEGIN DROP TABLE #tempTableForPivot END

/* 
	list of stat units that satisfy necessary requirements 
	with their Id and name of ActivityCategory with level = 1,
	name of ActivityCategory with level = 2,
	and name of oblast(region with level = 2(for kyrgyz database))
*/
CREATE TABLE #tempTableForPivot
(
	RegId INT NULL,
	ActivityParentId INT NULL,
	ActivityCategoryName NVARCHAR(MAX) NULL,
	ActivitySubCategoryName NVARCHAR(MAX) NULL,
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
		UnitStatusId,
		Discriminator,
		ROW_NUMBER() over (partition by ParentId order by StartPeriod desc) AS RowNumber
	FROM StatisticalUnitHistory
	WHERE DATEPART(YEAR,RegistrationDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1 AND DATEPART(YEAR,StartPeriod) BETWEEN @InPreviousYear AND @InCurrentYear - 1
),
/* list with all stat units linked to their primary ActivityCategory that were active in given dateperiod and have required StatUnitType */
ResultTableCTE AS
(
	SELECT
		IIF(DATEPART(YEAR,su.RegistrationDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1 AND DATEPART(YEAR,su.StartPeriod) BETWEEN @InPreviousYear AND @InCurrentYear - 1,su.RegId, asuhCTE.RegId) AS RegId,
		IIF(DATEPART(YEAR,su.RegistrationDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1 AND DATEPART(YEAR,su.StartPeriod) BETWEEN @InPreviousYear AND @InCurrentYear - 1,ac1.ParentId,ach1.ParentId) AS ActivityCategoryId1,
		IIF(DATEPART(YEAR,su.RegistrationDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1 AND DATEPART(YEAR,su.StartPeriod) BETWEEN @InPreviousYear AND @InCurrentYear - 1,ac2.ParentId,ach2.ParentId) AS ActivityCategoryId2,
		IIF(DATEPART(YEAR,su.RegistrationDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1 AND DATEPART(YEAR,su.StartPeriod) BETWEEN @InPreviousYear AND @InCurrentYear - 1,su.AddressId,asuhCTE.AddressId) AS AddressId,
		IIF(DATEPART(YEAR,su.RegistrationDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1 AND DATEPART(YEAR,su.StartPeriod) BETWEEN @InPreviousYear AND @InCurrentYear - 1,su.UnitStatusId,asuhCTE.UnitStatusId) AS UnitStatusId,
		IIF(DATEPART(YEAR,su.RegistrationDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1 AND DATEPART(YEAR,su.StartPeriod) BETWEEN @InPreviousYear AND @InCurrentYear - 1,su.Discriminator,asuhCTE.Discriminator) AS Discriminator,
		IIF(DATEPART(YEAR,su.RegistrationDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1 AND DATEPART(YEAR,su.StartPeriod) BETWEEN @InPreviousYear AND @InCurrentYear - 1,a.Activity_Type,ah.Activity_Type) AS ActivityType,
		IIF(DATEPART(YEAR,su.RegistrationDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1 AND DATEPART(YEAR,su.StartPeriod) BETWEEN @InPreviousYear AND @InCurrentYear - 1,0,1) AS isHistory
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
    WHERE su.IsDeleted = 0
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
		LEFT JOIN dbo.Statuses AS st ON st.Id = rt.UnitStatusId
		INNER JOIN RegionsHierarchyCTE AS tr ON tr.Id = addr.Region_id
	WHERE (@InStatUnitType ='All' OR (isHistory = 0 AND  rt.Discriminator = @InStatUnitType) 
				OR (isHistory = 1 AND rt.Discriminator = @InStatUnitType + 'History'))
			AND st.Code IN (1,3,4)
			AND rt.ActivityType = 1
),
ActivityCategoriesOrder AS (
	SELECT
		ac.Id,
		ROW_NUMBER() over (order BY ac.Name asc) AS OrderId
	FROM dbo.ActivityCategories AS ac
	WHERE ac.ActivityCategoryLevel = 1
)

/* filling temporary table by all ActivityCategories with level 1 and 2, oblasts and stat units from ResultTableCTE linked to them */
INSERT INTO #tempTableForPivot
/* inserting values for ActivityCategories with level = 1 */
SELECT 
	rt.RegId,
	aco.OrderId AS ActivityParentId,
	ac.Name AS ActivityCategoryName,
	'' AS ActivitySubCategoryName,
	rt.NameOblast
FROM dbo.ActivityCategories as ac
	INNER JOIN ActivityCategoriesOrder AS aco ON aco.Id = ac.Id
	LEFT JOIN ResultTableCTE2 AS rt ON ac.Id = rt.ActivityCategoryId1
WHERE ac.ActivityCategoryLevel = 1

UNION 
/* inserting values for ActivityCategories with level = 2 */
SELECT 
	rt.RegId,
	aco.OrderId AS ActivityParentId,
	'' AS ActivityCategoryName,
	ac.Name AS ActivitySubCategoryName,
	rt.NameOblast
FROM dbo.ActivityCategories as ac
	INNER JOIN ActivityCategoriesOrder AS aco ON aco.Id = ac.ParentId
	LEFT JOIN ResultTableCTE2 AS rt ON ac.Id = rt.ActivityCategoryId2
WHERE ac.ActivityCategoryLevel = 2

/* perform pivot on list of stat units transforming names of regions to columns and counting stat units for ActivityCategories with both levels 1 and 2 */
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

execute(@query)
