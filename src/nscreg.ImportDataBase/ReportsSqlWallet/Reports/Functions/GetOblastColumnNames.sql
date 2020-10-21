USE [nscreg]
GO

/****** Object:  UserDefinedFunction [dbo].[GetOblastColumnNames]    Script Date: 10/16/2020 5:12:21 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


-- Returns all oblast names, oblast are regions with region level 1
/* If there no Country level in your Regions table, below "WHERE" condition from:
    WHERE RegionLevel = 2
    Must be:
    WHERE RegionLevel = 1
*/
CREATE OR ALTER FUNCTION [dbo].[GetOblastColumnNames]()  
RETURNS NVARCHAR(MAX)
AS   

BEGIN  
    DECLARE @OblastNames  NVARCHAR(MAX) = ''; 
	DECLARE @HasCountryAsLevel1 BIT;
	DECLARE @RegionLevel INT = 1;

	SET @HasCountryAsLevel1 = dbo.HasCountryAsLevel1();
	IF @HasCountryAsLevel1 = 1
	BEGIN
		SET @RegionLevel += 1;
	END

	SET @OblastNames = STUFF(
		(SELECT DISTINCT ',' + QUOTENAME(Name)
        FROM dbo.Regions 
		WHERE 
			RegionLevel IN (@RegionLevel,@RegionLevel - 1)
		FOR XML PATH(''), TYPE
		).value('.', 'NVARCHAR(MAX)')
		,1,1,'')
    RETURN @OblastNames;  
END; 
GO

