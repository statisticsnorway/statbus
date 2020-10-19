CREATE VIEW [dbo].[v_ActivityCategoriesHierarchy]
AS
WITH ActivityCategoriesCTE AS (
	SELECT
		Id, 0 AS Level, CAST(Id AS VARCHAR(255)) AS ParentId, ActivityCategoryLevel
	FROM dbo.ActivityCategories 

	UNION ALL

	SELECT 
		ac.Id, acCTE.Level + 1, CAST(acCTE.ParentId AS VARCHAR(255)) AS ParentId, ac.ActivityCategoryLevel
	FROM dbo.ActivityCategories ac
	INNER JOIN ActivityCategoriesCTE acCTE ON acCTE.Id = ac.ParentId
)
SELECT
	acCTE.Id,
	acCTE.ParentId, 
	ROW_NUMBER() OVER (PARTITION BY acCTE.Id ORDER BY acCTE.Level DESC) AS DesiredLevel,
	rp.Name,
	rc.ActivityCategoryLevel
FROM ActivityCategoriesCTE AS acCTE
LEFT JOIN dbo.ActivityCategories rp ON rp.Id = acCTE.ParentId
LEFT JOIN dbo.ActivityCategories rc ON rc.Id = acCTE.Id
