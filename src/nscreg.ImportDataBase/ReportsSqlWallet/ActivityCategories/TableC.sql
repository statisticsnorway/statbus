DECLARE @cols AS NVARCHAR(MAX),@colSum AS NVARCHAR(MAX),
        @query AS NVARCHAR(MAX);
SET @cols = STUFF(
                     (
                         SELECT 
							', ' + QUOTENAME(Name)
                         FROM ActivityCategories
                         WHERE 
							ActivityCategoryLevel = 1
                         GROUP BY Name
                         ORDER BY Name
                         FOR XML PATH(''), TYPE
                     ).value('.', 'NVARCHAR(MAX)'),
                     1,
                     1,
                     ''
                 );
SET @colSum = STUFF(
                     (
                         SELECT 
							', SUM(' + QUOTENAME(Name)+') as '+ QUOTENAME(Name)
                         FROM ActivityCategories
                         WHERE 
							ActivityCategoryLevel = 1
                         GROUP BY Name
                         ORDER BY Name
                         FOR XML PATH(''), TYPE
                     ).value('.', 'NVARCHAR(MAX)'),
                     1,
                     1,
                     ''
                 );


IF (OBJECT_ID('tempdb..#tempActivityCategories') IS NOT NULL)
BEGIN DROP TABLE #tempActivityCategories END
CREATE TABLE #tempActivityCategories
(
    ID INT,
    Level INT,
    Path INT,
    RowNumber INT
);
IF (OBJECT_ID('tempdb..#tempRegions') IS NOT NULL)
BEGIN DROP TABLE #tempRegions END
CREATE TABLE #tempRegions
(
    ID INT,
    Level INT,
    Path INT,
    RowNumber INT
);


SET @query
    = N'
				;WITH ActivityCategoriesCTE AS (
					SELECT
						Id, 0 AS Level, CAST(Id AS VARCHAR(255)) AS Path
					FROM ActivityCategories 

					UNION ALL

					SELECT 
						i.Id, Level + 1, CAST(Path AS VARCHAR(255))
					FROM ActivityCategories i
					INNER JOIN ActivityCategoriesCTE itms ON itms.Id = i.ParentId
				)

				INSERT INTO #tempActivityCategories
				SELECT Id,Level,Path,ROW_NUMBER() over (partition by Id order by Level desc) FROM ActivityCategoriesCTE

				;WITH RegionsCTE AS (
					SELECT
						Id, 0 AS Level, CAST(Id AS VARCHAR(255)) AS Path
					FROM Regions 

					UNION ALL

					SELECT 
						i.Id, itms.Level + 1, CAST(itms.Path AS VARCHAR(255))
					FROM Regions i
					INNER JOIN RegionsCTE itms ON itms.Id = i.ParentId
				)

				INSERT INTO #tempRegions
				SELECT Id,Level,Path,ROW_NUMBER() over (partition by Id order by Level desc) FROM RegionsCTE

				;WITH CTE AS (
								SELECT 
									su.RegId,
									IIF(ac.ActivityCategoryLevel = 2, ac.ParentId,ac.Id) AS ActivityCategoryId,
									reg.RegionLevel,
									IIF(reg.RegionLevel = 4,reg.ParentId,reg.Id) AS RegionId
								FROM StatisticalUnits AS su	

								INNER JOIN ActivityStatisticalUnits asu ON asu.Unit_Id = su.RegId
								INNER JOIN Activities a ON a.Id = asu.Activity_Id
								INNER JOIN ActivityCategories ac ON ac.Id = a.ActivityCategoryId
								INNER JOIN Address addr	ON addr.Address_id = su.AddressId
								INNER JOIN Regions AS reg ON reg.Id = addr.Region_id
								LEFT JOIN Regions AS regParent ON reg.ParentId = regParent.Id
                WHERE su.IsDeleted = 0
				),
				CTE_Result AS (
SELECT RegionName,Id,ParentId,' + @colSum
      + N' from 
            (				
				SELECT 
					COUNT(ct.RegId) as RegId, 
					ct.ActivityCategoryId,
					--ct.RegionLevel,
					--ct.RegionId,
					reg.Id,
					reg.ParentId,
					reg.Name AS RegionName,
					act.Name AS actName
				FROM CTE AS ct
				INNER JOIN #tempRegions AS regTemp ON ct.RegionId = regTemp.Id
				INNER JOIN Regions AS reg ON regTemp.Path = reg.Id
				INNER JOIN #tempActivityCategories AS it ON it.ID = ct.ActivityCategoryId
				INNER JOIN ActivityCategories AS act ON act.Id = it.Path
				WHERE it.RowNumber = 1				
				GROUP BY ct.ActivityCategoryId,
					--ct.RegionLevel,
					--ct.RegionId,
					reg.Id,
					reg.ParentId,
					reg.Name,
					act.Name
				

           ) SourceTable 
            PIVOT 
            (
                SUM(RegId)
                FOR actName IN (' + @cols + N')
            ) PivotTable 
			GROUP BY RegionName,Id,ParentId)
			select IIF(ParentId!=1,''  ''+RegionName,RegionName) as RegionName,'+ @cols +' from CTE_Result
			ORDER BY Id,ParentId
			'
			;



EXECUTE (@query);
