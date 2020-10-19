USE [nscreg]
GO

/****** Object:  UserDefinedFunction [dbo].[GetOblastColumnNamesWithNullCheck]    Script Date: 10/16/2020 5:12:08 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

ALTER FUNCTION [dbo].[GetOblastColumnNamesWithNullCheck]()  
RETURNS NVARCHAR(MAX)
AS   
-- Returns all oblast names with Null checking, oblast are regions with region level 1
BEGIN  
    DECLARE @OblastNames  NVARCHAR(MAX) = '';
	DECLARE @HasCountryAsLevel1 BIT;
	DECLARE @RegionLevel INT = 1;
	SET @HasCountryAsLevel1 = dbo.HasCountryAsLevel1();

	IF @HasCountryAsLevel1 = 1
	BEGIN
		SET @RegionLevel += 1;
	END

	SET @OblastNames = 
		STUFF((SELECT distinct ',ISNULL(' +  QUOTENAME(Name) + ', 0)  AS ' + QUOTENAME(Name)
		/* set re.RegionLevel = 1 if there is no Country level at Regions tree */
		FROM dbo.Regions  
		WHERE 
			RegionLevel = @RegionLevel
		FOR XML PATH(''), 
		TYPE
		).value('.', 'NVARCHAR(MAX)')
		,1,1,'');
	RETURN @OblastNames
END; 
GO

