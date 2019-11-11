
BEGIN /* INPUT PARAMETERS */
	DECLARE @InStatusId NVARCHAR(MAX) = $StatusId
END

DECLARE @cols AS NVARCHAR(MAX), 
		@query  AS NVARCHAR(MAX), 
		@totalSumCols AS NVARCHAR(MAX), 
		@regionLevel AS NVARCHAR(MAX)		

SET @cols = STUFF((SELECT distinct ',' + QUOTENAME(r.Name)
            FROM Regions r  WHERE RegionLevel IN (1,2)
            FOR XML PATH(''), TYPE
            ).value('.', 'NVARCHAR(MAX)')
        ,1,1,'')
SET @totalSumCols = STUFF((SELECT distinct '+' + QUOTENAME(r.Name)
            FROM Regions r  WHERE RegionLevel IN (1,2)
            FOR XML PATH(''), TYPE
            ).value('.', 'NVARCHAR(MAX)')
        ,1,1,'')
SET @regionLevel = 2

BEGIN /*DECLARE and FILL IerarhyOfRegions*/
IF (OBJECT_ID('tempdb..#tempRegions') IS NOT NULL)
	BEGIN DROP TABLE #tempRegions END
CREATE TABLE #tempRegions
(
    ID INT,
    Level INT,
    ParentId INT,
    Name NVARCHAR(MAX)
);
CREATE NONCLUSTERED INDEX ix_tempRegionsIndex ON #tempRegions ([ID]);
;WITH RegionsCTE AS (
	SELECT Id, 0 AS Level, CAST(Id AS VARCHAR(255)) AS ParentId
	FROM Regions 

	UNION ALL

	SELECT i.Id, Level + 1, CAST(itms.ParentId AS VARCHAR(255))
	FROM Regions i
	INNER JOIN RegionsCTE itms ON itms.Id = i.ParentId
	WHERE i.ParentId>0
),
CTE_RN2 AS 
(
    SELECT Id,Level,ParentId, ROW_NUMBER() OVER (PARTITION BY r.Id ORDER BY r.Level DESC) RN
    FROM RegionsCTE r
    
)
INSERT INTO #tempRegions
SELECT r.Id, r.RN, r.ParentId, rp.Name AS ParentName
FROM CTE_RN2 r
	INNER JOIN Regions rp ON rp.Id = r.ParentId
	INNER JOIN Regions rc ON rc.Id = r.Id
WHERE r.RN = @regionLevel
END		
set @query = '
;WITH StatisticalUnitHistoryCTE AS (
	SELECT
		RegId,
		ParentId,	
		AddressId,
		InstSectorCodeId,
		ROW_NUMBER() over (partition by ParentId order by StartPeriod desc) AS RowNumber
	FROM StatisticalUnitHistory
	WHERE DATEPART(YEAR,StartPeriod)<2019
),
ResultTableCTE AS
(	
	SELECT
		su.RegId,
		IIF(DATEPART(YEAR, su.RegistrationDate)<2019 AND DATEPART(YEAR,su.StartPeriod)<2019,tr.Name, trh.Name) AS NameOblast,
		IIF(DATEPART(YEAR, su.RegistrationDate)<2019 AND DATEPART(YEAR,su.StartPeriod)<2019,sc.Id, sch.Id) AS SectorCodeId
	FROM StatisticalUnits su
	LEFT JOIN SectorCodes AS sc ON sc.Id = su.InstSectorCodeId		
	LEFT JOIN Address addr ON addr.Address_id = su.AddressId
	INNER JOIN #tempRegions as tr ON tr.Id = addr.Region_id				

	LEFT JOIN StatisticalUnitHistoryCTE asuhCTE ON asuhCTE.ParentId = su.RegId and asuhCTE.RowNumber = 1
	LEFT JOIN SectorCodes AS sch ON sch.Id = asuhCTE.InstSectorCodeId
	LEFT JOIN Address addrh ON addrh.Address_id = asuhCTE.AddressId
	LEFT JOIN #tempRegions as trh ON trh.Id = addrh.Region_id
    
    WHERE 
	su.UnitStatusId = ' + @InStatusId +' AND 
	Discriminator IN (''LegalUnit'',''EnterpriseUnit'')
)


SELECT Name, ' + @cols + ', ' + @totalSumCols + ' as Total from 
           (		
				SELECT
					sc.Name,
					rtCTE.RegId,
					rtCTE.NameOblast
				FROM SectorCodes as sc
				LEFT JOIN ResultTableCTE as rtCTE ON sc.Id = rtCTE.SectorCodeId
           ) SourceTable
            PIVOT 
            (
                COUNT(RegId)
                FOR NameOblast IN (' + @cols + ')
            ) PivotTable 
			'
execute(@query)
