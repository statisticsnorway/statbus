USE [nscreg2]
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
CREATE FUNCTION [dbo].[HasCountryAsLevel1]()  
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

