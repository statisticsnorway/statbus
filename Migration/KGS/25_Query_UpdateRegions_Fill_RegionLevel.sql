USE [nscreg]
GO

-- Add a function that gets the level number, passing the ID
CREATE FUNCTION GetRegionLevel (@input_id INT)   
	RETURNS INT
AS BEGIN   
    DECLARE @in_id INT = @input_id;
	DECLARE @level INT = 1;

	WHILE @in_id > 0 
	BEGIN
		SELECT top 1 @in_id = ParentId FROM Regions WHERE Id = @in_id
		IF @in_id > 0 SET @level = @level + 1;
	END

    RETURN @level  
END  
GO

-- Update Regions with correct level number
UPDATE Regions
SET RegionLevel = dbo.GetRegionLevel(Id)
GO

-- Remove unnecessary function
DROP FUNCTION [dbo].[GetRegionLevel]
GO