namespace nscreg.Data
{
    internal static partial class SeedData
    {
        public const string DeleteStatUnitSearchViewTableScript = @"
                IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'V_StatUnitSearch' AND TABLE_TYPE = 'BASE TABLE')
                DROP TABLE V_StatUnitSearch";

        public const string CheckIfStatUnitSearchViewExist = @"
            IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'V_StatUnitSearch'  AND TABLE_TYPE = 'VIEW')
            DROP VIEW [dbo].[V_StatUnitSearch]";

        public const string StatUnitSearchViewScript = @"
            CREATE VIEW [dbo].[V_StatUnitSearch]
            AS
            SELECT
	            RegId,
	            Name,
	            TaxRegId, 
	            StatId, 
	            ExternalId, 
	            Region_id AS RegionId, 
	            Employees, 
                Turnover, 
	            InstSectorCodeId AS SectorCodeId, 
	            LegalFormId, 
	            DataSource, 
	            StartPeriod,
	            ParentId,
	            IsDeleted,
	            LiqReason,
	            Address_part1 AS AddressPart1,
	            Address_part2 AS AddressPart2,
	            Address_part3 AS AddressPart3,
	            CASE 
		            WHEN Discriminator = 'LocalUnit' THEN 1
		            WHEN Discriminator = 'LegalUnit' THEN 2
		            WHEN Discriminator = 'EnterpriseUnit' THEN 3

	            END  
	            AS UnitType
            FROM	dbo.StatisticalUnits 
	            LEFT JOIN dbo.Address 
		            ON AddressId = Address_id

            UNION ALL

            SELECT
	            RegId,
	            Name,
	            TaxRegId, 
	            StatId, 
	            ExternalId, 
	            Region_id AS RegionId, 
	            Employees, 
                Turnover, 
	            InstSectorCodeId AS SectorCodeId, 
	            LegalFormId, 
	            DataSource, 
	            StartPeriod,
	            ParentId,
	            IsDeleted,
	            LiqReason,
	            Address_part1 AS AddressPart1,
	            Address_part2 AS AddressPart2,
	            Address_part3 AS AddressPart3,
	            4 AS UnitType
            FROM	dbo.EnterpriseGroups 
	            LEFT JOIN dbo.Address 
		            ON AddressId = Address_id
            ";
    }
}
