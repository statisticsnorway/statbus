/*
	RegionLevel:
		1 : Kyrgyz Republic
		2 : Area
		3 : Region
		4 : City / Village
*/

BEGIN /* INPUT PARAMETERS from report body */
	DECLARE @InStatusId NVARCHAR(MAX) = $StatusId ,
			    @InStatUnitType NVARCHAR(MAX) = $StatUnitType,
          @InCurrentYear NVARCHAR(MAX) = YEAR(GETDATE())
END
BEGIN /* DECLARE variables */
DECLARE @cols AS NVARCHAR(MAX),
        @selCols AS NVARCHAR(MAX),
        @query  AS NVARCHAR(MAX),
        @totalSumCols AS NVARCHAR(MAX),
        @activityCategoryLevel AS NVARCHAR(MAX),
        @regionLevel AS NVARCHAR(MAX)
SET @cols = STUFF((SELECT distinct ',' + QUOTENAME(r.Name)
            FROM Regions r  WHERE RegionLevel IN (1,2)
            FOR XML PATH(''), TYPE
            ).value('.', 'NVARCHAR(MAX)')
        ,1,1,'') /* COLUMNS VARIABLES - REGIONS, COUNTRY LEVEL */
SET @selCols = STUFF((SELECT distinct ',' + QUOTENAME(r.Name)
            FROM Regions r  WHERE RegionLevel = 2
            FOR XML PATH(''), TYPE
            ).value('.', 'NVARCHAR(MAX)')
        ,1,1,'') /* COLUMNS VARIABLES - REGIONS, OBLASTS LEVEL */
SET @totalSumCols = STUFF((SELECT distinct '+' + QUOTENAME(r.Name)
            FROM Regions r  WHERE RegionLevel IN (1,2)
            FOR XML PATH(''), TYPE
            ).value('.', 'NVARCHAR(MAX)')
        ,1,1,'')
SET @activityCategoryLevel = 1
SET @regionLevel = 2 /* SET THIS TO 1 if database has no Country level and begins from the Oblasts/Counties/Regions */
END
BEGIN /* DECLARE and FILL Hierarchy Of Activity Categories - Complect the Activity Category tree */
IF (OBJECT_ID('tempdb..#tempActivityCategories') IS NOT NULL)
BEGIN DROP TABLE #tempActivityCategories END /* Delete temporary table for Activity Categories if exists */
CREATE TABLE #tempActivityCategories /* Create new temporary table for Activity Categories */
(
    ID INT,
    Level INT,
    ParentId INT,
    Name NVARCHAR(MAX)
);
/* Create an index "ix_tempActivityCategoriesIndex" - to make search faster - Activity Categories */
CREATE NONCLUSTERED INDEX ix_tempActivityCategoriesIndex ON #tempActivityCategories ([ID]); 
/* using CTE (Common Table Expressions), revursively collect the Activity Categories tree */
;WITH ActivityCategoriesCTE AS (
	SELECT
		Id, 0 AS Level, CAST(Id AS VARCHAR(255)) AS ParentId
	FROM ActivityCategories 

	UNION ALL

	SELECT 
		i.Id, Level + 1, CAST(itms.ParentId AS VARCHAR(255))
	FROM ActivityCategories i
	INNER JOIN ActivityCategoriesCTE itms ON itms.Id = i.ParentId
),

/* Select all levels from Activity Categories and order them */
CTE_RN AS 
(
    SELECT Id,Level,ParentId, ROW_NUMBER() OVER (PARTITION BY r.Id ORDER BY r.Level DESC) RN
    FROM ActivityCategoriesCTE r
)

/* Fill the temporary table */
INSERT INTO #tempActivityCategories
SELECT r.Id, r.RN, r.ParentId, rp.Name AS ParentName
FROM CTE_RN r
INNER JOIN ActivityCategories rp ON rp.Id = r.ParentId
INNER JOIN ActivityCategories rc ON rc.Id = r.Id
WHERE r.RN = @activityCategoryLevel

END

/* Delete temporary table if exists */
BEGIN 
IF (OBJECT_ID('tempdb..#tempRegions') IS NOT NULL)
	BEGIN DROP TABLE #tempRegions END
CREATE TABLE #tempRegions
(
    ID INT,
    Level INT,
    ParentId INT,
    Name NVARCHAR(MAX)
);
/* Create an index "ix_tempRegionsIndex" - to make search faster - Regions */
CREATE NONCLUSTERED INDEX ix_tempRegionsIndex ON #tempRegions ([ID]);
/* using CTE (Common Table Expressions), revursively collect the Regions tree */
;WITH RegionsCTE AS (
	SELECT Id, 0 AS Level, CAST(Id AS VARCHAR(255)) AS ParentId
	FROM Regions 

	UNION ALL

	SELECT i.Id, Level + 1, CAST(itms.ParentId AS VARCHAR(255))
	FROM Regions i
	INNER JOIN RegionsCTE itms ON itms.Id = i.ParentId
	WHERE i.ParentId>0
),

