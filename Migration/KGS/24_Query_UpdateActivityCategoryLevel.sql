USE [nscreg]
GO

-- Add a function that gets the level number, passing the ID
CREATE FUNCTION GetActivityCategoryLevel (@input_id INT)   
	RETURNS INT
AS BEGIN   
    DECLARE @in_id INT = @input_id;
	DECLARE @level INT = 1;

	WHILE @in_id > 0 
	BEGIN
		SELECT top 1 @in_id = ParentId FROM ActivityCategories WHERE Id = @in_id
		IF @in_id > 0 SET @level = @level + 1;
	END

    RETURN @level  
END  
GO

-- Update ActivityCategories with correct level number
UPDATE ActivityCategories
SET ActivityCategoryLevel = dbo.GetActivityCategoryLevel(Id)
GO

-- Remove unnecessary function
DROP FUNCTION [dbo].[GetActivityCategoryLevel]
GO