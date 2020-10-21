USE [nscreg]
GO

/****** Object:  UserDefinedFunction [dbo].[HasCountryAsLevel1]    Script Date: 10/16/2020 5:11:27 PM ******/
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
CREATE OR ALTER FUNCTION [dbo].[HasCountryAsLevel1]()  
RETURNS BIT
AS   

BEGIN  
    DECLARE @NumberRecords INT;
	DECLARE @HasCountryAsLevel1 BIT;

	SET @NumberRecords = (
		SELECT COUNT(Id)
		FROM dbo.Regions  
		GROUP BY 
			RegionLevel
		HAVING RegionLevel = 1
	)
	

	IF @NumberRecords = 1
	BEGIN
		SET @HasCountryAsLevel1 = 1
	END
    RETURN @HasCountryAsLevel1;  
END; 
GO


/****** Object:  UserDefinedFunction [dbo].[HasCountryAsLevel1]    Script Date: 10/16/2020 5:11:27 PM ******/SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER FUNCTION [dbo].[GetOblastLevel]()  
RETURNS INT
AS   

BEGIN  
  DECLARE @OblastLevel INT = 1;
	DECLARE @HasCountryAsLevel1 BIT;

	SET @HasCountryAsLevel1 = dbo.HasCountryAsLevel1();
	IF @HasCountryAsLevel1 = 1
	BEGIN
		SET @OblastLevel += 1;
	END

  RETURN @OblastLevel;  
END; 
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

/****** Object:  UserDefinedFunction [dbo].[CountTotalInRayonsAsSql]    Script Date: 10/16/2020 5:11:14 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER FUNCTION [dbo].[CountTotalInRayonsAsSql](@OblastId INT)  
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
	SET @HasCountryAsLevel1 = dbo.HasCountryAsLevel1();

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

/****** Object:  UserDefinedFunction [dbo].[GetOblastColumnNamesWithNullCheck]    Script Date: 10/16/2020 5:12:08 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER FUNCTION [dbo].[GetOblastColumnNamesWithNullCheck]()  
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

/****** Object:  UserDefinedFunction [dbo].[GetRayonsColumnNames]    Script Date: 10/16/2020 5:11:39 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE OR ALTER FUNCTION [dbo].[GetRayonsColumnNames](@OblastId INT )  
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

CREATE OR ALTER VIEW vw_OblastRegions
AS 
SELECT
    Id,
    Name
FROM
    Regions
WHERE RegionLevel =  IIF(dbo.HasCountryAsLevel1() = 1,2,1)
