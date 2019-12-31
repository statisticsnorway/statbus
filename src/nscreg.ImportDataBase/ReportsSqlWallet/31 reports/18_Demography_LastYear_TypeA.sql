BEGIN /* INPUT PARAMETERS from report body */
	DECLARE @InStatusId NVARCHAR(MAX) = $StatusId,
			@InStatUnitType NVARCHAR(MAX) = $StatUnitType,
			@InCurrentYear NVARCHAR(MAX) = YEAR(GETDATE()),
			@InPreviousYear NVARCHAR(MAX) = YEAR(GETDATE()) - 1
END

/* checking if temporary table exists and deleting it if it is true */
IF (OBJECT_ID('tempdb..#tempTableForPivot') IS NOT NULL)
BEGIN DROP TABLE #tempTableForPivot END

/* list of stat units that satisfy necessary requirements with their ActivityCategory name and name of oblast */
CREATE TABLE #tempTableForPivot
(
	RegId INT NULL,
	Name NVARCHAR(MAX) NULL,
	NameOblast NVARCHAR(MAX) NULL
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
	WHERE DATEPART(YEAR,StartPeriod)>=@InPreviousYear AND DATEPART(YEAR,StartPeriod)<@InCurrentYear
),
/* list with all stat units linked to their primary ActivityCategory that were active in given dateperiod and have required StatUnitType */
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
),
ResultTableCTE2 AS
(
	SELECT
		RegId,
		tr.Name AS NameOblast,
		rt.ActivityCategoryId
	FROM ResultTableCTE AS rt
		LEFT JOIN dbo.Address AS addr ON addr.Address_id = rt.AddressId
		INNER JOIN RegionsHierarchyCTE AS tr ON tr.Id = addr.Region_id
	WHERE (@InStatUnitType ='All' OR (isHistory = 0 AND  rt.Discriminator = @InStatUnitType) 
				OR (isHistory = 1 AND rt.Discriminator = @InStatUnitType + 'History'))
			AND (@InStatusId = 0 OR rt.UnitStatusId = @InStatusId)
			AND rt.ActivityType = 1
)

/* filling temporary table by all ActivityCategories with level=1 and stat units from ResultTableCTE linked to them */
INSERT INTO #tempTableForPivot
SELECT 
	rt.RegId,
	ac.Name,
	rt.NameOblast
FROM dbo.ActivityCategories as ac
	LEFT JOIN ResultTableCTE2 AS rt ON ac.Id = rt.ActivityCategoryId
WHERE ac.ActivityCategoryLevel = 1

/* perform pivot on list of stat units transforming names of regions to columns and counting stat units for ActivityCategories */
DECLARE @query AS NVARCHAR(MAX) = '
SELECT Name, ' + dbo.[GetNamesRegionsForPivot](1, 'TOTAL',1) + ' as Total, ' + dbo.GetNamesRegionsForPivot(1,'FORINPIVOT',0) + ' from 
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
                FOR NameOblast IN (' + dbo.GetNamesRegionsForPivot(1,'FORINPIVOT',1) + ')
            ) PivotTable order by Name'

execute(@query)