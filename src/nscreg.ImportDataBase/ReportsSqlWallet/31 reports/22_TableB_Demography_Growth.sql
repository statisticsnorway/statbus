BEGIN /*INPUT PARAMETERS*/
	DECLARE @InRegionId INT = '2',
			    @InStatUnitType NVARCHAR(MAX) = 'LegalUnit',
    		  @InStatusId NVARCHAR(MAX) = '1',
          @InCurrentYear NVARCHAR(MAX) = YEAR(GETDATE()),
		      @InPreviousYear NVARCHAR(MAX) = YEAR(GETDATE()) - 1
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
	DATEPART(YEAR,suh.StartPeriod)>=@InPreviousYear AND DATEPART(YEAR,suh.StartPeriod)<@InCurrentYear AND ah.Activity_Type = 1
),
ResultTableCTE AS
(
	SELECT 
		su.RegId,
		a.Activity_Type,
		IIF(DATEPART(YEAR,su.RegistrationDate)>=@InPreviousYear AND DATEPART(YEAR, su.RegistrationDate)<@InCurrentYear AND DATEPART(YEAR,su.StartPeriod)>=@InPreviousYear AND DATEPART(YEAR,su.StartPeriod)<@InCurrentYear,a.ActivityCategoryId,ah.ActivityCategoryId) AS ActivityCategoryId,
		IIF(DATEPART(YEAR,su.RegistrationDate)>=@InPreviousYear AND DATEPART(YEAR, su.RegistrationDate)<@InCurrentYear AND DATEPART(YEAR,su.StartPeriod)>=@InPreviousYear AND DATEPART(YEAR,su.StartPeriod)<@InCurrentYear,su.AddressId,suhCTE.AddressId) AS AddressId,
		su.RegistrationDate,
		su.UnitStatusId,
		su.LiqDate
	FROM [dbo].[StatisticalUnits] AS su	
		LEFT JOIN dbo.ActivityStatisticalUnits asu ON asu.Unit_Id = su.RegId 
		LEFT JOIN dbo.Activities a ON a.Id = asu.Activity_Id 

		LEFT JOIN StatisticalUnitHistoryCTE suhCTE ON suhCTE.ParentId = su.RegId and suhCTE.RowNumber = 1
		LEFT JOIN dbo.ActivityStatisticalUnitHistory asuh ON asuh.Unit_Id = suhCTE.RegId
		LEFT JOIN dbo.Activities ah ON ah.Id = asuh.Activity_Id
		

	WHERE (((@InStatUnitType = 'All' OR su.Discriminator = @InStatUnitType) AND su.UnitStatusId = @InStatusId 
		 AND asu.Unit_Id IS NOT NULL
		 AND a.Activity_Type = 1)
		 OR 
		 ((@InStatUnitType = 'All' OR su.Discriminator = @InStatUnitType) AND su.UnitStatusId = @InStatusId 
		 AND asu.Unit_Id IS NOT NULL		 
		 AND a.Activity_Type = 1
		 AND DATEPART(YEAR,su.StartPeriod) = @InCurrentYear))
),
ResultTableCTE2 AS
(
	SELECT
		r.RegId,
		ac.ParentId AS ActivityCategoryId,
		r.AddressId,
		tr.RegionLevel,
		tr.Name AS RegionParentName,
		tr.ParentId AS RegionParentId,
		r.RegistrationDate,
		r.UnitStatusId,
		r.LiqDate
	FROM ResultTableCTE AS r
	LEFT JOIN ActivityCategoriesHierarchyCTE AS ac ON ac.Id = r.ActivityCategoryId
	LEFT JOIN dbo.Address AS addr ON addr.Address_id = r.AddressId
	INNER JOIN RegionsHierarchyCTE AS tr ON tr.Id = addr.Region_id	
)

INSERT INTO #tempTableForPivot
SELECT
	SUM(IIF(DATEPART(YEAR,rt.RegistrationDate) >= 2018 AND rt.UnitStatusId=1,1,0)) - SUM(IIF(rt.LiqDate IS NOT NULL AND DATEPART(YEAR,rt.LiqDate) >= 2018, 1,0)) AS Count,
	ac.Name,
	rt.RegionParentName
FROM dbo.ActivityCategories as ac
	LEFT JOIN ResultTableCTE2 AS rt ON ac.Id = rt.ActivityCategoryId
	WHERE ac.ActivityCategoryLevel = 1
	GROUP BY ac.Name, rt.RegionParentName

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
                SUM(RegId)
                FOR NameOblast IN (' + dbo.GetNamesRegionsForPivot(@InRegionId,'FORINPIVOT', 1) + ')
            ) PivotTable			
			'
execute(@query)
