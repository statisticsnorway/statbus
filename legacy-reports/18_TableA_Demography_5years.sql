BEGIN /* INPUT PARAMETERS */
	DECLARE @InStatusId NVARCHAR(MAX) = $StatusId,
			@InStatUnitType NVARCHAR(MAX) = $StatUnitType,
			@InCurrentYear NVARCHAR(MAX) = YEAR(GETDATE()),
			@InPreviousYear NVARCHAR(MAX) = YEAR(GETDATE()) - 5
			
			
END

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
	WHERE DesiredLevel = 2 OR Id = 1 AND DesiredLevel  = 1
),
StatisticalUnitHistoryCTE AS (
	SELECT
		RegId,
		ParentId,	
		AddressId,
		ROW_NUMBER() over (partition by ParentId order by StartPeriod desc) AS RowNumber
	FROM StatisticalUnitHistory
	WHERE DATEPART(YEAR,RegistrationDate)>=@InPreviousYear AND DATEPART(YEAR, RegistrationDate)<@InCurrentYear AND DATEPART(YEAR,StartPeriod)<@InCurrentYear
),
ResultTableCTE AS
(
	SELECT
		su.RegId as RegId,
		IIF(DATEPART(YEAR, su.RegistrationDate)<@InCurrentYear AND DATEPART(YEAR, su.RegistrationDate)>=@InPreviousYear AND DATEPART(YEAR,su.StartPeriod)<@InCurrentYear,ac.Name,ach.Name) AS Name,
		IIF(DATEPART(YEAR, su.RegistrationDate)<@InCurrentYear AND DATEPART(YEAR, su.RegistrationDate)>=@InPreviousYear AND DATEPART(YEAR,su.StartPeriod)<@InCurrentYear,tr.Name,trh.Name) AS NameOblast,
		IIF(DATEPART(YEAR, su.RegistrationDate)<@InCurrentYear AND DATEPART(YEAR, su.RegistrationDate)>=@InPreviousYear AND DATEPART(YEAR,su.StartPeriod)<@InCurrentYear,ac.ParentId,ach.ParentId) AS ActivityCategoryId
	FROM StatisticalUnits AS su	
		LEFT JOIN ActivityStatisticalUnits asu ON asu.Unit_Id = su.RegId
		LEFT JOIN Activities a ON a.Id = asu.Activity_Id
		LEFT JOIN ActivityCategoriesHierarchyCTE AS ac ON ac.Id = a.ActivityCategoryId
		LEFT JOIN dbo.Address AS addr ON addr.Address_id = su.AddressId
		INNER JOIN RegionsHierarchyCTE AS tr ON tr.Id = addr.Region_id

		LEFT JOIN StatisticalUnitHistoryCTE asuhCTE ON asuhCTE.ParentId = su.RegId and asuhCTE.RowNumber = 1
		LEFT JOIN ActivityStatisticalUnitHistory asuh ON asuh.Unit_Id = asuhCTE.RegId
		LEFT JOIN Activities ah ON ah.Id = asuh.Activity_Id
		LEFT JOIN ActivityCategoriesHierarchyCTE AS ach ON ach.Id = ah.ActivityCategoryId
		LEFT JOIN dbo.Address AS addrh ON addrh.Address_id = asuhCTE.AddressId
		LEFT JOIN RegionsHierarchyCTE AS trh ON trh.Id = addrh.Region_id
	WHERE (@InStatUnitType ='All' OR su.Discriminator = @InStatUnitType) AND su.UnitStatusId = @InStatusId
  AND a.Activity_Type = 1
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
	SELECT Name, ' + dbo.GetNamesRegionsForPivot(1,'FORINPIVOT',0) + ', ' + dbo.[GetNamesRegionsForPivot](1, 'TOTAL',1) + ' as Total from 
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
