USE [nscreg]
GO

/****** Object:  UserDefinedFunction [dbo].[GetRayonsColumnNames]    Script Date: 10/16/2020 5:11:39 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


ALTER FUNCTION [dbo].[GetRayonsColumnNames](@OblastId INT )  
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
		(SELECT DISTINCT ',' + QUOTENAME(Name)
		FROM dbo.Regions  
		WHERE 
			RegionLevel IN (@RegionLevel,@RegionLevel - 1)
		
		FOR XML PATH(''), TYPE)
		.value('.', 'NVARCHAR(MAX)')
		,1,1,'')
	RETURN @TotalEmployeesSql
END; 
GO

