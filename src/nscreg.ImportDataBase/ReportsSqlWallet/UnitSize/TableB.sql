DECLARE @cols AS NVARCHAR(MAX), @query AS NVARCHAR(MAX), @totalSumCols AS NVARCHAR(MAX);
SET @cols = STUFF((SELECT distinct ',' + QUOTENAME(r.Name)
            FROM Regions r  WHERE RegionLevel = 2 --AND r.ParentId = $RegionId
            FOR XML PATH(''), TYPE
            ).value('.', 'NVARCHAR(MAX)')
        ,1,1,'')
SET @totalSumCols = STUFF((SELECT distinct '+' + QUOTENAME(r.Name)
            FROM Regions r  WHERE RegionLevel = 2-- AND r.ParentId = $RegionId
            FOR XML PATH(''), TYPE
            ).value('.', 'NVARCHAR(MAX)')
        ,1,1,'')
set @query = 'SELECT Name, ' + @cols + ', ' + @totalSumCols + ' as Total from 
            (
				SELECT
					su.RegId,
					us.Name,
					reg.Name AS NameOblast
				FROM UnitsSize AS us
				LEFT JOIN StatisticalUnits su
					ON us.Id = su.SizeId
				LEFT JOIN dbo.Address addr
					ON addr.Address_id = su.AddressId
				LEFT JOIN dbo.Regions AS reg ON reg.Id = addr.Region_id
           ) SourceTable
            PIVOT 
            (
                COUNT(RegId)
                FOR NameOblast IN (' + @cols + ')
            ) PivotTable '
execute(@query)
