CREATE OR ALTER FUNCTION [dbo].[GetNamesRegionsForPivot]
(
  @RegionId INT,
  @RequestName NVARCHAR(MAX),
  @IncludeSourceRegion BIT
)
RETURNS NVARCHAR(MAX)
AS
BEGIN
  DECLARE @ResultValue NVARCHAR(MAX);
		IF (@RequestName = 'TOTAL')
			SET @ResultValue = STUFF((SELECT distinct '+' + QUOTENAME(Name)
				FROM dbo.Regions  WHERE (ParentId = @RegionId AND RegionLevel IN (1,2,3)) OR (@IncludeSourceRegion = 1 AND Id = @RegionId)
				FOR XML PATH(''), TYPE
				).value('.', 'NVARCHAR(MAX)')
			,1,1,'');
		IF (@RequestName = 'SELECT')
			SET @ResultValue = STUFF((SELECT distinct ',' + QUOTENAME(Name)
				FROM dbo.Regions WHERE ParentId = @RegionId AND RegionLevel = 3
				FOR XML PATH(''), TYPE
				).value('.', 'NVARCHAR(MAX)')
			,1,1,'');
		IF (@RequestName = 'FORINPIVOT')
			SET @ResultValue = STUFF((SELECT distinct ',' + QUOTENAME(Name)
				FROM dbo.Regions  WHERE ParentId = @RegionId AND RegionLevel IN (1,2,3) OR (@IncludeSourceRegion = 1 AND Id = @RegionId)
				FOR XML PATH(''), TYPE
				).value('.', 'NVARCHAR(MAX)')
			,1,1,'');
			
		RETURN(@ResultValue);
END
