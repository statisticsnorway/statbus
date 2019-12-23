BEGIN /* INPUT PARAMETERS from report body */
	DECLARE @InRegionId INT = $RegionId,
			@InStatUnitType NVARCHAR(MAX) = $StatUnitType,
			@InStatusId NVARCHAR(MAX) = $StatusId,
			@InCurrentYear NVARCHAR(MAX) = YEAR(GETDATE()),
			@InPreviousYear NVARCHAR(MAX) = YEAR(GETDATE()) - 1
END

/* name of oblast with Id = @InRegionId */
DECLARE @nameTotalColumn AS NVARCHAR(MAX) = (SELECT TOP 1 Name FROM dbo.Regions WHERE Id = @InRegionId)

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
/* table where regions linked to their ancestor - rayon(region with level = 3) and region with Id = @InRegionId(level = 2) linked to itself */
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
		DesiredLevel = 3 OR Id = @InRegionId AND DesiredLevel = 2
		To:
		DesiredLevel = 2 OR Id = @InRegionId AND DesiredLevel = 1
	*/
	WHERE DesiredLevel = 3 OR Id = @InRegionId AND DesiredLevel = 2
),
/* table with needed fields for previous states of stat units that were active in given dateperiod */
StatisticalUnitHistoryCTE AS (
	SELECT
		suh.RegId,
		suh.ParentId,
		ach.ParentId as achParentId,
		ach.Name as acchName,
		trh.Name as trhParentName,
		suh.AddressId,
		suh.UnitStatusId,
		ROW_NUMBER() over (partition by suh.ParentId order by suh.StartPeriod desc) AS RowNumber
	FROM dbo.StatisticalUnitHistory as suh
		LEFT JOIN dbo.ActivityStatisticalUnitHistory asuh ON asuh.Unit_Id = suh.RegId
		LEFT JOIN dbo.Activities ah ON ah.Id = asuh.Activity_Id
		LEFT JOIN ActivityCategoriesHierarchyCTE AS ach ON ach.Id = ah.ActivityCategoryId
		LEFT JOIN dbo.Address AS addrh ON addrh.Address_id = suh.AddressId
		LEFT JOIN RegionsHierarchyCTE as trh ON trh.Id = addrh.Region_id
	WHERE 
	DATEPART(YEAR,suh.StartPeriod)>=@InPreviousYear AND DATEPART(YEAR,suh.StartPeriod)<@InCurrentYear AND ah.Activity_Type = 1
),

/* list with all stat units linked to their primary ActivityCategory that were active in given dateperiod and have required StatUnitType */
ResultTableCTE AS
(
	SELECT 
		su.RegId,
		su.StatId,		
		suh.RegId as hRegId,
		a.Activity_Type,
		IIF(DATEPART(YEAR,su.RegistrationDate)>=@InPreviousYear AND DATEPART(YEAR, su.RegistrationDate)<@InCurrentYear AND DATEPART(YEAR,su.StartPeriod)>=@InPreviousYear AND DATEPART(YEAR,su.StartPeriod)<@InCurrentYear,acc.Name,suh.acchName) AS Name,
		IIF(DATEPART(YEAR,su.RegistrationDate)>=@InPreviousYear AND DATEPART(YEAR, su.RegistrationDate)<@InCurrentYear AND DATEPART(YEAR,su.StartPeriod)>=@InPreviousYear AND DATEPART(YEAR,su.StartPeriod)<@InCurrentYear,acc.ParentId,suh.achParentId) AS ActivityCategoryId,
		IIF(DATEPART(YEAR,su.RegistrationDate)>=@InPreviousYear AND DATEPART(YEAR, su.RegistrationDate)<@InCurrentYear AND DATEPART(YEAR,su.StartPeriod)>=@InPreviousYear AND DATEPART(YEAR,su.StartPeriod)<@InCurrentYear,tr.Name,suh.trhParentName) AS NameOblast
	FROM [dbo].[StatisticalUnits] AS su	
		LEFT JOIN dbo.ActivityStatisticalUnits asu ON asu.Unit_Id = su.RegId 
		LEFT JOIN dbo.Activities a ON a.Id = asu.Activity_Id 
		LEFT JOIN dbo.ActivityCategories AS ac ON ac.Id = a.ActivityCategoryId
		LEFT JOIN ActivityCategoriesHierarchyCTE acc ON ac.ParentId = acc.Id
		LEFT JOIN dbo.Address addr ON addr.Address_id = su.AddressId
		LEFT JOIN RegionsHierarchyCTE as tr ON tr.Id = addr.Region_id
		LEFT JOIN StatisticalUnitHistoryCTE suh ON suh.ParentId = su.RegId

	WHERE (((@InStatUnitType = 'All' OR su.Discriminator = @InStatUnitType) AND su.UnitStatusId = @InStatusId 
		 AND asu.Unit_Id IS NOT NULL
		 AND a.Activity_Type = 1)
		 OR 
		 ((@InStatUnitType = 'All' OR su.Discriminator = @InStatUnitType) AND su.UnitStatusId = @InStatusId 
		 AND asu.Unit_Id IS NOT NULL		 
		 AND a.Activity_Type = 1
		 AND DATEPART(YEAR,su.StartPeriod) = @InCurrentYear))
)

/* filling temporary table by all ActivityCategories with level=1 and stat units from ResultTableCTE linked to them */
INSERT INTO #tempTableForPivot
SELECT
	rt.RegId,
	ac.Name,
	rt.NameOblast
FROM dbo.ActivityCategories as ac
	LEFT JOIN ResultTableCTE AS rt ON ac.Id = rt.ActivityCategoryId
WHERE ac.ActivityCategoryLevel = 1

/* perform pivot on list of stat units transforming names of regions to columns and counting stat units for ActivityCategories */
DECLARE @query AS NVARCHAR(MAX) = '
SELECT 
	Name, ' + dbo.GetNamesRegionsForPivot(@InRegionId,'TOTAL',1) + ' as [' + @nameTotalColumn+ '], ' + dbo.GetNamesRegionsForPivot(@InRegionId,'SELECT', 0) + ' from 
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
                FOR NameOblast IN (' + dbo.GetNamesRegionsForPivot(@InRegionId,'FORINPIVOT', 1) + ')
            ) PivotTable			
			'

execute(@query)