;WITH UnitsAndAddresses AS (
	SELECT 
		su.RegId, 
		adr.Address_id, 
		ray.Id AS RayonId,
		adr.Address_part1,
		adr.Address_part2,
		adr.Address_part3
	FROM Address AS adr
	INNER JOIN Regions AS r
		ON adr.Region_id = r.Id 
	LEFT JOIN Regions AS ray
		ON r.Code LIKE LEFT(ray.Code, 8) + '%' AND ray.RegionLevel = 2 AND ISNULL(r.RegionLevel, 0) <> 1 AND r.ParentId IS NOT NULL
	INNER JOIN StatisticalUnits AS su
		ON su.AddressId = adr.Address_id AND ($StatUnitType = 'All' OR su.Discriminator = $StatUnitType) AND su.UnitStatusId IS NOT NULL
),
OblastsAndRayons AS (
	SELECT 
		obl.Id AS OblastId, obl.[Code] AS OblastCode, obl.[Name] AS OblastName,
		ray.Id AS RayonId, ray.[Code] AS RayonCode, ray.[Name] AS RayonName, ray.FullPath
	FROM Regions AS obl
	INNER JOIN Regions AS ray
		ON obl.Id = ray.ParentId
	WHERE
		ray.RegionLevel = 2
)
SELECT  top 10000
	OblastCode,
	OblastName, 
	RayonCode, 
	RayonName, 
	su.EmailAddress,
	su.NumOfPeopleEmp,
	su.RegistrationDate,
	su.ShortName,
	usize.Name,
	su.StatId,
	su.WebAddress,
	su.TotalCapital,
	su.Turnover AS StatUnitTurnover, 
	su.Name AS StatUnitName, 
	su.Employees AS StatUnitEmployees,
	Address_part1,
	Address_part2,
	Address_part3,
	FullPath,
	a.Activity_Type,
	a.Turnover AS ActivityTurnover,
	a.Employees AS TurnoverEmployees,
	ac.Code,
	ac.Name AS ActivityCategoryName,
    ac.ActivityCategoryLevel,
	ac.Section,
	--sc.Code,
	--sc.Name,
	lf.Code AS Legal_Form_Code,
	lf.Name AS Legal_Form,
    us.Name AS Unit_Status
	
	 
FROM OblastsAndRayons AS ray
INNER JOIN UnitsAndAddresses AS ua
	ON ua.RayonId = ray.RayonId
LEFT JOIN [dbo].[StatisticalUnits] AS su
	ON ua.RegId = su.RegId
LEFT JOIN ActivityStatisticalUnits asu
	ON asu.Unit_Id = su.RegId
LEFT JOIN Activities a
	ON a.Id = asu.Activity_Id
LEFT JOIN ActivityCategories ac
	ON ac.Id = a.ActivityCategoryId
LEFT JOIN SectorCodes sc
	ON sc.Id = su.InstSectorCodeId
LEFT JOIN LegalForms lf
	ON lf.Id = su.LegalFormId
LEFT JOIN Statuses us
	ON us.Id = su.UnitStatusId
LEFT JOIN UnitsSize usize
	ON usize.Id = su.SizeId