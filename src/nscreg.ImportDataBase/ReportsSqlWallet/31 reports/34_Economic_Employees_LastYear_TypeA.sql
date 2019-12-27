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
		DesiredLevel = 2 OR Id = 1 AND DesiredLevel  = 1
		To:
		DesiredLevel = 1
	*/
	WHERE DesiredLevel = 2 OR Id = 1 AND DesiredLevel  = 1
),
/* table with needed fields for previous states of stat units that were active in given dateperiod */
StatisticalUnitHistoryCTE AS (
	SELECT
		RegId,
		ParentId,	
		AddressId,
		Employees,
		ROW_NUMBER() over (partition by ParentId order by StartPeriod desc) AS RowNumber
	FROM StatisticalUnitHistory
	WHERE DATEPART(YEAR,RegistrationDate) = @InPreviousYear AND DATEPART(YEAR,StartPeriod) = @InPreviousYear
),
/* list with all stat units linked to their primary ActivityCategory that were active in given dateperiod and have required StatUnitType */
ResultTableCTE AS
(
	SELECT
		su.RegId as RegId,
		IIF(DATEPART(YEAR,su.RegistrationDate) = @InPreviousYear AND DATEPART(YEAR,su.StartPeriod) = @InPreviousYear,a.ActivityCategoryId,ah.ActivityCategoryId) AS ActivityCategoryId,
		IIF(DATEPART(YEAR,su.RegistrationDate) = @InPreviousYear AND DATEPART(YEAR,su.StartPeriod) = @InPreviousYear,su.AddressId,suhCTE.AddressId) AS AddressId,
		IIF(DATEPART(YEAR,su.RegistrationDate) = @InPreviousYear AND DATEPART(YEAR,su.StartPeriod) = @InPreviousYear,su.Employees,suhCTE.Employees) AS Employees,
		su.RegistrationDate,
		su.UnitStatusId,
		su.LiqDate
	FROM dbo.StatisticalUnits AS su	
		LEFT JOIN dbo.ActivityStatisticalUnits asu ON asu.Unit_Id = su.RegId
		LEFT JOIN dbo.Activities a ON a.Id = asu.Activity_Id

		LEFT JOIN StatisticalUnitHistoryCTE suhCTE ON suhCTE.ParentId = su.RegId and suhCTE.RowNumber = 1
		LEFT JOIN dbo.ActivityStatisticalUnitHistory asuh ON asuh.Unit_Id = suhCTE.RegId
		LEFT JOIN dbo.Activities ah ON ah.Id = asuh.Activity_Id
	WHERE (@InStatUnitType ='All' OR su.Discriminator = @InStatUnitType) AND (@InStatusId = 0 OR su.UnitStatusId = @InStatusId) 
			AND a.Activity_Type = 1
),
/* list of stat units linked to their oblast(region with level = 2) */
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
		r.LiqDate,
		r.Employees
	FROM ResultTableCTE AS r
	LEFT JOIN ActivityCategoriesHierarchyCTE AS ac ON ac.Id = r.ActivityCategoryId
	LEFT JOIN dbo.Address AS addr ON addr.Address_id = r.AddressId
	INNER JOIN RegionsHierarchyCTE AS tr ON tr.Id = addr.Region_id
	WHERE DATEPART(YEAR, r.RegistrationDate) = @InPreviousYear AND Employees IS NOT NULL
)

/* filling temporary table by all ActivityCategories with level=1 and number of employees in new stat units from ResultTableCTE linked to them */
INSERT INTO #tempTableForPivot
SELECT 
	SUM(Employees) AS Count,
	ac.Name,
	rt.RegionParentName as NameOblast
FROM dbo.ActivityCategories as ac
	LEFT JOIN ResultTableCTE2 AS rt ON ac.Id = rt.ActivityCategoryId
WHERE ac.ActivityCategoryLevel = 1
GROUP BY ac.Name, rt.RegionParentName

/*
	list of regions with level=2, that will be columns in report
	for select statement with replacing NULL values with zeroes
*/
DECLARE @colswithISNULL as NVARCHAR(MAX) = STUFF((SELECT distinct ', ISNULL(' + QUOTENAME(Name) + ', 0)  AS ' + QUOTENAME(Name)
				/* set re.RegionLevel = 1 if there is no Country level at Regions tree */
				FROM dbo.Regions  WHERE RegionLevel = 2
				FOR XML PATH(''), TYPE
				).value('.', 'NVARCHAR(MAX)')
			,1,2,'');

/* total sum of values for select statement */
DECLARE @total AS NVARCHAR(MAX) = STUFF((SELECT distinct '+ISNULL(' + QUOTENAME(Name) + ', 0)'
				/* set re.RegionLevel = 1 if there is no Country level at Regions tree (without condition Id = 1) */
				FROM dbo.Regions  WHERE RegionLevel = 2 OR Id = 1
				FOR XML PATH(''), TYPE
				).value('.', 'NVARCHAR(MAX)')
			,1,1,'')

/* perform pivot on list of number of employees transforming names of regions to columns and summarizing number of employees for ActivityCategories */
DECLARE @query AS NVARCHAR(MAX) = '
SELECT Name, ' + @total + ' as Total, ' + @colswithISNULL + ' from 
            (
				SELECT 
					Count,
					Name,
					NameOblast
				FROM #tempTableForPivot
           ) SourceTable
            PIVOT 
            (
                SUM(Count)
                FOR NameOblast IN (' + dbo.GetNamesRegionsForPivot(1,'FORINPIVOT',1) + ')
            ) PivotTable order by Name'

execute(@query)