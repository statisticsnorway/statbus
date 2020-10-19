USE [nscreg]
GO

/****** Object:  UserDefinedFunction [dbo].[CountTotalEmployeesInOblastsAsSql]    Script Date: 10/16/2020 5:10:45 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER FUNCTION [dbo].[CountTotalEmployeesInOblastsAsSql]()  
RETURNS NVARCHAR(MAX)
AS   
-- Returns all oblast names with Null checking, oblast are regions with region level 1
BEGIN  
    DECLARE @TotalEmployeesSql  NVARCHAR(MAX) = ''; 
	DECLARE @HasCountryAsLevel1 BIT;
	DECLARE @RegionLevel INT = 1;

	SET @HasCountryAsLevel1 = dbo.HasCountryAsLevel1();
	IF @HasCountryAsLevel1 = 1
	BEGIN
		SET @RegionLevel += 1;
	END

	SET @TotalEmployeesSql = STUFF(
		(SELECT DISTINCT '+ISNULL(' + QUOTENAME(Name) + ', 0)'
		FROM dbo.Regions  
		WHERE 
			RegionLevel IN (@RegionLevel,@RegionLevel - 1)
		FOR XML PATH(''), TYPE)
		.value('.', 'NVARCHAR(MAX)')
		,1,1,'')
	RETURN @TotalEmployeesSql
END; 
GO

