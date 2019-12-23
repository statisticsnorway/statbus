BEGIN /* INPUT PARAMETERS from report body */
	DECLARE @InStatusId NVARCHAR(MAX) = $StatusId,
			@InStatUnitType NVARCHAR(MAX) = $StatUnitType,
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
	WHERE DesiredLevel = 2 OR Id = 1 AND DesiredLevel  = 1
),
/* table with needed fields for previous states of stat units that were active in given dateperiod */
StatisticalUnitHistoryCTE AS (
	SELECT
		RegId,
		ParentId,	
		AddressId,
		ROW_NUMBER() over (partition by ParentId order by StartPeriod desc) AS RowNumber
	FROM StatisticalUnitHistory
	WHERE DATEPART(YEAR,RegistrationDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1 AND DATEPART(YEAR,StartPeriod)<@InCurrentYear
),
/* list with all stat units linked to their primary ActivityCategory that were active in given dateperiod and have required StatUnitType */
ResultTableCTE AS
(
	SELECT
		su.RegId as RegId,
		IIF(DATEPART(YEAR, su.RegistrationDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1 AND DATEPART(YEAR,su.StartPeriod)<@InCurrentYear,tr.Name,trh.Name) AS NameOblast,
		IIF(DATEPART(YEAR, su.RegistrationDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1 AND DATEPART(YEAR,su.StartPeriod)<@InCurrentYear,ac1.ParentId,ach1.ParentId) AS ActivityCategoryId1,
		IIF(DATEPART(YEAR, su.RegistrationDate) BETWEEN @InPreviousYear AND @InCurrentYear - 1 AND DATEPART(YEAR,su.StartPeriod)<@InCurrentYear,ac2.ParentId,ach2.ParentId) AS ActivityCategoryId2
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

/* filling temporary table by all ActivityCategories with level 1 and 2, oblasts and stat units from ResultTableCTE linked to them */
INSERT INTO #tempTableForPivot
/* inserting values for ActivityCategories with level = 1 */
SELECT 
	rt.RegId,
	ac.Id AS ActivityParentId,
	ac.Name AS ActivityCategoryName,
	'' AS ActivitySubCategoryName,
	rt.NameOblast
FROM dbo.ActivityCategories as ac
	LEFT JOIN ResultTableCTE AS rt ON ac.Id = rt.ActivityCategoryId1
	WHERE ac.ActivityCategoryLevel = 1

UNION 
/* inserting values for ActivityCategories with level = 2 */
SELECT 
	rt.RegId,
	ac.ParentId AS ActivityParentId,
	'' AS ActivityCategoryName,
	ac.Name AS ActivitySubCategoryName,
	rt.NameOblast
FROM dbo.ActivityCategories as ac
	LEFT JOIN ResultTableCTE AS rt ON ac.Id = rt.ActivityCategoryId2
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