CREATE VIEW [dbo].[v_Regions]
AS
WITH RegionsCTE AS (
	SELECT
		Id, 0 AS Level, CAST(Id AS VARCHAR(255)) AS ParentId
	FROM dbo.Regions 

	UNION ALL

	SELECT 
		r.Id, Level + 1, CAST(itms.ParentId AS VARCHAR(255))
	FROM dbo.Regions r
	INNER JOIN RegionsCTE itms ON itms.Id = r.ParentId
	WHERE r.ParentId>0
)
SELECT
	rCTE.Id,
	rCTE.ParentId,
	ROW_NUMBER() OVER (PARTITION BY rCTE.Id ORDER BY rCTE.Level DESC) DesiredLevel,
	rp.Name,
	rc.RegionLevel
FROM RegionsCTE AS rCTE
LEFT JOIN dbo.Regions rp ON rp.Id = rCTE.ParentId
LEFT JOIN dbo.Regions rc ON rc.Id = rCTE.Id
