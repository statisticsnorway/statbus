DELETE FROM [dbo].[Regions]
GO
DBCC CHECKIDENT ('dbo.Regions',RESEED, 1)
GO

ALTER TABLE [dbo].[Regions] ADD OldParentId NVARCHAR(20) NULL
GO

INSERT INTO [dbo].[Regions]
  ([AdminstrativeCenter]
  ,[Code]
  ,[IsDeleted]
  ,[Name]
  ,[NameLanguage1]
  ,[NameLanguage2]
  ,[ParentId]
  ,[OldParentId]
  ,[FullPath]
  ,[FullPathLanguage1]
  ,[FullPathLanguage2]
  ,[RegionLevel])
SELECT
  [NAM1]
  ,[K_TER]
  ,0
  ,[N_TER]
  ,NULL
  ,NULL
  ,NULL
  ,[K_TER_GROUP]
  ,NULL
  ,NULL
  ,NULL
  ,NULL
FROM [statcom].[dbo].[SPRTER]
GO

-- Define childs and parents

UPDATE Child
  SET [ParentId] = Parent.Id
FROM [dbo].[Regions] Parent
  INNER JOIN [dbo].[Regions] Child
    ON Parent.Code = Child.OldParentId

-- Delete unneeded column

ALTER TABLE [dbo].[Regions] DROP COLUMN OldParentId
GO

-- FullPath collecting CTE

WITH CTE AS (
  SELECT Id, AdminstrativeCenter, Code, IsDeleted, Name, ParentId, Name AS FullPath, ParentId AS LastParentId, 1 AS num
  FROM Regions 

  UNION ALL

  SELECT CTE.Id, CTE.AdminstrativeCenter, CTE.Code, CTE.IsDeleted, CTE.Name, CTE.ParentId, r.Name + ', ' + CTE.FullPath, r.ParentId, num + 1
  FROM CTE 
  INNER JOIN Regions AS r
    ON CTE.LastParentId = r.Id
),
CTE2 AS (
  SELECT Id, AdminstrativeCenter, Code, IsDeleted, Name, ParentId, FullPath, ROW_NUMBER() OVER(PARTITION BY Id ORDER BY num DESC) AS rn
  FROM CTE
)

-- FullPath define

UPDATE r
	SET r.FullPath = cte.FullPath
FROM Regions r
	INNER JOIN CTE2 cte
		ON cte.Id = r.Id
WHERE rn = 1
GO

-- REGION CATEGORY LEVEL DEFINE PART --

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

-- Update ActivityCategories with correct level number
UPDATE [dbo].[Regions]
SET [RegionLevel] = dbo.GetRegionLevel(Id)
GO

-- Remove unnecessary function
DROP FUNCTION [dbo].[GetRegionLevel]
GO
