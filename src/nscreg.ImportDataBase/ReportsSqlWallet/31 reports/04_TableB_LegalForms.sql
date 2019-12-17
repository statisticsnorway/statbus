/*
	RegionLevel:
		1 : Kyrgyz Republic
		2 : Area
		3 : Region
		4 : City / Village

Row headers - Legal forms
Column headers - Rayons and in Total Oblast
*/
BEGIN /* INPUT PARAMETERS from report body */
	DECLARE @InRegionId INT = $RegionId,
			    @InStatusId NVARCHAR(MAX) = $StatusId,
          @InCurrentYear NVARCHAR(MAX) = YEAR(GETDATE())
END
DECLARE @cols AS NVARCHAR(MAX),
    @selCols AS NVARCHAR(MAX),
		@query AS NVARCHAR(MAX),
		@totalSumCols AS NVARCHAR(MAX),
		@regionLevel AS NVARCHAR(MAX),
		@nameTotalColumn AS NVARCHAR(MAX)

/* Declare Oblast/County/Region - to take only Rayons/Municipalities/Sub-level of Oblast */
SET @nameTotalColumn  = (SELECT TOP 1 Name FROM Regions WHERE Id = @InRegionId)
SET @cols = STUFF((SELECT distinct ',' + QUOTENAME(r.Name)
            FROM Regions r  WHERE (RegionLevel <= 3 AND r.ParentId = @InRegionId) OR r.Id = @InRegionId
            FOR XML PATH(''), TYPE
            ).value('.', 'NVARCHAR(MAX)')
        ,1,1,'')
		PRINT @cols /* COLUMNS VARIABLES - REGIONS, OBLASTS LEVEL */
SET @selCols = STUFF((SELECT distinct ',' + QUOTENAME(r.Name)
            FROM Regions r  WHERE RegionLevel = 3 AND r.ParentId = @InRegionId
            FOR XML PATH(''), TYPE
            ).value('.', 'NVARCHAR(MAX)')
        ,1,1,'')
		PRINT @selCols /* COLUMNS VARIABLES - Rayons/Municipalities/Sub-level of Oblast LEVEL */
SET @totalSumCols = STUFF((SELECT distinct '+' + QUOTENAME(r.Name)
            FROM Regions r  WHERE (RegionLevel = 3 AND r.ParentId = @InRegionId) OR r.Id = @InRegionId
            FOR XML PATH(''), TYPE
            ).value('.', 'NVARCHAR(MAX)')
        ,1,1,'')
		PRINT @totalSumCols

/* SET THIS TO 2 if database has no Country level and begins from the Oblasts/Counties/Regions */
SET @regionLevel = 3

/* Delete temporary table for Pivot - result table if exists */
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

/* Create an index "ix_tempRegionsIndex" - to make search faster - Activity Categories */
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
END	

/*
The resulting query 
At the first checking the history logs that have StartPeriod less than current year
and then
ResultTable - get the actual state of statistical units where RegistrationDate and StartPeriod less than current year
and then
Select by Legal forms all statistical units
and then
Count statistical units using pivot transform regions - from column to row
*/
set @query = '
;WITH StatisticalUnitHistoryCTE AS (
	SELECT
		RegId,
		ParentId,	
		AddressId,
		LegalFormId,
		ROW_NUMBER() over (partition by ParentId order by StartPeriod desc) AS RowNumber
	FROM StatisticalUnitHistory
	WHERE DATEPART(YEAR,StartPeriod)<'+@InCurrentYear+'
),
ResultTableCTE AS
(	
	SELECT
		su.RegId,
		IIF(DATEPART(YEAR, su.RegistrationDate)<'+@InCurrentYear+' AND DATEPART(YEAR,su.StartPeriod)<'+@InCurrentYear+',tr.Name, trh.Name) AS NameOblast,
		IIF(DATEPART(YEAR, su.RegistrationDate)<'+@InCurrentYear+' AND DATEPART(YEAR,su.StartPeriod)<'+@InCurrentYear+',lf.Id, lfh.Id) AS LegalFormId
	FROM StatisticalUnits su
	LEFT JOIN LegalForms AS lf ON lf.Id = su.LegalFormId		
	LEFT JOIN dbo.Address addr ON addr.Address_id = su.AddressId
	INNER JOIN #tempRegions as tr ON tr.Id = addr.Region_id	AND tr.Level = ' + @regionLevel + '

	LEFT JOIN StatisticalUnitHistoryCTE asuhCTE ON asuhCTE.ParentId = su.RegId and asuhCTE.RowNumber = 1
	LEFT JOIN LegalForms AS lfh ON lfh.Id = asuhCTE.LegalFormId
	LEFT JOIN dbo.Address addrh ON addrh.Address_id = asuhCTE.AddressId
	LEFT JOIN #tempRegions as trh ON trh.Id = addrh.Region_id
    
    WHERE su.UnitStatusId = ' + @InStatusId +'
)
SELECT Name, ' + @selCols + ', ' + @totalSumCols + ' as [' + @nameTotalColumn+ '] from
            (
				SELECT
					lf.Name,
					rtCTE.RegId,
					rtCTE.NameOblast
				FROM LegalForms as lf
				LEFT JOIN ResultTableCTE as rtCTE ON lf.Id = rtCTE.LegalFormId
           ) SourceTable
            PIVOT 
            (
                COUNT(RegId)
                FOR NameOblast IN (' + @cols + ')
            ) PivotTable'
execute(@query) /* execution of the query */
