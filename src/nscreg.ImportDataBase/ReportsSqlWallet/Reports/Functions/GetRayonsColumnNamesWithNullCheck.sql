USE [nscreg]
GO

/****** Object:  UserDefinedFunction [dbo].[GetRayonsColumnNamesWithNullCheck]    Script Date: 10/16/2020 5:11:51 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE OR ALTER FUNCTION [dbo].[GetRayonsColumnNamesWithNullCheck](@OblastId INT)  
RETURNS NVARCHAR(MAX)
AS   
-- Returns all oblast names with Null checking, oblast are regions with region level 1
BEGIN  
    DECLARE @RayonsNames  NVARCHAR(MAX) = '';
	DECLARE @NumberRecordsByRegionLevel1 BIT;
	DECLARE @RegionLevel INT = 2;

	SET @NumberRecordsByRegionLevel1 = dbo.HasCountryAsLevel1();

	IF @NumberRecordsByRegionLevel1 = 1
	BEGIN
		SET @RegionLevel += 1;
	END
	SET @RayonsNames = 
		STUFF((SELECT distinct ',ISNULL(' +  QUOTENAME(Name) + ', 0)  AS ' + QUOTENAME(Name)

		FROM dbo.Regions  
		WHERE 
			RegionLevel = @RegionLevel
		AND
			ParentId = @OblastId
		
		FOR XML PATH(''), 
		TYPE
		).value('.', 'NVARCHAR(MAX)')
		,1,1,'');
	RETURN @RayonsNames
END; 
GO