/* Select all levels from Regions and order them */
CTE_RN2 AS 
(
    SELECT Id,Level,ParentId, ROW_NUMBER() OVER (PARTITION BY r.Id ORDER BY r.Level DESC) RN
    FROM RegionsCTE r
    
)

/* Fill the temporary table */
INSERT INTO #tempRegions
SELECT r.Id, r.RN, r.ParentId, rp.Name AS ParentName
FROM CTE_RN2 r
	INNER JOIN Regions rp ON rp.Id = r.ParentId
	INNER JOIN Regions rc ON rc.Id = r.Id
WHERE r.RN = @regionLevel
END

/*
The resulting query 
At the first checking the history logs that have StartPeriod less than current year
and then
Activity Categories top-level select
and then
ResultTable - get the actual state of statistical units where RegistrationDate and StartPeriod less than current year
and then
Select by Activity Categories all statistical units
and then
Count statistical units using pivot transform regions - from column to row
*/
SET @query = '
;WITH StatisticalUnitHistoryCTE AS (
	SELECT
		RegId,
		ParentId,	
		AddressId,
		ROW_NUMBER() over (partition by ParentId order by StartPeriod desc) AS RowNumber
	FROM StatisticalUnitHistory
	WHERE DATEPART(YEAR,StartPeriod)<'+@InCurrentYear+'
),
ActivityCategoriesForResultCTE AS 
(
	SELECT Id,Name
	FROM dbo.ActivityCategories 
	WHERE ActivityCategoryLevel = 1
),
ResultTable AS
(
	SELECT
		su.RegId as RegId,
		IIF(DATEPART(YEAR, su.RegistrationDate)<'+@InCurrentYear+' AND DATEPART(YEAR,su.StartPeriod)<'+@InCurrentYear+',ac.Name,ach.Name) AS Name,
		IIF(DATEPART(YEAR, su.RegistrationDate)<'+@InCurrentYear+' AND DATEPART(YEAR,su.StartPeriod)<'+@InCurrentYear+',tr.Name,trh.Name) AS NameOblast,
		IIF(DATEPART(YEAR, su.RegistrationDate)<'+@InCurrentYear+' AND DATEPART(YEAR,su.StartPeriod)<'+@InCurrentYear+',ac.ParentId,ach.ParentId) AS ActivityCategoryId
	FROM StatisticalUnits AS su	
		LEFT JOIN ActivityStatisticalUnits asu ON asu.Unit_Id = su.RegId
		LEFT JOIN Activities a ON a.Id = asu.Activity_Id AND a.Activity_Type = 1
		LEFT JOIN #tempActivityCategories AS ac ON ac.Id = a.ActivityCategoryId
		LEFT JOIN dbo.Address AS addr ON addr.Address_id = su.AddressId
		INNER JOIN #tempRegions AS tr ON tr.Id = addr.Region_id

		LEFT JOIN StatisticalUnitHistoryCTE asuhCTE ON asuhCTE.ParentId = su.RegId and asuhCTE.RowNumber = 1
		LEFT JOIN ActivityStatisticalUnitHistory asuh ON asuh.Unit_Id = asuhCTE.RegId
		LEFT JOIN Activities ah ON ah.Id = asuh.Activity_Id AND ah.Activity_Type = 1 
		LEFT JOIN #tempActivityCategories AS ach ON ach.Id = ah.ActivityCategoryId
		LEFT JOIN dbo.Address AS addrh ON addrh.Address_id = asuhCTE.AddressId
		LEFT JOIN #tempRegions AS trh ON trh.Id = addrh.Region_id
	WHERE ('''+@InStatUnitType+''' = ''All'' OR su.Discriminator = '''+@InStatUnitType+''') AND su.UnitStatusId = ' + @InStatusId +'
)
SELECT Name, ' + @totalSumCols + ' as Total, ' + @selCols + ' from 
            (
				SELECT 
					rt.RegId,
					acrc.Name,
					rt.NameOblast
				FROM ActivityCategoriesForResultCTE as acrc
				LEFT JOIN ResultTable AS rt ON acrc.Id = rt.ActivityCategoryId
           ) SourceTable
            PIVOT 
            (
                COUNT(RegId)
                FOR NameOblast IN (' + @cols + ')
            ) PivotTable order by Name'
execute(@query) /* execution of the query */
