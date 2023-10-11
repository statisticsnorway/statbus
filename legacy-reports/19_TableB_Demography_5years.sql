BEGIN /*INPUT PARAMETERS*/
	DECLARE @InRegionId INT = $StatusId,
			@InStatUnitType NVARCHAR(MAX) = $StatUnitType,
    		@InStatusId NVARCHAR(MAX) = $StatusId,
			@InCurrentYear NVARCHAR(MAX) = YEAR(GETDATE()),
			@InPreviousYear NVARCHAR(MAX) = YEAR(GETDATE()) - 5
END

DECLARE @nameTotalColumn AS NVARCHAR(MAX) = (SELECT TOP 1 Name FROM dbo.Regions WHERE Id = @InRegionId)

IF (OBJECT_ID('tempdb..#tempTableForPivot') IS NOT NULL)
BEGIN DROP TABLE #tempTableForPivot END

CREATE TABLE #tempTableForPivot
(
	RegId INT NULL,
	Name NVARCHAR(MAX) NULL,
	NameOblast NVARCHAR(MAX) NULL
)
;WITH ActivityCategoriesHierarchyCTE(Id,ParentId,Name,DesiredLevel) AS(
	SELECT 
		Id,
		ParentId,
		Name,
		DesiredLevel
	FROM v_ActivityCategoriesHierarchy 
	WHERE DesiredLevel=1
),
RegionsHierarchyCTE AS(
	SELECT 
		Id,
		ParentId,
		Name,
		RegionLevel,
		DesiredLevel
	FROM v_Regions
	WHERE DesiredLevel = 3 OR Id = @InRegionId AND DesiredLevel  = 2
),
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
	DATEPART(YEAR,RegistrationDate)>=@InPreviousYear AND DATEPART(YEAR, RegistrationDate)<@InCurrentYear AND DATEPART(YEAR,suh.StartPeriod)<@InCurrentYear AND ah.Activity_Type = 1
),
ResultTableCTE AS
(
	SELECT 
		su.RegId,
		su.StatId,		
		suh.RegId as hRegId,
		a.Activity_Type,
		IIF(DATEPART(YEAR, su.RegistrationDate)<@InCurrentYear AND DATEPART(YEAR, su.RegistrationDate)>=@InPreviousYear AND DATEPART(YEAR,su.StartPeriod)<@InCurrentYear,acc.Name,suh.acchName) AS Name,
		IIF(DATEPART(YEAR, su.RegistrationDate)<@InCurrentYear AND DATEPART(YEAR, su.RegistrationDate)>=@InPreviousYear AND DATEPART(YEAR,su.StartPeriod)<@InCurrentYear,acc.ParentId,suh.achParentId) AS ActivityCategoryId,
		IIF(DATEPART(YEAR, su.RegistrationDate)<@InCurrentYear AND DATEPART(YEAR, su.RegistrationDate)>=@InPreviousYear AND DATEPART(YEAR,su.StartPeriod)<@InCurrentYear,tr.Name,suh.trhParentName) AS NameOblast
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
INSERT INTO #tempTableForPivot
SELECT
	rt.RegId,
	ac.Name,
	rt.NameOblast
FROM dbo.ActivityCategories as ac
	LEFT JOIN ResultTableCTE AS rt ON ac.Id = rt.ActivityCategoryId
	WHERE ac.ActivityCategoryLevel = 1

DECLARE @query AS NVARCHAR(MAX) = '
SELECT 
	Name, ' + dbo.GetNamesRegionsForPivot(@InRegionId,'SELECT', 0) + ', ' + dbo.GetNamesRegionsForPivot(@InRegionId,'TOTAL',1) + ' as [' + @nameTotalColumn+ '] from 
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
