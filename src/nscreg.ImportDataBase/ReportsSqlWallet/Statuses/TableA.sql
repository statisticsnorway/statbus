DECLARE @cols AS NVARCHAR(MAX), @query  AS NVARCHAR(MAX), @totalSumCols AS NVARCHAR(MAX);
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
		
set @query = 'SELECT Name, ' + @cols + ', ' + @totalSumCols + ' as Total from 
            (
				SELECT 
					su.RegId,
					st.Name,
					reg.Name AS NameOblast 
				FROM dbo.Statuses AS st
				LEFT JOIN StatisticalUnits su
					ON st.Id = su.UnitStatusId
				LEFT JOIN dbo.Address addr
					ON addr.Address_id = su.AddressId
				LEFT JOIN dbo.Regions AS reg ON reg.Id = addr.Region_id
         WHERE su.IsDeleted = 0
           ) SourceTable
            PIVOT 
            (
                COUNT(RegId)
                FOR NameOblast IN (' + @cols + ')
            ) PivotTable '
execute(@query)
