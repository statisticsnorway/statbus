USE [nscreg2]
GO

/****** Object:  UserDefinedFunction [dbo].[CountTotalInRayonsAsSql]    Script Date: 10/16/2020 5:11:14 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[CountTotalInRayonsAsSql](@OblastId INT)  
RETURNS NVARCHAR(MAX)
AS   
-- Returns all oblast names with Null checking, oblast are regions with region level 1
BEGIN  
    DECLARE @TotalEmployeesSql  NVARCHAR(MAX) = ''; 
	DECLARE @HasCountryAsLevel1 BIT;
	DECLARE @RegionLevel INT = 2;

	SET @HasCountryAsLevel1 = dbo.HasCountryAsLevel1();

	IF @HasCountryAsLevel1 = 1
	BEGIN
		SET @RegionLevel += 1;
	END

	/* set re.RegionLevel = 1 if there is no Country level at Regions tree (without condition Id = 1) */
	SET @TotalEmployeesSql = STUFF(
		(SELECT DISTINCT '+ISNULL(' + QUOTENAME(Name) + ', 0)'
		FROM dbo.Regions  
		WHERE RegionLevel 
			IN (@RegionLevel,@RegionLevel - 1)
		AND (
			Id = @OblastId
		OR
			ParentId = @OblastId
		)
		
		FOR XML PATH(''), TYPE)
		.value('.', 'NVARCHAR(MAX)')
		,1,1,'')
	RETURN @TotalEmployeesSql
END; 
GO

